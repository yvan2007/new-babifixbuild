import csv
import builtins
import json
import logging
import math
import os
import uuid
from decimal import Decimal

from django.conf import settings
from django.contrib import messages
from django.contrib.auth import authenticate
from django.contrib.auth.decorators import login_required
from django.contrib.auth.models import User
from django.db import transaction
from django.db.models import Avg, Count, Q, Sum
from django.http import HttpResponse, JsonResponse
from django.shortcuts import redirect, render
from django.urls import reverse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_GET, require_http_methods

logger = logging.getLogger(__name__)

# JWT auth - nouveau systeme securise
from .jwt_auth import (
    create_access_token,
    create_refresh_token,
    verify_access_token,
    verify_refresh_token,
    refresh_access_token,
    require_jwt_auth,
    require_jwt_auth_or_refresh,
)
from .auth import require_api_auth  # Backward compat


def _safe_print(*args, **kwargs):
    cleaned = []
    for arg in args:
        text = str(arg)
        cleaned.append(text.encode("cp1252", errors="ignore").decode("cp1252"))
    builtins.print(*cleaned, **kwargs)


print = _safe_print

# Machine a etats stricte — utilisee dans tous les endpoints de changement de statut
RESERVATION_VALID_TRANSITIONS = {
    "En attente": {"Confirmee", "Annulee"},
    "DEMANDE_ENVOYEE": {"DEVIS_EN_COURS", "DEVIS_ENVOYE", "Annulee"},
    "DEVIS_EN_COURS": {"DEVIS_ENVOYE", "Annulee"},
    "DEVIS_ENVOYE": {"DEVIS_ACCEPTE", "DEMANDE_ENVOYEE", "Annulee"},
    "DEVIS_ACCEPTE": {"INTERVENTION_EN_COURS", "Annulee"},
    "INTERVENTION_EN_COURS": {"En attente client", "Terminee", "Annulee"},
    "En attente client": {"Terminee", "Confirmee"},
    "Confirmee": {"En cours", "INTERVENTION_EN_COURS", "Annulee"},
    "En cours": {"En attente client", "Annulee"},
    "Terminee": {"Confirmee", "Annulee"},
}

# ✅ F3: Workflow annulation avec penalites
ANNULATION_RULES = {
    "ANNULE_CLIENT": {
        "before_devis": {"penalty_pct": 0, "refund": True},  # Pas de penalite avant devis
        "after_devis": {"penalty_pct": 0, "refund": True},  # Devis recu mais pas accepte
        "after_accept": {"penalty_pct": 10, "refund": True},  # 10% penalite si annule apres accept
        "after_start": {"penalty_pct": 50, "refund": False},  # 50% si intervention commencee
    },
    "ANNULE_PRESTATAIRE": {
        "before_devis": {"penalty_pct": 0, "refund": True},
        "after_devis": {"penalty_pct": 0, "refund": True},
        "after_accept": {"penalty_pct": 0, "refund": True},  # Pas de penalite prest
        "after_start": {"penalty_pct": 0, "refund": True},
    },
}


def validate_reservation_transition(current_status, new_status):
    """Valide une transition de statut de réservation."""
    valid_next = RESERVATION_VALID_TRANSITIONS.get(current_status, set())
    if new_status not in valid_next:
        return False, list(valid_next)
    return True, []


RESERVATION_STATUS_ALIASES = {
    "PENDING": "En attente",
    "EN ATTENTE": "En attente",
    "CONFIRMED": "Confirmee",
    "CONFIRMEE": "Confirmee",
    "IN_PROGRESS": "En cours",
    "WAITING_CLIENT": "En attente client",
    "DONE": "Terminee",
    "CANCELLED": "Annulee",
}


def normalize_reservation_status(status):
    raw = str(status or "").strip()
    if not raw:
        return raw
    return RESERVATION_STATUS_ALIASES.get(raw.upper(), raw)


def parse_money_amount(value, default="0") -> Decimal:
    raw = str(value if value not in (None, "") else default).strip()
    cleaned = (
        raw.replace("francs CFA", "")
        .replace("F CFA", "")
        .replace("FCFA", "")
        .replace(" ", "")
        .replace(",", ".")
        .strip()
    )
    if not cleaned:
        cleaned = str(default)
    try:
        return Decimal(cleaned)
    except Exception:
        return Decimal(str(default))


def validate_reservation_transition(current_status, new_status):
    """Valide une transition de statut de rÃ©servation."""
    current = normalize_reservation_status(current_status)
    target = normalize_reservation_status(new_status)
    valid_next = RESERVATION_VALID_TRANSITIONS.get(current, set())
    if target not in valid_next:
        return False, sorted(valid_next)
    return True, []


from .auth import create_refresh_token, create_token, require_api_auth, verify_token
from .category_catalog import import_categories_from_catalog
from .constants import CATEGORY_ICON_SLUGS, PAYMENT_METHOD_STATIC
from .push_dispatch import _schedule
from .forms import (
    ActualiteForm,
    CategoryForm,
    ClientForm,
    DisputeForm,
    NotificationForm,
    PaymentForm,
    ProviderForm,
    ReservationForm,
)

from .models import (
    Actualite,
    AdminAuditLog,
    Category,
    Client,
    Conversation,
    DeviceToken,
    Devis,
    Dispute,
    LigneDevis,
    Message,
    Notification,
    Payment,
    Provider,
    PrestataireUnavailability,
    Rating,
    Reservation,
    SiteContent,
    SystemSetting,
    UserProfile,
    WalletTransaction,
    recalc_provider_rating_stats,
)


def _parse_mobile_money_operator(payload: dict, payment_type: str) -> str:
    """Operateur Mobile Money (CI) : uniquement si paiement MOBILE_MONEY."""
    if payment_type != Reservation.PaymentType.MOBILE_MONEY:
        return ""
    raw = (
        str(payload.get("mobile_money_operator", "") or "")
        .upper()
        .replace(" ", "_")
        .replace("-", "_")
    )
    if raw in {"MTN", "MTN_MOBILE_MONEY", "MTN_MONEY"}:
        raw = Reservation.MobileMoneyOperator.MTN_MOMO
    allowed = {
        Reservation.MobileMoneyOperator.ORANGE_MONEY,
        Reservation.MobileMoneyOperator.MTN_MOMO,
        Reservation.MobileMoneyOperator.WAVE,
        Reservation.MobileMoneyOperator.MOOV,
    }
    return raw if raw in allowed else ""


def _demo_seed_enabled() -> bool:
    """
    Données factices (prestataires « Marie Dubois », réservations RES-001, etc.).
    Par défaut : **désactivé** (données 100 % réelles via apps + API).
    Activer uniquement pour tests locaux : BABIFIX_ENABLE_DEMO_SEED=1
    """
    v = (os.getenv("BABIFIX_ENABLE_DEMO_SEED") or "").strip().lower()
    if v in {"1", "true", "yes", "on"}:
        return True
    if v in {"0", "false", "no", "off"}:
        return False
    # Sans variable : jamais de seed démo (même si DEBUG=True)
    return False


def _bootstrap_data():
    """Toujours : paramètres système + contenu vitrine. Le reste = option démo."""
    SystemSetting.objects.get_or_create(pk=1)
    _ensure_site_content_defaults()
    if not _demo_seed_enabled():
        return
    if not Provider.objects.exists():
        Provider.objects.bulk_create(
            [
                Provider(nom="Konan Jean", specialite="Menage & Nettoyage", ville="Abidjan - Cocody", tarif_horaire=5000, statut="Valide", disponible=True, average_rating=4.8, rating_count=34, bio="Professionnel du ménage depuis 6 ans, matériel fourni."),
                Provider(nom="Kone Mariam", specialite="Menage & Nettoyage", ville="Abidjan - Abobo", tarif_horaire=4000, statut="Valide", disponible=True, average_rating=4.5, rating_count=22, bio="Spécialiste grand ménage et repassage."),
                Provider(nom="Bamba Seydou", specialite="Plomberie", ville="Abidjan - Plateau", tarif_horaire=8000, statut="Valide", disponible=True, average_rating=4.7, rating_count=19, bio="Plombier certifié, intervention rapide 7j/7."),
                Provider(nom="Fofana Ibrahim", specialite="Electricite", ville="Abidjan - Yopougon", tarif_horaire=7500, statut="Valide", disponible=True, average_rating=4.9, rating_count=41, bio="Électricien diplômé, installation et dépannage."),
                Provider(nom="Coulibaly Aminata", specialite="Peinture & Ravalement", ville="Abidjan - Marcory", tarif_horaire=6500, statut="Valide", disponible=False, average_rating=4.6, rating_count=15, bio="Peintre décorateur intérieur et extérieur."),
                Provider(nom="Diomande Oumar", specialite="Jardinage", ville="Abidjan - Riviera", tarif_horaire=4500, statut="Valide", disponible=True, average_rating=4.4, rating_count=28, bio="Jardinier paysagiste, entretien et création."),
                Provider(nom="Toure Fatoumata", specialite="Cuisine & Traiteur", ville="Abidjan - Treichville", tarif_horaire=9000, statut="Valide", disponible=True, average_rating=5.0, rating_count=52, bio="Traiteur événementiel, cuisine ivoirienne et internationale."),
                Provider(nom="Soro Lamine", specialite="Menuiserie", ville="Abidjan - Adjame", tarif_horaire=7000, statut="Valide", disponible=True, average_rating=4.3, rating_count=11, bio="Menuisier ébéniste, fabrication sur mesure."),
                Provider(nom="Gbagbo Arsene", specialite="Climatisation", ville="Abidjan - Cocody", tarif_horaire=12000, statut="Valide", disponible=True, average_rating=4.7, rating_count=38, bio="Technicien froid, installation et maintenance clim."),
                Provider(nom="Traore Nassira", specialite="Demenagement", ville="Abidjan - Port-Bouet", tarif_horaire=15000, statut="Valide", disponible=False, average_rating=4.2, rating_count=9, bio="Déménagements résidentiels et professionnels."),
            ]
        )
    if not Reservation.objects.exists():
        Reservation.objects.bulk_create(
            [
                Reservation(
                    reference="RES-001",
                    client="Akouabi Paul",
                    prestataire="Konan Jean",
                    montant="15000",
                    statut="Terminee",
                ),
                Reservation(
                    reference="RES-002",
                    client="Bamba Claire",
                    prestataire="Kone Mariam",
                    montant="25000",
                    statut="DEVIS_ACCEPTE",
                ),
                Reservation(
                    reference="RES-003",
                    client="Coulibaly Thomas",
                    prestataire="Fofana Ibrahim",
                    montant="20000",
                    statut="DEVIS_ENVOYE",
                ),
            ]
        )
    if not Dispute.objects.exists():
        Dispute.objects.bulk_create(
            [
                Dispute(
                    reference="LIT-001",
                    motif="Service non conforme",
                    client="Julie Rousseau",
                    prestataire="Lucas Petit",
                    priorite="Haute",
                ),
                Dispute(
                    reference="LIT-002",
                    motif="Prestataire non presente",
                    client="Marc Leroy",
                    prestataire="Emma Moreau",
                    priorite="Haute",
                ),
                Dispute(
                    reference="LIT-003",
                    motif="Retard important",
                    client="Anne Durand",
                    prestataire="Jean Martin",
                    priorite="Moyenne",
                ),
            ]
        )
    if not Client.objects.exists():
        Client.objects.bulk_create(
            [
                Client(
                    nom="Pierre Durand",
                    email="pierre@email.com",
                    ville="Paris",
                    reservations=24,
                    depense=Decimal("2450"),
                ),
                Client(
                    nom="Claire Rousseau",
                    email="claire@email.com",
                    ville="Lyon",
                    reservations=18,
                    depense=Decimal("1890"),
                ),
                Client(
                    nom="Thomas Blanc",
                    email="thomas@email.com",
                    ville="Marseille",
                    reservations=31,
                    depense=Decimal("3200"),
                ),
            ]
        )
    from decimal import Decimal

    if not Payment.objects.exists():
        Payment.objects.bulk_create(
            [
                Payment(
                    reference="PAY-2026-001",
                    client="Pierre Durand",
                    prestataire="Marie Dubois",
                    montant=Decimal("8950.00"),
                    commission=Decimal("895.00"),
                    etat=Payment.State.COMPLETE,
                ),
                Payment(
                    reference="PAY-2026-002",
                    client="Claire Rousseau",
                    prestataire="Jean Martin",
                    montant=Decimal("14500.00"),
                    commission=Decimal("1450.00"),
                    etat=Payment.State.PENDING,
                ),
                Payment(
                    reference="PAY-2026-003",
                    client="Thomas Blanc",
                    prestataire="Sophie Bernard",
                    montant=Decimal("21000.00"),
                    commission=Decimal("2100.00"),
                    etat=Payment.State.COMPLETE,
                ),
            ]
        )
    if not Category.objects.exists():
        Category.objects.bulk_create(
            [
                Category(nom="Menage & Nettoyage", icone_slug="nettoyage", services=24, reservations=856, actif=True, ordre_affichage=1),
                Category(nom="Plomberie", icone_slug="goutte", services=12, reservations=412, actif=True, ordre_affichage=2),
                Category(nom="Electricite", icone_slug="eclair", services=10, reservations=378, actif=True, ordre_affichage=3),
                Category(nom="Peinture & Ravalement", icone_slug="pinceau", services=8, reservations=211, actif=True, ordre_affichage=4),
                Category(nom="Jardinage", icone_slug="tondeuse", services=9, reservations=194, actif=True, ordre_affichage=5),
                Category(nom="Cuisine & Traiteur", icone_slug="traiteur", services=7, reservations=163, actif=True, ordre_affichage=6),
                Category(nom="Demenagement", icone_slug="demenagement", services=5, reservations=88, actif=True, ordre_affichage=7),
                Category(nom="Menuiserie", icone_slug="menuiserie", services=6, reservations=102, actif=True, ordre_affichage=8),
                Category(nom="Climatisation", icone_slug="climatisation", services=4, reservations=95, actif=True, ordre_affichage=9),
                Category(nom="Multiservices", icone_slug="multiservices", services=3, reservations=67, actif=True, ordre_affichage=10),
            ]
        )
    if not Notification.objects.exists():
        Notification.objects.bulk_create(
            [
                Notification(title="Nouveau litige ouvert", time="Il y a 5 min"),
                Notification(
                    title="Prestataire valide avec succes", time="Il y a 18 min"
                ),
                Notification(title="Demande de support client", time="Il y a 42 min"),
            ]
        )
    _bootstrap_users()
    _link_demo_providers()
    _link_demo_categories()


def _bootstrap_users():
    defaults = [
        ("client_demo", "client123", UserProfile.Role.CLIENT),
        ("prestataire_demo", "prest123", UserProfile.Role.PRESTATAIRE),
        ("admin_demo", "admin123", UserProfile.Role.ADMIN),
    ]
    for username, password, role in defaults:
        user, created = User.objects.get_or_create(
            username=username, defaults={"is_active": True}
        )
        if created:
            user.set_password(password)
            user.save(update_fields=["password"])
        profile, _ = UserProfile.objects.get_or_create(
            user=user, defaults={"role": role, "active": True}
        )
        if profile.role != role:
            profile.role = role
            profile.save(update_fields=["role"])


def _link_demo_providers():
    u = User.objects.filter(username="prestataire_demo").first()
    if u:
        p = Provider.objects.filter(nom="Jean Martin").first()
        if p and p.user_id is None:
            p.user = u
            p.save(update_fields=["user"])
    marie = Provider.objects.filter(nom="Marie Dubois").first()
    if marie and marie.user_id is None:
        u2, created = User.objects.get_or_create(
            username="prestataire_marie",
            defaults={"is_active": True},
        )
        if created:
            u2.set_password("marie123")
            u2.save(update_fields=["password"])
        UserProfile.objects.get_or_create(
            user=u2,
            defaults={"role": UserProfile.Role.PRESTATAIRE, "active": True},
        )
        marie.user = u2
        marie.save(update_fields=["user"])


def _link_demo_categories():
    """Lie les prestataires a leur categorie (matching exact nom==specialite) et active is_approved."""
    # Correspondance exacte specialite → categorie
    cat_by_nom = {c.nom: c for c in Category.objects.all()}
    providers_without_cat = Provider.objects.filter(category__isnull=True).exclude(specialite="")
    for p in providers_without_cat:
        cat = cat_by_nom.get((p.specialite or "").strip())
        if cat:
            p.category = cat
            p.save(update_fields=["category"])
    # Synchroniser is_approved avec statut Valide
    Provider.objects.filter(statut=Provider.Status.VALID).update(is_approved=True)


def _static_absolute(request, relative_path: str) -> str:
    """URL absolue vers un fichier dans STATIC (ex. category-icons/maison.svg)."""
    if not relative_path:
        return ""
    p = relative_path.lstrip("/")
    url = f"{settings.STATIC_URL.rstrip('/')}/{p}"
    if request is not None:
        try:
            return request.build_absolute_uri(url)
        except Exception:
            pass
    return url


def _premium_badge_label(provider) -> str:
    """Libellé du badge premium ('' si standard). Lecture seule, sans écriture BDD."""
    try:
        from .services.provider_subscription_service import PREMIUM_TIERS
        if getattr(provider, "is_premium", False):
            until = getattr(provider, "premium_until", None)
            from django.utils import timezone as _tz
            if until and until < _tz.now():
                return ""
            return PREMIUM_TIERS.get(provider.premium_tier or "", {}).get("badge", "")
    except Exception:
        pass
    return ""


def _category_icon_url(request, category):
    if not category:
        return ""
    if (category.icone_url or "").strip().startswith("http"):
        return category.icone_url.strip()
    slug = (category.icone_slug or "").strip()
    if slug:
        return _static_absolute(request, f"category-icons/{slug}.svg")
    return (category.icone_url or "").strip()


def _ensure_site_content_defaults():
    """Clés vitrine — valeurs vides par défaut (remplies par l’admin)."""
    pairs = [
        ("hero_title", ""),
        ("hero_subtitle", ""),
        ("store_ios_client", ""),
        ("store_android_client", ""),
        ("store_ios_prestataire", ""),
        ("store_android_prestataire", ""),
        ("contact_admin_email", "support@babifix.ci"),
    ]
    for key, val in pairs:
        SiteContent.objects.get_or_create(key=key, defaults={"value": val})


import unicodedata as _ud
import re as _re


def _normalize_category_key(s: str) -> str:
    """Normalise un nom de catégorie → clé filtre Flutter (UPPER + underscores, max 24)."""
    s = _ud.normalize("NFC", (s or "").strip()).upper()
    s = _re.sub(r"\s+", "_", s)
    return s[:24]


def _safe_photo_url(url: str, request=None) -> str:
    """
    Retourne l'URL normalisée.
    - Si HTTP/HTTPS → tel quel
    - Si /media/... → absolu si request fourni, sinon relatif
    - Si data:image (legacy) → tel quel
    """
    if not url:
        return ""
    s = url.strip()
    if s.startswith("http://") or s.startswith("https://"):
        return s
    if s.startswith("/media/") or s.startswith("media/"):
        if request is not None:
            return request.build_absolute_uri(s if s.startswith("/") else f"/{s}")
        return s
    if s.startswith("data:image"):
        return s
    return ""


def _decode_and_save_media(b64_data: str, subfolder: str, prefix: str) -> str:
    """
    Décode une data URL base64 et enregistre le fichier via le stockage Django
    par défaut.

    Quand CLOUDINARY_URL est défini, STORAGES["default"] pointe vers Cloudinary :
    le fichier est alors envoyé sur Cloudinary et l'URL retournée est PERSISTANTE
    (https://res.cloudinary.com/...). Sinon, on retombe sur le disque local
    (MEDIA_ROOT) — éphémère sur Render, OK en développement.

    Retourne l'URL du fichier, ou '' si les données sont invalides.
    """
    import base64 as _b64
    import re as _re

    from django.core.files.base import ContentFile
    from django.core.files.storage import default_storage

    if not b64_data or not b64_data.startswith("data:"):
        return ""
    # Extraire le MIME type et les données
    match = _re.match(r"data:(image/\w+|video/\w+);base64,(.+)", b64_data, _re.DOTALL)
    if not match:
        return ""
    mime_type = match.group(1)
    raw_b64 = match.group(2).strip()
    # Déterminer l'extension
    ext_map = {
        "image/jpeg": "jpg", "image/jpg": "jpg", "image/png": "png",
        "image/gif": "gif", "image/webp": "webp",
        "video/mp4": "mp4", "video/quicktime": "mov", "video/webm": "webm",
    }
    ext = ext_map.get(mime_type, "bin")
    try:
        file_bytes = _b64.b64decode(raw_b64)
    except Exception:
        return ""

    name = f"providers/{subfolder}/{prefix}_{uuid.uuid4().hex[:12]}.{ext}"
    is_video = mime_type.startswith("video/")

    # Stockage par défaut = Cloudinary si configuré, sinon disque local.
    storage = default_storage
    using_cloudinary = "cloudinary" in type(storage).__module__.lower()
    # Cloudinary distingue images et vidéos : route les vidéos vers le bon backend.
    if is_video and using_cloudinary:
        try:
            from cloudinary_storage.storage import VideoMediaCloudinaryStorage

            storage = VideoMediaCloudinaryStorage()
        except Exception:
            storage = default_storage

    try:
        saved_name = storage.save(name, ContentFile(file_bytes))
        return storage.url(saved_name)
    except Exception as exc:
        logger.warning(
            "Echec enregistrement media via storage (%s) — repli sur disque local",
            exc,
        )
        # Repli : disque local (comportement historique).
        save_dir = os.path.join(settings.MEDIA_ROOT, "providers", subfolder)
        os.makedirs(save_dir, exist_ok=True)
        filename = os.path.basename(name)
        filepath = os.path.join(save_dir, filename)
        try:
            with open(filepath, "wb") as f:
                f.write(file_bytes)
        except OSError:
            return ""
        return f"{settings.MEDIA_URL}providers/{subfolder}/{filename}"


def _is_in_cote_ivoire(lat, lon):
    """Pré-filtre bbox + ray-casting polygon pour vérifier si (lat, lon) est en CI."""
    try:
        lat = float(lat)
        lon = float(lon)
    except (TypeError, ValueError):
        return False
    if not (4.0 <= lat <= 11.0 and -9.0 <= lon <= -2.0):
        return False
    polygon = [
        (4.357, -7.540), (4.384, -7.683), (4.420, -7.917),
        (4.477, -8.194), (4.556, -8.424), (4.622, -8.537),
        (4.721, -8.584), (4.856, -8.600), (6.451, -8.660),
        (7.550, -8.500), (8.500, -8.600), (9.362, -8.536),
        (10.175, -7.985), (10.686, -6.832), (10.755, -5.928),
        (10.745, -5.190), (10.385, -4.430), (9.718, -4.241),
        (9.096, -3.805), (8.581, -3.000), (7.772, -2.590),
        (6.949, -2.659), (6.214, -3.086), (5.527, -2.674),
        (5.131, -2.586), (5.108, -3.147), (5.058, -3.550),
        (4.921, -3.997), (4.886, -4.498), (4.799, -5.249),
        (4.698, -5.755), (4.662, -6.754), (4.537, -7.192),
    ]
    inside = False
    j = len(polygon) - 1
    for i in range(len(polygon)):
        lat_i, lon_i = polygon[i]
        lat_j, lon_j = polygon[j]
        if (lon_i > lon) != (lon_j > lon):
            intersect_at = lat_j + (lat_i - lat_j) * (lon - lon_j) / (lon_i - lon_j)
            if lat < intersect_at:
                inside = not inside
        j = i
    return inside


def _provider_distance_km(client_lat, client_lon, provider):
    if client_lat is None or client_lon is None:
        return None
    if not _is_in_cote_ivoire(client_lat, client_lon):
        return None
    plat = getattr(provider, 'latitude', None)
    plon = getattr(provider, 'longitude', None)
    if plat is None or plon is None:
        plat = getattr(provider, 'service_latitude', None)
        plon = getattr(provider, 'service_longitude', None)
    if plat is None or plon is None or not _is_in_cote_ivoire(plat, plon):
        return None
    try:
        from math import asin, cos, radians, sin, sqrt
        lat1, lon1, lat2, lon2 = radians(float(client_lat)), radians(float(client_lon)), radians(float(plat)), radians(float(plon))
        dphi, dlmb = lat2 - lat1, lon2 - lon1
        a = sin(dphi / 2) ** 2 + cos(lat1) * cos(lat2) * sin(dlmb / 2) ** 2
        return round(6371 * 2 * asin(min(1.0, sqrt(a))), 1)
    except (TypeError, ValueError):
        return None


def _services_from_db(request=None, client_lat=None, client_lon=None):
    """
    Prestataires validés uniquement — aucune donnée fictive.
    Prix = tarif_horaire (FCFA) saisi par le prestataire ; 0 si non défini.
    Note = moyenne réelle uniquement (sinon 0).
    Si client_lat/client_lon fournis, calcule et inclut distance_km.
    """
    qs = Provider.objects.filter(
        statut=Provider.Status.VALID, is_approved=True
    ).select_related("category")
    out = []
    colors = ["#244B5A", "#2A3340", "#3A2F43", "#303D2F"]
    for p in qs:
        cat_label = (p.category.nom if p.category_id else None) or (
            p.specialite or "Service"
        )
        spec = _normalize_category_key(cat_label)
        base_price = 0
        if p.rating_count and p.average_rating is not None:
            stars = round(float(p.average_rating), 1)
        else:
            stars = 0.0
        out.append(
            {
                "title": f"{p.specialite} — {p.nom}",
                "category": spec,
                "category_filter_key": spec,
                "duration": "",
                "price": int(base_price),
                "rating": stars,
                "rating_count": int(p.rating_count or 0),
                "verified": True,
                "color": colors[p.id % len(colors)],
                "provider_id": int(p.id),
                "image_url": _safe_photo_url(p.photo_portrait_url or "", request),
                "disponible": p.disponible,
                "distance_km": _provider_distance_km(client_lat, client_lon, p),
                "category_nom": (p.category.nom if p.category_id else "") or "",
                "category_icone_slug": (p.category.icone_slug or "").strip()
                if p.category_id
                else "",
                "category_icone_url": _category_icon_url(
                    request, p.category if p.category_id else None
                )
                if p.category_id
                else "",
            }
        )
    return out


def _prestataire_provider_for_user(uid):
    return Provider.objects.filter(user_id=uid).first()


def _prestataire_can_message(prestataire_user_id):
    return Provider.objects.filter(
        user_id=prestataire_user_id,
        statut=Provider.Status.VALID,
    ).exists()


def _msg_dict(request, m):
    img = ""
    if m.image:
        try:
            img = request.build_absolute_uri(m.image.url)
        except Exception:
            img = str(m.image)
    audio_url = ""
    audio_file = getattr(m, "audio", None)
    if audio_file:
        try:
            audio_url = request.build_absolute_uri(audio_file.url)
        except Exception:
            audio_url = str(audio_file)
    return {
        "id": int(m.id),
        "body": m.body or "",
        "image_url": img,
        "audio_url": audio_url,
        "audio_duration": int(getattr(m, "audio_duration", 0) or 0),
        "sender_id": int(m.sender_id),
        "created_at": m.created_at.isoformat(),
        "reply_to_id": int(m.reply_to_id) if m.reply_to_id else None,
        "lu": bool(getattr(m, "lu", False)),
        "deleted": bool(getattr(m, "deleted", False)),
        # Phase C — type de message + données structurées (carte devis,
        # événement système). Permet au chat d'afficher la carte devis figée.
        "kind": getattr(m, "kind", "USER") or "USER",
        "payload_json": getattr(m, "payload_json", None),
    }


def _mark_conversation_messages_read(conv: Conversation, reader_uid: int) -> None:
    """Marque comme lus les messages dont le destinataire est reader_uid."""
    Message.objects.filter(conversation=conv).exclude(sender_id=reader_uid).update(
        lu=True
    )


def _conversation_unread_for_user(conv: Conversation, uid: int) -> int:
    return (
        Message.objects.filter(conversation=conv)
        .exclude(sender_id=uid)
        .filter(lu=False)
        .count()
    )


def _unread_messages_total_for_user(uid: int) -> int:
    conv_ids = Conversation.objects.filter(
        Q(client_id=uid) | Q(prestataire_id=uid)
    ).values_list("id", flat=True)
    return (
        Message.objects.filter(conversation_id__in=conv_ids)
        .exclude(sender_id=uid)
        .filter(lu=False)
        .count()
    )


def _notify_actualite_reach(request) -> None:
    """Affiche un message indiquant la portée réelle du push d'une actualité publiée."""
    try:
        from .fcm_backend import _ensure_firebase_app

        target_ids = UserProfile.objects.filter(
            role__in=(UserProfile.Role.CLIENT, UserProfile.Role.PRESTATAIRE),
            active=True,
        ).values_list("user_id", flat=True)
        nb_devices = (
            DeviceToken.objects.filter(user_id__in=target_ids)
            .values("token")
            .distinct()
            .count()
        )
        if not _ensure_firebase_app():
            messages.warning(
                request,
                "⚠️ Firebase non configuré : aucune notification push ne sera "
                "envoyée (la clé de service Firebase est absente).",
            )
        elif nb_devices == 0:
            messages.warning(
                request,
                "ℹ️ Aucun appareil enregistré pour le moment : personne ne recevra "
                "de notification. Les utilisateurs doivent ouvrir/rouvrir "
                "l'application (version récente) pour enregistrer leur appareil.",
            )
        else:
            messages.success(
                request,
                f"📲 Notification push envoyée à {nb_devices} appareil(s) enregistré(s).",
            )
    except Exception as exc:  # pragma: no cover - retour best-effort
        messages.warning(
            request,
            f"Impossible d'estimer la portée de la notification : {exc}",
        )


def _actualite_to_json(request, a: Actualite, summary: bool = False) -> dict:
    img = ""
    if a.image:
        try:
            img = request.build_absolute_uri(a.image.url)
        except Exception:
            img = ""
    desc = a.description or ""
    out = {
        "id": int(a.pk),
        "titre": a.titre,
        "description": desc
        if not summary
        else ((desc[:240] + "…") if len(desc) > 240 else desc),
        "image_url": img,
        "categorie_tag": a.categorie_tag,
        "icone_key": a.icone_key or "",
        "date_publication": a.date_publication.isoformat(),
        "cible": a.cible,
    }
    return out


def _build_kanban_reservations():
    # Pipeline COMPLET (les 11 statuts du modèle, dans l'ordre logique). Avant,
    # seuls 7 statuts étaient affichés → les réservations « Confirmee »,
    # « En attente », « En cours » ou « Annulee » n'apparaissaient dans AUCUNE
    # colonne, donnant un kanban vide (« rien ne vient »).
    statuses = [
        "En attente",
        "DEMANDE_ENVOYEE",
        "DEVIS_EN_COURS",
        "DEVIS_ENVOYE",
        "DEVIS_ACCEPTE",
        "Confirmee",
        "INTERVENTION_EN_COURS",
        "En cours",
        "En attente client",
        "Terminee",
        "Annulee",
    ]
    kanban = {}
    for s in statuses:
        kanban[s] = list(
            Reservation.objects.filter(statut=s)
            .select_related("client_user", "assigned_provider")
            .order_by("-id")[:20]
        )
    # Filet de sécurité : toute réservation dont le statut n'est PAS prévu
    # ci-dessus est regroupée dans une colonne « Autres » — on ne cache
    # jamais une réservation.
    autres = list(
        Reservation.objects.exclude(statut__in=statuses)
        .select_related("client_user", "assigned_provider")
        .order_by("-id")[:20]
    )
    if autres:
        kanban["Autres"] = autres
    return kanban


def _build_kanban_providers():
    statuses_labels = {k: v for k, v in Provider.Status.choices}
    kanban = {}
    for code, label in statuses_labels.items():
        kanban[label] = list(
            Provider.objects.filter(statut=code)[:20]
        )
    return kanban


def _build_kanban_paiements():
    """Colonnes du Kanban Paiements, groupées par état (les 3 états du modèle
    Payment) + une colonne « Autres » filet de sécurité."""
    etats = ["Pending", "Complete", "Litige"]
    kanban = {}
    for e in etats:
        kanban[e] = list(
            Payment.objects.filter(etat=e)
            .select_related("reservation")
            .order_by("-id")[:20]
        )
    autres = list(
        Payment.objects.exclude(etat__in=etats)
        .select_related("reservation")
        .order_by("-id")[:20]
    )
    if autres:
        kanban["Autres"] = autres
    return kanban


def _dashboard_forms_context(request, section):
    """Formulaires CRUD intégrés au dashboard (pas django-admin)."""
    ctx = {}
    if section == "prestataires":
        ctx["provider_view"] = request.GET.get("view", "table")
        ctx["kanban_providers"] = _build_kanban_providers() if ctx["provider_view"] == "kanban" else {}
        eid = request.GET.get("edit_provider")
        if eid and str(eid).isdigit():
            try:
                inst = Provider.objects.get(pk=int(eid))
                ctx["provider_form"] = ProviderForm(instance=inst)
                ctx["edit_provider_id"] = inst.pk
            except Provider.DoesNotExist:
                ctx["provider_form"] = ProviderForm()
        else:
            ctx["provider_form"] = ProviderForm()
    elif section == "clients":
        eid = request.GET.get("edit_client")
        if eid and str(eid).isdigit():
            try:
                inst = Client.objects.get(pk=int(eid))
                ctx["client_form"] = ClientForm(instance=inst)
                ctx["edit_client_id"] = inst.pk
            except Client.DoesNotExist:
                ctx["client_form"] = ClientForm()
        else:
            ctx["client_form"] = ClientForm()
    elif section == "reservations":
        eid = request.GET.get("edit_reservation")
        ctx["reservation_form"] = None
        ctx["reservation_view"] = request.GET.get("view", "table")
        if eid and str(eid).isdigit():
            try:
                inst = Reservation.objects.get(pk=int(eid))
                ctx["reservation_form"] = ReservationForm(instance=inst)
                ctx["edit_reservation_id"] = inst.pk
            except Reservation.DoesNotExist:
                pass
        _kb = _build_kanban_reservations() if ctx["reservation_view"] == "kanban" else {}
        ctx["kanban_reservations"] = _kb
        ctx["kanban_total"] = sum(len(v) for v in _kb.values())
    elif section == "kanban":
        ctx["reservation_view"] = "kanban"
        _kb = _build_kanban_reservations()
        ctx["kanban_reservations"] = _kb
        ctx["kanban_total"] = sum(len(v) for v in _kb.values())
    elif section == "litiges":
        eid = request.GET.get("edit_litige")
        if eid and str(eid).isdigit():
            try:
                inst = Dispute.objects.get(pk=int(eid))
                ctx["litige_form"] = DisputeForm(instance=inst)
                ctx["edit_litige_id"] = inst.pk
            except Dispute.DoesNotExist:
                ctx["litige_form"] = DisputeForm()
        else:
            ctx["litige_form"] = DisputeForm()
    elif section == "paiements":
        eid = request.GET.get("edit_paiement")
        if eid and str(eid).isdigit():
            try:
                inst = Payment.objects.get(pk=int(eid))
                ctx["paiement_form"] = PaymentForm(instance=inst)
                ctx["edit_paiement_id"] = inst.pk
            except Payment.DoesNotExist:
                ctx["paiement_form"] = PaymentForm()
        else:
            ctx["paiement_form"] = PaymentForm()
        # Toggle Tableau / Kanban de la section paiements. AVANT : la vue ne
        # définissait ni `paiement_view` ni `kanban_paiements` → cliquer
        # « Kanban » ne faisait rien (le board ne s'affichait jamais).
        ctx["paiement_view"] = request.GET.get("view", "table")
        ctx["kanban_paiements"] = (
            _build_kanban_paiements() if ctx["paiement_view"] == "kanban" else {}
        )
    elif section == "categories":
        ctx["category_icon_slugs"] = CATEGORY_ICON_SLUGS
        eid = request.GET.get("edit_category")
        if eid and str(eid).isdigit():
            try:
                inst = Category.objects.get(pk=int(eid))
                ctx["category_form"] = CategoryForm(instance=inst)
                ctx["edit_category_id"] = inst.pk
            except Category.DoesNotExist:
                ctx["category_form"] = CategoryForm()
        else:
            ctx["category_form"] = CategoryForm()
    elif section == "notifications":
        eid = request.GET.get("edit_notification")
        if eid:
            ctx["edit_notification_id"] = eid
            if str(eid).isdigit():
                try:
                    inst = Notification.objects.get(pk=int(eid))
                    ctx["notification_form"] = NotificationForm(instance=inst)
                except Notification.DoesNotExist:
                    ctx["notification_form"] = NotificationForm()
            else:
                ctx["notification_form"] = NotificationForm()
        else:
            ctx["notification_form"] = NotificationForm()
    elif section == "actualites":
        eid = request.GET.get("edit_actualite")
        if eid:
            ctx["edit_actualite_id"] = eid
            if str(eid).isdigit():
                try:
                    inst = Actualite.objects.get(pk=int(eid))
                    ctx["actualite_form"] = ActualiteForm(instance=inst)
                except Actualite.DoesNotExist:
                    ctx["actualite_form"] = ActualiteForm()
            else:
                ctx["actualite_form"] = ActualiteForm()
        else:
            ctx["actualite_form"] = ActualiteForm()
    elif section == "payouts":
        # Retraits prestataires à traiter (en attente d'abord, puis récents).
        from django.db.models import Case, When, Value, IntegerField

        po_status = (request.GET.get("pstatus") or "").strip()
        base_qs = WalletTransaction.objects.filter(tx_type="debit")
        ctx["payout_status_filter"] = po_status
        ctx["payout_stats"] = {
            "count": base_qs.count(),
            "pending": base_qs.filter(status="pending").count(),
            "paid": base_qs.filter(status="success").count(),
            "failed": base_qs.filter(status="failed").count(),
            "total_paid": base_qs.filter(status="success").aggregate(
                s=Sum("amount_fcfa"))["s"] or 0,
        }
        po_qs = base_qs.select_related("provider")
        if po_status:
            po_qs = po_qs.filter(status=po_status)
        ctx["payout_withdrawals"] = list(
            po_qs.order_by(
                Case(When(status="pending", then=Value(0)), default=Value(1),
                     output_field=IntegerField()),
                "-created_at",
            )[:100]
        )
    elif section == "finances":
        # Vue financière complète (commissions, versements, soldes, remboursements).
        ctx["finance"] = _finance_overview()
        # Dossiers de remboursement à traiter (litige tranché en faveur du client,
        # annulation…) : l'admin peut déclencher le virement ou marquer payé.
        ctx["finance_refunds"] = list(
            Reservation.objects.filter(refund_owed_fcfa__gt=0)
            .exclude(refund_status="paid")
            .order_by("-id")[:100]
        )
        # Détail horodaté des derniers paiements encaissés (brut / commission /
        # net) — pour tracer chaque transaction avec sa date et son heure.
        finance_payments = []
        for p in Payment.objects.order_by("-created_at")[:50]:
            brut = _safe_decimal(p.montant)
            comm = _safe_decimal(p.commission)
            finance_payments.append({
                "reference": p.reference,
                "client": p.client,
                "prestataire": p.prestataire,
                "brut": brut,
                "commission": comm,
                "net": brut - comm,
                "type_paiement": p.type_paiement,
                "etat": p.etat,
                "created_at": p.created_at,
            })
        ctx["finance_payments"] = finance_payments
        # Détail horodaté des versements (retraits) prestataires.
        ctx["finance_versements"] = list(
            WalletTransaction.objects.filter(tx_type="debit")
            .select_related("provider")
            .order_by("-created_at")[:50]
        )
    return ctx


def _finance_overview():
    """Vue financière complète pour l'admin : commissions (revenus BABIFIX),
    versements prestataires, soldes wallet, remboursements + réconciliation."""
    from decimal import Decimal as _D
    from django.db.models import Sum

    Z = _D("0")

    def _wt(**f):
        return WalletTransaction.objects.filter(**f).aggregate(
            s=Sum("amount_fcfa")
        )["s"] or Z

    # ── Versements prestataires (retraits = débits du wallet) ──
    withdrawals_paid = _wt(tx_type="debit", status="success")
    withdrawals_inflight = _wt(tx_type="debit", status="pending")
    alert_withdrawals_failed = WalletTransaction.objects.filter(
        tx_type="debit", status="failed"
    ).count()
    alert_withdrawals_inflight = WalletTransaction.objects.filter(
        tx_type="debit", status="pending"
    ).count()

    # ── Mouvements wallet (crédits/remboursements) ──
    wallet_credits = _wt(tx_type="credit", status="success")
    wallet_refunds = _wt(tx_type="refund", status="success")
    wallet_balances = Provider.objects.aggregate(s=Sum("solde_fcfa"))["s"] or Z
    wallet_expected = wallet_credits + wallet_refunds - withdrawals_paid - withdrawals_inflight
    wallet_ecart = wallet_balances - wallet_expected
    wallet_ok = abs(wallet_ecart) <= _D("1")

    # ── Commission BABIFIX = TON revenu réel ──────────────────────────────
    # On somme le LEDGER de revenus (PlatformRevenue source=commission) et non
    # `Payment.commission` qui n'est pas renseigné (=0) → total faux à 0 FCFA.
    from .models import PlatformRevenue

    commission_total = PlatformRevenue.objects.filter(
        source="commission"
    ).aggregate(s=Sum("amount_fcfa"))["s"] or Z
    completed_payments = Payment.objects.filter(etat="Complete").count()

    # ── Remboursements clients (depuis Reservation) ──
    refunds_owed_qs = Reservation.objects.filter(refund_owed_fcfa__gt=0).exclude(
        refund_status="paid"
    )
    refunds_owed_total = refunds_owed_qs.aggregate(s=Sum("refund_owed_fcfa"))["s"] or Z
    refunds_paid_qs = Reservation.objects.filter(
        refund_status="paid", refund_owed_fcfa__gt=0
    )
    refunds_paid_total = refunds_paid_qs.aggregate(s=Sum("refund_owed_fcfa"))["s"] or Z

    return {
        "revenue_total": commission_total,
        "commission_total": commission_total,
        "commission_count": completed_payments,
        "withdrawals_paid": withdrawals_paid,
        "withdrawals_inflight": withdrawals_inflight,
        "wallet_balances": wallet_balances,
        "wallet_credits": wallet_credits,
        "wallet_refunds": wallet_refunds,
        "wallet_expected": wallet_expected,
        "wallet_ecart": wallet_ecart,
        "wallet_ok": wallet_ok,
        "refunds_owed_total": refunds_owed_total,
        "refunds_owed_count": refunds_owed_qs.count(),
        "refunds_paid_total": refunds_paid_total,
        "refunds_paid_count": refunds_paid_qs.count(),
        "alert_withdrawals_failed": alert_withdrawals_failed,
        "alert_withdrawals_inflight": alert_withdrawals_inflight,
        "alert_refunds_failed": Reservation.objects.filter(refund_status="failed").count(),
        "alert_refunds_manual": Reservation.objects.filter(refund_status="manual").count(),
        "revenue_by_source": [
            {
                "source": "Commissions (Mobile Money)",
                "total": commission_total,
                "count": completed_payments,
            },
        ],
    }


def _dashboard_kpi_payload():
    """KPI pour le tableau de bord (réutilisé par la page complète et le fragment HTMX)."""
    conv_n = Conversation.objects.count()

    # Réservation « active » = toute réservation NON terminale (toutes les
    # demandes en cours comptent : DEMANDE_ENVOYEE, DEVIS_*, En cours, etc.).
    # L'ancien filtre ["En attente","Confirmee"] ratait les nouvelles demandes
    # (statut par défaut DEMANDE_ENVOYEE) → le compteur restait à 0.
    _TERMINAL = ["Terminee", "Annulee"]
    # Source de vérité = UserProfile (tout compte créé par les apps). Les tables
    # Provider/Client sont secondaires : un prestataire n'a une ligne Provider
    # qu'après le KYC, donc les compter raterait les inscrits récents (→ 0).
    # On prend le maximum entre les deux pour rester juste dans tous les cas.
    profiles_providers = UserProfile.objects.filter(
        role=UserProfile.Role.PRESTATAIRE
    ).count()
    profiles_clients = UserProfile.objects.filter(
        role=UserProfile.Role.CLIENT
    ).count()
    total_providers = max(Provider.objects.count(), profiles_providers)
    pending_providers = Provider.objects.filter(statut="En attente").count()
    total_reservations = Reservation.objects.count()
    active_reservations = Reservation.objects.exclude(statut__in=_TERMINAL).count()
    done_reservations = Reservation.objects.filter(statut="Terminee").count()
    total_clients = max(Client.objects.count(), profiles_clients)
    payments_count = Payment.objects.count()
    open_disputes = Dispute.objects.filter(decision="En cours").count()

    # warn=True → carte avec indicateur orange « traitement requis » (éléments
    # qui demandent une action admin : prestataires en attente, litiges).
    stats = [
        {"label": "Prestataires (total)", "value": total_providers, "icon": "user", "warn": False},
        {"label": "Prestataires en attente", "value": pending_providers, "icon": "clock", "warn": True},
        {"label": "Clients inscrits", "value": total_clients, "icon": "users", "warn": False},
        {"label": "Réservations (total)", "value": total_reservations, "icon": "calendar", "warn": False},
        {"label": "Réservations actives", "value": active_reservations, "icon": "activity", "warn": False},
        {"label": "Réservations terminées", "value": done_reservations, "icon": "check", "warn": False},
        {"label": "Paiements enregistrés", "value": payments_count, "icon": "card", "warn": False},
        {"label": "Litiges ouverts", "value": open_disputes, "icon": "alert", "warn": True},
        {"label": "Conversations actives", "value": conv_n, "icon": "chat", "warn": False},
    ]
    kpi = {
        "total_providers": total_providers,
        "pending_providers": pending_providers,
        "total_clients": total_clients,
        "total_reservations": total_reservations,
        "active_reservations": active_reservations,
        "done_reservations": done_reservations,
        "open_disputes": open_disputes,
        "payments_count": payments_count,
        "conversations": conv_n,
    }
    kpi_chart = {
        "labels": [
            "Prestataires",
            "Clients",
            "Réservations actives",
            "Terminées",
            "Paiements",
            "Litiges",
        ],
        "data": [
            total_providers,
            total_clients,
            active_reservations,
            done_reservations,
            payments_count,
            open_disputes,
        ],
    }
    return stats, kpi, kpi_chart


def _sync_missing_clients():
    """Crée les enregistrements Client manquants pour les UserProfile de rôle CLIENT.
    Appelé à chaque chargement de la liste clients pour rattraper les inscriptions passées.
    """
    existing_emails = set(Client.objects.values_list("email", flat=True))
    profiles = UserProfile.objects.filter(role=UserProfile.Role.CLIENT).select_related(
        "user"
    )
    to_create = []
    for profile in profiles:
        user = profile.user
        client_email = user.email or f"{user.username}"
        if client_email not in existing_emails:
            nb_res = Reservation.objects.filter(client_user=user).count()
            total_fcfa = (
                Reservation.objects.filter(
                    client_user=user, statut=Reservation.Status.DONE
                ).aggregate(t=Sum("montant"))["t"]
                or 0
            )
            to_create.append(
                Client(
                    nom=user.username,
                    email=client_email,
                    ville=profile.country_code or "",
                    reservations=nb_res,
                    depense=total_fcfa,
                )
            )
            existing_emails.add(client_email)  # éviter les doublons intra-batch
    if to_create:
        Client.objects.bulk_create(to_create, ignore_conflicts=True)


def _sync_missing_providers():
    """Crée une ligne Provider minimale pour chaque UserProfile prestataire qui
    n'en a pas encore (inscrit mais KYC non commencé).

    Statut « En attente » → le prestataire reste invisible aux clients (seuls les
    « Valide » s'affichent), mais il apparaît dans l'admin et est compté
    correctement. Le KYC mettra ensuite à jour cette même ligne (pas de doublon).
    """
    existing_user_ids = set(
        Provider.objects.exclude(user_id=None).values_list("user_id", flat=True)
    )
    profiles = UserProfile.objects.filter(
        role=UserProfile.Role.PRESTATAIRE
    ).select_related("user")
    to_create = []
    for profile in profiles:
        if not profile.user_id or profile.user_id in existing_user_ids:
            continue
        user = profile.user
        to_create.append(
            Provider(
                user=user,
                nom=user.username,
                specialite="",
                ville=profile.country_code or "",
                statut=Provider.Status.PENDING,
            )
        )
        existing_user_ids.add(profile.user_id)
    if to_create:
        Provider.objects.bulk_create(to_create, ignore_conflicts=True)


def _filter_lists_for_section(section, search_q):
    """
    Filtre les listes selon la section courante et le paramètre GET q=.
    """
    q = (search_q or "").strip()
    # Synchroniser depuis UserProfile (rattrapage des inscriptions passées) :
    # tout prestataire/client créé par les apps apparaît dans l'admin.
    _sync_missing_providers()
    _sync_missing_clients()
    from django.db.models import Case, When, Value, IntegerField
    providers = (
        Provider.objects.filter(is_deleted=False)
        .select_related("user", "category")
        # Nouveaux / en attente de validation EN HAUT, puis les plus récents.
        .order_by(
            Case(
                When(statut="En attente", then=Value(0)),
                default=Value(1),
                output_field=IntegerField(),
            ),
            "-id",
        )
    )
    reservations = Reservation.objects.all()
    litiges = Dispute.objects.all()
    clients = Client.objects.all()
    # select_related('reservation') : on affiche l'opérateur Mobile Money
    # (Orange/MTN/Wave/Moov) + son logo dans le tableau des paiements.
    paiements = Payment.objects.select_related("reservation").all()
    categories = Category.objects.all()
    notifications = Notification.objects.all()[:20]

    if not q:
        return (
            providers,
            reservations,
            litiges,
            clients,
            paiements,
            categories,
            notifications,
        )

    if section == "dashboard":
        providers = providers.filter(
            Q(nom__icontains=q)
            | Q(specialite__icontains=q)
            | Q(ville__icontains=q)
            | Q(bio__icontains=q)
        )
        paiements = paiements.filter(
            Q(reference__icontains=q)
            | Q(client__icontains=q)
            | Q(prestataire__icontains=q)
            | Q(montant__icontains=q)
        )
    elif section == "prestataires":
        providers = providers.filter(
            Q(nom__icontains=q)
            | Q(specialite__icontains=q)
            | Q(ville__icontains=q)
            | Q(bio__icontains=q)
        )
    elif section == "reservations":
        reservations = reservations.filter(
            Q(reference__icontains=q)
            | Q(client__icontains=q)
            | Q(prestataire__icontains=q)
            | Q(title__icontains=q)
            | Q(montant__icontains=q)
            | Q(statut__icontains=q)
        )
    elif section == "litiges":
        litiges = litiges.filter(
            Q(reference__icontains=q)
            | Q(motif__icontains=q)
            | Q(client__icontains=q)
            | Q(prestataire__icontains=q)
            | Q(decision__icontains=q)
            | Q(priorite__icontains=q)
        )
    elif section == "clients":
        clients = clients.filter(
            Q(nom__icontains=q) | Q(email__icontains=q) | Q(ville__icontains=q)
        )
    elif section == "paiements":
        paiements = paiements.filter(
            Q(reference__icontains=q)
            | Q(client__icontains=q)
            | Q(prestataire__icontains=q)
            | Q(montant__icontains=q)
            | Q(commission__icontains=q)
            | Q(etat__icontains=q)
        )
    elif section == "categories":
        categories = categories.filter(
            Q(nom__icontains=q) | Q(description__icontains=q)
        )
    elif section == "notifications":
        notifications = Notification.objects.filter(
            Q(title__icontains=q) | Q(time__icontains=q)
        )[:20]

    return (
        providers,
        reservations,
        litiges,
        clients,
        paiements,
        categories,
        notifications,
    )


@login_required(login_url="/admin/login/")
@require_GET
def export_dashboard_csv(request, kind):
    """Export CSV (UTF-8 avec BOM pour Excel) — listes filtrées possibles via q=."""
    allowed = {
        "reservations",
        "payments",
        "providers",
        "clients",
        "litiges",
        "categories",
    }
    if kind not in allowed:
        return HttpResponse("Type d’export inconnu", status=404)

    _bootstrap_data()
    search_q = request.GET.get("q", "").strip()
    kind_section = {
        "reservations": "reservations",
        "payments": "paiements",
        "providers": "prestataires",
        "clients": "clients",
        "litiges": "litiges",
        "categories": "categories",
    }
    providers, reservations, litiges, clients, paiements, categories, _notifications = (
        _filter_lists_for_section(
            kind_section[kind],
            search_q,
        )
    )

    response = HttpResponse(content_type="text/csv; charset=utf-8")
    response["Content-Disposition"] = f'attachment; filename="babifix_{kind}.csv"'
    response.write("\ufeff")
    writer = csv.writer(response, delimiter=";")

    if kind == "reservations":
        writer.writerow(
            [
                "reference",
                "client",
                "prestataire",
                "montant",
                "statut",
                "paiement",
                "operateur_mm",
                "flux_especes",
            ]
        )
        for r in reservations.order_by("-id"):
            op = (
                r.get_mobile_money_operator_display()
                if r.payment_type == Reservation.PaymentType.MOBILE_MONEY
                else ""
            )
            writer.writerow(
                [
                    r.reference,
                    r.client,
                    r.prestataire,
                    r.montant,
                    r.statut,
                    r.get_payment_type_display(),
                    op,
                    r.get_cash_flow_status_display()
                    if r.payment_type == Reservation.PaymentType.ESPECES
                    else "",
                ]
            )
    elif kind == "payments":
        writer.writerow(
            [
                "reference",
                "client",
                "prestataire",
                "montant",
                "commission",
                "etat",
                "type_paiement",
            ]
        )
        for p in paiements.order_by("-id"):
            writer.writerow(
                [
                    p.reference,
                    p.client,
                    p.prestataire,
                    p.montant,
                    p.commission,
                    p.etat,
                    p.get_type_paiement_display(),
                ]
            )
    elif kind == "providers":
        writer.writerow(
            ["nom", "specialite", "ville", "statut", "tarif_horaire", "disponible"]
        )
        for p in providers.order_by("nom"):
            writer.writerow(
                [
                    p.nom,
                    p.specialite,
                    p.ville,
                    p.statut,
                    str(p.tarif_horaire) if p.tarif_horaire is not None else "",
                    "oui" if p.disponible else "non",
                ]
            )
    elif kind == "clients":
        writer.writerow(["nom", "email", "ville", "reservations", "depense"])
        for c in clients.order_by("nom"):
            writer.writerow([c.nom, c.email, c.ville, c.reservations, c.depense])
    elif kind == "litiges":
        writer.writerow(
            ["reference", "motif", "client", "prestataire", "priorite", "decision"]
        )
        for l in litiges.order_by("-id"):
            writer.writerow(
                [l.reference, l.motif, l.client, l.prestataire, l.priorite, l.decision]
            )
    elif kind == "categories":
        writer.writerow(["nom", "description", "services", "reservations", "actif"])
        for c in categories.order_by("ordre_affichage", "nom"):
            writer.writerow(
                [
                    c.nom,
                    c.description,
                    c.services,
                    c.reservations,
                    "oui" if c.actif else "non",
                ]
            )

    return response


@login_required(login_url="/admin/login/")
def dashboard(request):
    if not (request.user.is_staff or request.user.is_superuser):
        from django.http import HttpResponseForbidden
        return HttpResponseForbidden("Accès réservé aux administrateurs BABIFIX.")
    section = request.GET.get("section", "dashboard")
    allowed_sections = {
        "dashboard",
        "prestataires",
        "reservations",
        "kanban",
        "litiges",
        "clients",
        "paiements",
        "categories",
        "catalogue",
        "finances",
        "payouts",
        "notifications",
        "actualites",
        "parametres",
        "audit",
    }
    if section not in allowed_sections:
        section = "dashboard"

    _bootstrap_data()
    settings_obj = SystemSetting.objects.get(pk=1)

    if request.method == "POST":
        action = request.POST.get("action")
        if action == "provider_status":
            try:
                provider_id = int(request.POST.get("provider_id") or "0")
            except ValueError:
                provider_id = 0
            next_status = request.POST.get("next_status", "")
            provider = Provider.objects.filter(id=provider_id).first()
            if provider:
                provider.statut = next_status
                update_fields = ["statut"]
                if next_status == Provider.Status.VALID:
                    provider.refusal_reason = ""
                    provider.is_approved = True
                    update_fields += ["refusal_reason", "is_approved"]
                elif next_status == Provider.Status.REFUSED:
                    provider.is_approved = False
                    update_fields.append("is_approved")
                provider.save(update_fields=update_fields)
                Notification.objects.create(
                    title=f"Statut prestataire mis a jour: {provider.nom} ({next_status})"
                )
        elif action == "provider_refuse":
            try:
                provider_id = int(request.POST.get("provider_id") or "0")
            except ValueError:
                provider_id = 0
            reason = (request.POST.get("reason") or "").strip()[:2000]
            provider = Provider.objects.filter(id=provider_id).first()
            if provider:
                provider.statut = Provider.Status.REFUSED
                provider.refusal_reason = reason
                provider.save(update_fields=["statut", "refusal_reason"])
                Notification.objects.create(title=f"Prestataire refuse: {provider.nom}")
        elif action == "provider_save":
            pk = (request.POST.get("pk") or "").strip()
            inst = Provider.objects.filter(pk=int(pk)).first() if pk.isdigit() else None
            form = ProviderForm(request.POST, instance=inst)
            if form.is_valid():
                form.save()
                messages.success(request, "Prestataire enregistré.")
            else:
                messages.error(request, form.errors.as_text())
        elif action == "provider_delete":
            pk = request.POST.get("pk")
            if pk and str(pk).isdigit():
                Provider.objects.filter(pk=int(pk)).delete()
                messages.success(request, "Prestataire supprimé.")
        elif action == "client_save":
            pk = (request.POST.get("pk") or "").strip()
            inst = Client.objects.filter(pk=int(pk)).first() if pk.isdigit() else None
            form = ClientForm(request.POST, instance=inst)
            if form.is_valid():
                form.save()
                messages.success(request, "Client enregistré.")
            else:
                messages.error(request, form.errors.as_text())
        elif action == "client_delete":
            pk = request.POST.get("pk")
            if pk and str(pk).isdigit():
                Client.objects.filter(pk=int(pk)).delete()
                messages.success(request, "Client supprimé.")
        elif action == "reservation_save":
            pk = (request.POST.get("pk") or "").strip()
            inst = (
                Reservation.objects.filter(pk=int(pk)).first() if pk.isdigit() else None
            )
            form = ReservationForm(request.POST, instance=inst)
            if form.is_valid():
                form.save()
                messages.success(request, "Réservation enregistrée.")
            else:
                messages.error(request, form.errors.as_text())
        elif action == "reservation_delete":
            pk = request.POST.get("pk")
            if pk and str(pk).isdigit():
                Reservation.objects.filter(pk=int(pk)).delete()
                messages.success(request, "Réservation supprimée.")
        elif action == "litige_save":
            pk = (request.POST.get("pk") or "").strip()
            inst = Dispute.objects.filter(pk=int(pk)).first() if pk.isdigit() else None
            form = DisputeForm(request.POST, instance=inst)
            if form.is_valid():
                form.save()
                messages.success(request, "Litige enregistré.")
            else:
                messages.error(request, form.errors.as_text())
        elif action == "litige_delete":
            pk = request.POST.get("pk")
            if pk and str(pk).isdigit():
                Dispute.objects.filter(pk=int(pk)).delete()
                messages.success(request, "Litige supprimé.")
        elif action == "litige_decision":
            litige_id = request.POST.get("litige_id", "")
            decision = request.POST.get("decision", "")
            dispute = Dispute.objects.filter(reference=litige_id).first()
            if dispute:
                # L'UI envoie les codes anglais (REFUND/RELEASE/SPLIT/OPEN). On
                # normalise vers le libellé canonique français de l'enum pour que
                # le badge s'affiche bien et que la donnée reste cohérente.
                _norm = (decision or "").strip().upper()
                _canon = {
                    "REFUND": Dispute.Decision.REFUND,
                    "REMBOURSER CLIENT": Dispute.Decision.REFUND,
                    "RELEASE": Dispute.Decision.RELEASE,
                    "LIBERER PAIEMENT": Dispute.Decision.RELEASE,
                    "LIBÉRER PAIEMENT": Dispute.Decision.RELEASE,
                    "SPLIT": Dispute.Decision.SPLIT,
                    "PARTAGE PARTIEL": Dispute.Decision.SPLIT,
                    "PARTAGE": Dispute.Decision.SPLIT,
                    "OPEN": Dispute.Decision.OPEN,
                    "EN COURS": Dispute.Decision.OPEN,
                }.get(_norm, decision)
                dispute.decision = _canon
                dispute.decided_at = timezone.now()
                if getattr(request, "user", None) and request.user.is_authenticated:
                    dispute.decided_by = request.user
                dispute.save(update_fields=["decision", "decided_at", "decided_by"])
                # Applique RÉELLEMENT l'issue financière (libération / remboursement
                # / partage). Sans cet appel, la décision n'était qu'une étiquette :
                # aucun fond ne bougeait, aucune dette de remboursement n'était créée.
                actionable = _canon in (
                    Dispute.Decision.REFUND,
                    Dispute.Decision.RELEASE,
                    Dispute.Decision.SPLIT,
                )
                if dispute.reservation_id and actionable:
                    try:
                        from .services.escrow_service import EscrowService

                        res = EscrowService.resolve_dispute(
                            dispute.reservation, decision
                        )
                        if res.get("error"):
                            messages.error(
                                request,
                                f"Litige {litige_id} : décision enregistrée mais "
                                f"non appliquée ({res['error']}).",
                            )
                        else:
                            act = res.get("action", "")
                            if act == "release":
                                messages.success(
                                    request,
                                    f"Litige {litige_id} : fonds libérés au prestataire.",
                                )
                            elif act == "refund":
                                messages.success(
                                    request,
                                    f"Litige {litige_id} : remboursement de "
                                    f"{int(res.get('refund_owed', 0))} F CFA dû au client "
                                    f"(à verser depuis Finances).",
                                )
                            elif act == "split":
                                messages.success(
                                    request,
                                    f"Litige {litige_id} : partage appliqué — "
                                    f"{int(res.get('to_provider', 0))} F CFA au prestataire, "
                                    f"{int(res.get('refund_owed', 0))} F CFA dû au client.",
                                )
                    except Exception as _disp_err:  # noqa: BLE001
                        messages.error(
                            request,
                            f"Litige {litige_id} : erreur lors de l'application "
                            f"de la décision ({_disp_err}).",
                        )
                elif actionable and not dispute.reservation_id:
                    messages.warning(
                        request,
                        f"Litige {litige_id} : aucune réservation liée — "
                        f"décision enregistrée mais à traiter manuellement.",
                    )
            Notification.objects.create(
                title=f"Decision litige {litige_id}: {decision}"
            )
        elif action == "paiement_save":
            pk = (request.POST.get("pk") or "").strip()
            inst = Payment.objects.filter(pk=int(pk)).first() if pk.isdigit() else None
            form = PaymentForm(request.POST, instance=inst)
            if form.is_valid():
                form.save()
                messages.success(request, "Paiement enregistré.")
            else:
                messages.error(request, form.errors.as_text())
        elif action == "paiement_delete":
            pk = request.POST.get("pk")
            if pk and str(pk).isdigit():
                Payment.objects.filter(pk=int(pk)).delete()
                messages.success(request, "Paiement supprimé.")
        elif action == "payment_validate":
            # Valider un paiement en attente (bouton « Valider » du tableau/kanban
            # — jusque-là sans effet faute de handler).
            pid = request.POST.get("payment_id") or request.POST.get("pk")
            if pid and str(pid).isdigit():
                pay = Payment.objects.filter(pk=int(pid)).first()
                if pay:
                    pay.etat = Payment.State.COMPLETE
                    pay.valide_par_admin = True
                    pay.save(update_fields=["etat", "valide_par_admin"])
                    messages.success(request, f"Paiement {pay.reference} validé.")
        elif action == "category_save":
            pk = (request.POST.get("pk") or "").strip()
            inst = Category.objects.filter(pk=int(pk)).first() if pk.isdigit() else None
            form = CategoryForm(request.POST, instance=inst)
            if form.is_valid():
                form.save()
                messages.success(request, "Catégorie enregistrée.")
            else:
                messages.error(request, form.errors.as_text())
        elif action == "category_delete":
            pk = request.POST.get("pk")
            if pk and str(pk).isdigit():
                Category.objects.filter(pk=int(pk)).delete()
                messages.success(request, "Catégorie supprimée.")
        elif action == "notification_save":
            pk = (request.POST.get("pk") or "").strip()
            inst = (
                Notification.objects.filter(pk=int(pk)).first()
                if pk.isdigit()
                else None
            )
            form = NotificationForm(request.POST, instance=inst)
            if form.is_valid():
                form.save()
                messages.success(request, "Notification enregistrée.")
            else:
                messages.error(request, form.errors.as_text())
        elif action == "notification_delete":
            pk = request.POST.get("pk")
            if pk and str(pk).isdigit():
                Notification.objects.filter(pk=int(pk)).delete()
                messages.success(request, "Notification supprimée.")
        elif action == "notification_create":
            title = request.POST.get("title", "").strip()
            if title:
                Notification.objects.create(title=title)
        elif action == "actualite_save":
            pk = (request.POST.get("pk") or "").strip()
            inst = (
                Actualite.objects.filter(pk=int(pk)).first() if pk.isdigit() else None
            )
            form = ActualiteForm(request.POST, request.FILES, instance=inst)
            if form.is_valid():
                obj = form.save(commit=False)
                obj.created_by = request.user
                try:
                    obj.save()
                except Exception as exc:  # noqa: BLE001
                    # Échec de l'upload média (ex. Cloudinary mal configuré /
                    # signature invalide) : on enregistre quand même l'actualité
                    # SANS l'image plutôt que de planter (500).
                    logger.warning("Actualité : échec save avec image (%s) — sauvegarde sans image", exc)
                    if obj.image:
                        obj.image = None
                    obj.save()
                    messages.warning(
                        request,
                        "Actualité enregistrée, mais l'image n'a pas pu être "
                        "envoyée (vérifiez la clé Cloudinary CLOUDINARY_URL). "
                        "Réessayez l'image une fois la clé corrigée.",
                    )
                messages.success(request, "Actualité enregistrée.")
                # Retour visuel immédiat : portée réelle de la notification push.
                if obj.publie:
                    _notify_actualite_reach(request)
                else:
                    messages.info(
                        request,
                        "Actualité enregistrée en brouillon (non publiée) : "
                        "aucune notification n'est envoyée tant que « Publié » "
                        "n'est pas coché.",
                    )
            else:
                messages.error(request, form.errors.as_text())
        elif action == "actualite_toggle_publish":
            pk = (request.POST.get("pk") or "").strip()
            inst = (
                Actualite.objects.filter(pk=int(pk)).first() if pk.isdigit() else None
            )
            if inst is None:
                messages.error(request, "Actualité introuvable.")
            else:
                inst.publie = not inst.publie
                inst.save(update_fields=["publie"])
                if inst.publie:
                    messages.success(request, "Actualité publiée.")
                    _notify_actualite_reach(request)
                else:
                    messages.info(request, "Actualité repassée en brouillon.")
            section = "actualites"
        elif action == "actualite_delete":
            pk = request.POST.get("pk")
            if pk and str(pk).isdigit():
                Actualite.objects.filter(pk=int(pk)).delete()
                messages.success(request, "Actualité supprimée.")
        elif action == "category_toggle":
            cat_name = request.POST.get("category_name", "")
            category = Category.objects.filter(nom=cat_name).first()
            if category:
                category.actif = not category.actif
                category.save(update_fields=["actif"])
        elif action == "category_import_catalog":
            if not request.user.is_staff:
                messages.error(
                    request, "Import réservé aux comptes administrateur (staff)."
                )
            else:
                try:
                    result = import_categories_from_catalog(dry_run=False)
                    messages.success(
                        request,
                        f"Catalogue BABIFIX : {result['created']} catégorie(s) créée(s), "
                        f"{result['updated']} mise(s) à jour (ordre + descriptions + icônes).",
                    )
                    for w in result.get("warnings") or []:
                        messages.warning(request, w)
                except OSError as exc:
                    messages.error(
                        request, f"Lecture du fichier catalogue impossible : {exc}"
                    )
                except (ValueError, KeyError) as exc:
                    messages.error(request, f"Import catalogue : {exc}")
            section = "categories"
        elif action == "category_clear_icons_active":
            if not request.user.is_staff:
                messages.error(
                    request, "Action réservée aux comptes administrateur (staff)."
                )
            else:
                n = Category.objects.filter(actif=True).update(
                    icone_slug="", icone_url=""
                )
                messages.success(
                    request,
                    f"Icônes effacées (slug + URL) pour {n} catégorie(s) marquée(s) active(s).",
                )
            section = "categories"
        elif action == "category_delete_all":
            if not request.user.is_staff:
                messages.error(
                    request, "Action réservée aux comptes administrateur (staff)."
                )
            else:
                with transaction.atomic():
                    n = Category.objects.count()
                    Category.objects.all().delete()
                messages.success(
                    request,
                    f"{n} catégorie(s) supprimée(s). Les prestataires liés n’ont plus de catégorie "
                    "(réassignation ou réimport du catalogue JSON possible).",
                )
            section = "categories"
        elif action == "params_update":
            commission = request.POST.get("commission", "").strip()
            if commission.isdigit():
                settings_obj.commission = int(commission)
            settings_obj.auto_validation = request.POST.get("auto_validation") == "on"
            settings_obj.maintenance = request.POST.get("maintenance") == "on"
            settings_obj.mode_paiement = (
                request.POST.get("mode_paiement") or ""
            ).strip()[:120]
            settings_obj.save()
        elif action == "withdrawal_relance":
            # Admin marque un retrait comme versé (après virement Mobile Money).
            try:
                tx_id = int(request.POST.get("tx_id") or "0")
            except ValueError:
                tx_id = 0
            tx = WalletTransaction.objects.filter(
                pk=tx_id, tx_type="debit", status="pending"
            ).select_related("provider").first()
            if tx:
                tx.status = "success"
                tx.save(update_fields=["status"])
                try:
                    from .push_dispatch import _schedule
                    if tx.provider and tx.provider.user_id:
                        _schedule(
                            [tx.provider.user_id],
                            "BABIFIX — Retrait effectué",
                            f"Votre retrait de {tx.amount_fcfa:,.0f} FCFA via "
                            f"{(tx.operator or '').upper()} a été traité.",
                            {"type": "wallet.withdrawal_done", "tx_id": str(tx.pk)},
                        )
                except Exception:
                    pass
                messages.success(request, f"Retrait de {tx.amount_fcfa:,.0f} FCFA marqué comme versé.")
            else:
                messages.error(request, "Retrait introuvable ou déjà traité.")
            section = "payouts"
        elif action == "withdrawal_reject":
            # Admin rejette un retrait → on recrédite le solde du prestataire.
            try:
                tx_id = int(request.POST.get("tx_id") or "0")
            except ValueError:
                tx_id = 0
            with transaction.atomic():
                tx = WalletTransaction.objects.select_for_update().filter(
                    pk=tx_id, tx_type="debit", status="pending"
                ).select_related("provider").first()
                if tx:
                    prov = Provider.objects.select_for_update().get(pk=tx.provider_id)
                    from decimal import Decimal as _D
                    prov.solde_fcfa = (prov.solde_fcfa or _D("0")) + tx.amount_fcfa
                    prov.save(update_fields=["solde_fcfa"])
                    tx.status = "failed"
                    tx.save(update_fields=["status"])
                    try:
                        from .push_dispatch import _schedule
                        if prov.user_id:
                            _schedule(
                                [prov.user_id],
                                "BABIFIX — Retrait refusé",
                                f"Votre demande de retrait de {tx.amount_fcfa:,.0f} FCFA "
                                "a été refusée. Le montant a été recrédité sur votre solde.",
                                {"type": "wallet.withdrawal_rejected", "tx_id": str(tx.pk)},
                            )
                    except Exception:
                        pass
            messages.success(request, "Retrait rejeté et solde recrédité.")
            section = "payouts"
        elif action == "refund_process":
            # Admin déclenche le virement de remboursement au client (payout MM).
            ref = (request.POST.get("reference") or "").strip()
            res = Reservation.objects.filter(reference=ref).first()
            if not res:
                messages.error(request, "Réservation introuvable.")
            else:
                try:
                    from .services.escrow_service import EscrowService

                    out = EscrowService.process_client_refund(res)
                    if out.get("error"):
                        messages.warning(
                            request,
                            f"Remboursement {ref} : {out['error']}. "
                            f"{'À traiter manuellement.' if out.get('manual') else ''}",
                        )
                    elif out.get("skip"):
                        messages.info(request, f"Remboursement {ref} : {out['skip']}.")
                    else:
                        messages.success(
                            request,
                            f"Remboursement {ref} : virement déclenché vers le client.",
                        )
                except Exception as _ref_err:  # noqa: BLE001
                    messages.error(
                        request, f"Remboursement {ref} : erreur ({_ref_err})."
                    )
            section = "finances"
        elif action == "refund_mark_paid":
            # Admin confirme un remboursement réglé hors ligne (cash / virement manuel).
            ref = (request.POST.get("reference") or "").strip()
            res = Reservation.objects.filter(reference=ref).first()
            if res:
                res.refund_status = "paid"
                res.refund_paid_at = timezone.now()
                res.save(update_fields=["refund_status", "refund_paid_at"])
                messages.success(
                    request, f"Remboursement {ref} marqué comme payé."
                )
            else:
                messages.error(request, "Réservation introuvable.")
            section = "finances"
        return redirect(f"/?section={section}")

    search_q = request.GET.get("q", "").strip()
    stats, kpi, kpi_chart = _dashboard_kpi_payload()
    providers, reservations, litiges, clients, paiements, categories, notifications = (
        _filter_lists_for_section(
            section,
            search_q,
        )
    )
    actualites = Actualite.objects.all().order_by("-date_publication")
    if section == "actualites" and search_q:
        actualites = actualites.filter(
            Q(titre__icontains=search_q) | Q(description__icontains=search_q)
        )

    # ── Paiements : filtres avancés + mini-stats (section « pro ») ──────────
    # Filtres : état, opérateur Mobile Money, plage de dates (date_start/end,
    # jusque-là inertes), montant min/max. Stats calculées sur la sélection.
    paiement_stats = None
    paiement_filters = {}
    if section == "paiements":
        from django.utils.dateparse import parse_date
        from decimal import InvalidOperation

        f_etat = (request.GET.get("etat") or "").strip()
        f_op = (request.GET.get("operator") or "").strip()
        f_ds = (request.GET.get("date_start") or "").strip()
        f_de = (request.GET.get("date_end") or "").strip()
        f_min = (request.GET.get("amount_min") or "").strip()
        f_max = (request.GET.get("amount_max") or "").strip()
        paiement_filters = {
            "etat": f_etat, "operator": f_op, "date_start": f_ds,
            "date_end": f_de, "amount_min": f_min, "amount_max": f_max,
        }
        if f_etat:
            paiements = paiements.filter(etat=f_etat)
        if f_op:
            paiements = paiements.filter(reservation__mobile_money_operator=f_op)
        if f_ds and parse_date(f_ds):
            paiements = paiements.filter(created_at__date__gte=parse_date(f_ds))
        if f_de and parse_date(f_de):
            paiements = paiements.filter(created_at__date__lte=parse_date(f_de))
        if f_min:
            try:
                paiements = paiements.filter(montant__gte=Decimal(f_min))
            except (InvalidOperation, ValueError):
                pass
        if f_max:
            try:
                paiements = paiements.filter(montant__lte=Decimal(f_max))
            except (InvalidOperation, ValueError):
                pass
        # La commission n'est pas stockée sur Payment mais sur la Réservation :
        # on somme la commission des réservations DISTINCTES des paiements filtrés
        # (Payment.commission vaut 0 → une somme dessus donnerait un faux 0).
        _resa_ids = paiements.exclude(reservation__isnull=True).values_list(
            "reservation_id", flat=True).distinct()
        paiement_stats = {
            "encaisse": paiements.filter(etat="Complete").aggregate(
                s=Sum("montant"))["s"] or 0,
            "commission": Reservation.objects.filter(id__in=_resa_ids).aggregate(
                s=Sum("commission"))["s"] or 0,
            "count": paiements.count(),
            "pending": paiements.filter(etat="Pending").count(),
            "litige": paiements.filter(etat="Litige").count(),
        }

    # ── Réservations : filtres avancés + mini-stats ────────────────────────
    reservation_stats = None
    reservation_filters = {}
    if section == "reservations":
        from django.utils.dateparse import parse_date as _pd

        r_statut = (request.GET.get("statut") or "").strip()
        r_pay = (request.GET.get("payment") or "").strip()
        r_op = (request.GET.get("operator") or "").strip()
        r_ds = (request.GET.get("date_start") or "").strip()
        r_de = (request.GET.get("date_end") or "").strip()
        r_urgent = (request.GET.get("urgent") or "").strip()
        reservation_filters = {
            "statut": r_statut, "payment": r_pay, "operator": r_op,
            "date_start": r_ds, "date_end": r_de, "urgent": r_urgent,
        }
        if r_statut:
            reservations = reservations.filter(statut=r_statut)
        if r_pay:
            reservations = reservations.filter(payment_type=r_pay)
        if r_op:
            reservations = reservations.filter(mobile_money_operator=r_op)
        if r_ds and _pd(r_ds):
            reservations = reservations.filter(created_at__date__gte=_pd(r_ds))
        if r_de and _pd(r_de):
            reservations = reservations.filter(created_at__date__lte=_pd(r_de))
        if r_urgent == "1":
            reservations = reservations.filter(is_urgent=True)
        reservation_stats = {
            "count": reservations.count(),
            "active": reservations.exclude(
                statut__in=["Terminee", "Annulee"]).count(),
            "done": reservations.filter(statut="Terminee").count(),
            "urgent": reservations.filter(is_urgent=True).count(),
            "montant": reservations.aggregate(s=Sum("montant"))["s"] or 0,
        }

    # ── Prestataires : filtres avancés + mini-stats ────────────────────────
    provider_stats = None
    provider_filters = {}
    if section == "prestataires":
        p_statut = (request.GET.get("statut") or "").strip()
        p_tier = (request.GET.get("tier") or "").strip()
        p_kyc = (request.GET.get("kyc") or "").strip()
        p_ville = (request.GET.get("ville") or "").strip()
        provider_filters = {
            "statut": p_statut, "tier": p_tier, "kyc": p_kyc, "ville": p_ville,
        }
        if p_statut:
            providers = providers.filter(statut=p_statut)
        if p_tier == "premium":
            providers = providers.filter(is_premium=True)
        elif p_tier in ("gold", "silver", "bronze"):
            providers = providers.filter(premium_tier=p_tier, is_premium=True)
        if p_kyc:
            providers = providers.filter(kyc_status=p_kyc)
        if p_ville:
            providers = providers.filter(ville__icontains=p_ville)
        provider_stats = {
            "count": providers.count(),
            "pending": providers.filter(statut="En attente").count(),
            "valides": providers.filter(statut="Valide").count(),
            "premium": providers.filter(is_premium=True).count(),
        }

    # ── Litiges : filtres + mini-stats ─────────────────────────────────────
    litige_stats = None
    litige_filters = {}
    if section == "litiges":
        from django.utils.dateparse import parse_date as _pd

        l_prio = (request.GET.get("priorite") or "").strip()
        l_dec = (request.GET.get("decision") or "").strip()
        l_ds = (request.GET.get("date_start") or "").strip()
        l_de = (request.GET.get("date_end") or "").strip()
        litige_filters = {
            "priorite": l_prio, "decision": l_dec,
            "date_start": l_ds, "date_end": l_de,
        }
        if l_prio:
            litiges = litiges.filter(priorite=l_prio)
        # « Ouvert » = décision encore « En cours » (valeur par défaut du modèle).
        if l_dec == "__open__":
            litiges = litiges.filter(decision="En cours")
        elif l_dec:
            litiges = litiges.filter(decision=l_dec)
        if l_ds and _pd(l_ds):
            litiges = litiges.filter(created_at__date__gte=_pd(l_ds))
        if l_de and _pd(l_de):
            litiges = litiges.filter(created_at__date__lte=_pd(l_de))
        litige_stats = {
            "count": litiges.count(),
            "open": litiges.filter(decision="En cours").count(),
            "resolved": litiges.exclude(decision="En cours").count(),
            "urgent": litiges.filter(priorite="Haute").count(),
        }

    # ── Clients : filtres + mini-stats (Client n'a pas de date : on s'appuie
    #    sur ville, nb de réservations et dépense cumulée). ─────────────────
    client_stats = None
    client_filters = {}
    if section == "clients":
        c_ville = (request.GET.get("ville") or "").strip()
        client_filters = {"ville": c_ville}
        if c_ville:
            clients = clients.filter(ville__icontains=c_ville)
        client_stats = {
            "count": clients.count(),
            "villes": clients.exclude(ville="").values("ville").distinct().count(),
            "reservations": clients.aggregate(s=Sum("reservations"))["s"] or 0,
            "depense": clients.aggregate(s=Sum("depense"))["s"] or 0,
        }

    # ── Catégories : filtre (actif) + mini-stats ──────────────────────────
    category_stats = None
    category_filters = {}
    if section == "categories":
        cat_actif = (request.GET.get("actif") or "").strip()
        category_filters = {"actif": cat_actif}
        if cat_actif == "1":
            categories = categories.filter(actif=True)
        elif cat_actif == "0":
            categories = categories.filter(actif=False)
        category_stats = {
            "count": categories.count(),
            "actives": categories.filter(actif=True).count(),
            "services": categories.aggregate(s=Sum("services"))["s"] or 0,
            "reservations": categories.aggregate(s=Sum("reservations"))["s"] or 0,
        }

    # ── Actualités : filtres (publié, cible, date) + mini-stats ────────────
    actualite_stats = None
    actualite_filters = {}
    if section == "actualites":
        from django.utils.dateparse import parse_date as _pd

        a_pub = (request.GET.get("publie") or "").strip()
        a_cible = (request.GET.get("cible") or "").strip()
        a_ds = (request.GET.get("date_start") or "").strip()
        a_de = (request.GET.get("date_end") or "").strip()
        actualite_filters = {
            "publie": a_pub, "cible": a_cible,
            "date_start": a_ds, "date_end": a_de,
        }
        if a_pub == "1":
            actualites = actualites.filter(publie=True)
        elif a_pub == "0":
            actualites = actualites.filter(publie=False)
        if a_cible:
            actualites = actualites.filter(cible=a_cible)
        if a_ds and _pd(a_ds):
            actualites = actualites.filter(date_publication__date__gte=_pd(a_ds))
        if a_de and _pd(a_de):
            actualites = actualites.filter(date_publication__date__lte=_pd(a_de))
        actualite_stats = {
            "count": actualites.count(),
            "publiees": actualites.filter(publie=True).count(),
            "brouillons": actualites.filter(publie=False).count(),
        }

    # ── Notifications : filtres (type, lu) + mini-stats ────────────────────
    notification_stats = None
    notification_filters = {}
    if section == "notifications":
        n_type = (request.GET.get("ntype") or "").strip()
        n_lu = (request.GET.get("lu") or "").strip()
        notification_filters = {"ntype": n_type, "lu": n_lu}
        _n_qs = Notification.objects.all()
        if n_type:
            _n_qs = _n_qs.filter(notif_type=n_type)
        if n_lu == "1":
            _n_qs = _n_qs.filter(lu=True)
        elif n_lu == "0":
            _n_qs = _n_qs.filter(lu=False)
        notifications = list(_n_qs.order_by("-created_at")[:50])
        _all_notif = Notification.objects.all()
        notification_stats = {
            "count": _all_notif.count(),
            "non_lues": _all_notif.filter(lu=False).count(),
            "affichees": len(notifications),
        }

    if request.GET.get("partial") == "stats" and section == "dashboard":
        return render(
            request,
            "adminpanel/partials/dashboard_stats.html",
            {"stats": stats, "kpi_chart": kpi_chart},
        )

    _headings = {
        "dashboard": (
            "Tableau de bord",
            "Vue d'ensemble : montants en FCFA (Côte d'Ivoire). Les comptes clients/prestataires viennent des apps ; vous validez et pilotez.",
        ),
        "prestataires": (
            "Prestataires",
            "Vous n'inventez pas les dossiers : les prestataires s'inscrivent sur l'app. Ici : vérifier, approuver, suspendre ou refuser.",
        ),
        "reservations": (
            "Réservations",
            "Suivi des missions, mode de paiement (espèces, Mobile Money Orange/MTN/Wave/Moov, carte) et flux espèces.",
        ),
        "kanban": (
            "Kanban Réservations",
            "Vue drag & drop du pipeline de réservations : glissez pour changer le statut.",
        ),
        "litiges": ("Litiges", "Médiation et décisions enregistrées côté plateforme."),
        "clients": (
            "Clients",
            "Lecture / suivi des fiches issues de l'activité : pas de saisie manuelle des noms comme sur un guichet.",
        ),
        "paiements": (
            "Paiements",
            "Commissions & états (espèces, Orange/MTN/Wave/Moov, carte selon config).",
        ),
        "categories": (
            "Catégories",
            "Services affichés sur la vitrine et dans les apps.",
        ),
        "notifications": ("Notifications", "Alertes internes équipe admin."),
        "actualites": (
            "Actualités",
            "Annonces publiques pour les apps client et prestataire : publication instantanée (WebSocket + push).",
        ),
        "parametres": (
            "Paramètres",
            "Commission, maintenance : impacte le comportement des apps connectées.",
        ),
        "audit": (
            "Journal d'audit",
            "Historique de toutes les actions administrateurs sur la plateforme.",
        ),
    }
    page_heading, page_subtitle = _headings.get(section, _headings["dashboard"])

    audit_logs = []
    if section == "audit":
        audit_logs = list(
            AdminAuditLog.objects.select_related("admin_user")
            .order_by("-created_at")[:100]
            .values(
                "id",
                "action",
                "target_type",
                "target_id",
                "target_label",
                "details",
                "created_at",
                "admin_user__username",
            )
        )

    # Score de fiabilité client (Phase 4) : le modèle Client legacy n'a pas le
    # score (il est sur UserProfile) → on le rattache par e-mail pour l'affichage.
    if section == "clients":
        try:
            emails = [c.email for c in clients if getattr(c, "email", "")]
            score_by_email = {}
            if emails:
                for u in User.objects.filter(email__in=emails).select_related("profile"):
                    prof = getattr(u, "profile", None)
                    if prof is not None and u.email:
                        score_by_email[u.email] = int(prof.fiabilite_score or 100)
            for c in clients:
                c.fiabilite_score = score_by_email.get(getattr(c, "email", ""), 100)
        except Exception:
            for c in clients:
                c.fiabilite_score = 100

    context = {
        "section": section,
        "page_heading": page_heading,
        "page_subtitle": page_subtitle,
        "stats": stats,
        "kpi": kpi,
        "kpi_chart": kpi_chart,
        "search_q": search_q,
        "providers": providers,
        "reservations": reservations,
        "litiges": litiges,
        "clients": clients,
        "paiements": paiements,
        "paiement_stats": paiement_stats,
        "paiement_filters": paiement_filters,
        "reservation_stats": reservation_stats,
        "reservation_filters": reservation_filters,
        "provider_stats": provider_stats,
        "provider_filters": provider_filters,
        "litige_stats": litige_stats,
        "litige_filters": litige_filters,
        "client_stats": client_stats,
        "client_filters": client_filters,
        "category_stats": category_stats,
        "category_filters": category_filters,
        "actualite_stats": actualite_stats,
        "actualite_filters": actualite_filters,
        "notification_stats": notification_stats,
        "notification_filters": notification_filters,
        "categories": categories,
        "notifications": notifications,
        "unified_notifications": notifications,
        "actualites": actualites,
        "params": settings_obj,
        "audit_logs": audit_logs,
    }
    context.update(_dashboard_forms_context(request, section))
    return render(request, "adminpanel/dashboard.html", context)


@require_GET
def api_public_vitrine(request):
    _bootstrap_data()

    def g(key):
        o = SiteContent.objects.filter(key=key).first()
        return (o.value if o else "") or ""

    faq_obj = SiteContent.objects.filter(key="faq").first()
    faq = faq_obj.json_value if faq_obj and faq_obj.json_value else []

    return JsonResponse(
        {
            "hero_title": g("hero_title"),
            "hero_subtitle": g("hero_subtitle"),
            "store_ios_url": g("store_ios_client"),
            "store_android_url": g("store_android_client"),
            "store_prestataire_ios_url": g("store_ios_prestataire"),
            "store_prestataire_android_url": g("store_android_prestataire"),
            "contact_admin_email": g("contact_admin_email"),
            "faq": faq,
            "content": {},
        }
    )


@require_GET
@require_api_auth(["client", "admin"])
def api_client_home(request):
    _bootstrap_data()
    clat = request.GET.get("lat")
    clon = request.GET.get("lon")
    services = _services_from_db(request, client_lat=clat, client_lon=clon)
    uid = request.api_user_id
    user = User.objects.filter(id=uid).first()
    client_name = (user.get_full_name() or user.username) if user else ""
    reservations = []
    # Gating fiabilité (Phase 4) — calculé une fois (même client pour toutes
    # les lignes). False si gating désactivé (défaut).
    try:
        from .services.reliability_service import ReliabilityService
        _prepaiement_requis = ReliabilityService.client_prepaiement_requis(uid)
    except Exception:
        _prepaiement_requis = False

    def _push_reservation_row(item):
        has_rating = Rating.objects.filter(reservation=item).exists()
        can_rate = (
            item.statut == "Terminee" and item.client_user_id == uid and not has_rating
        )
        # « Quand » = créneau/disponibilité choisi par le client. Repli propre
        # selon l'état (terminée → date de fin, sinon « Dès que possible »).
        _when_label = (item.disponibilites_client or "").strip()
        if not _when_label:
            if item.prestation_terminee_at:
                _when_label = "Terminée le " + item.prestation_terminee_at.strftime(
                    "%d/%m/%Y"
                )
            else:
                _when_label = "Dès que possible"
        reservations.append(
            {
                "id": int(item.id),
                "reference": item.reference,
                "title": item.reference,
                # Vrai intitulé de la prestation + nom du prestataire affecté →
                # affichés sur la carte client (avant on ne voyait que la réf).
                "service_title": (item.title or "").strip(),
                "provider_name": (
                    (item.assigned_provider.nom if item.assigned_provider else None)
                    or item.prestataire
                    or ""
                ),
                "when_label": _when_label,
                # Date prévue choisie par le client (affichée sur la carte).
                "scheduled_date": (
                    item.scheduled_date.isoformat()
                    if item.scheduled_date
                    else None
                ),
                "amount": item.montant,
                "status": item.statut,
                "payment_type": item.payment_type,
                "mobile_money_operator": item.mobile_money_operator or "",
                "cash_flow_status": item.cash_flow_status,
                # Montant réellement en séquestre (payé en ligne, pas encore
                # libéré) → permet d'afficher « Bloqué » exact côté client.
                "montant_verse": float(item.montant_verse or 0),
                "funds_released": bool(item.funds_released_at),
                "can_rate": can_rate,
                "rated": has_rating,
                "client_message": (item.client_message or "")[:500],
                "demande_type": item.demande_type or "",
                "demande_type_label": item.get_demande_type_display() if item.demande_type else "",
                "audio_probleme": item.audio_probleme or "",
                "reponses_exigences": item.reponses_exigences or {},
                "caution_montant": float(item.caution_montant or 0),
                "caution_motif": item.caution_motif or "",
                "caution_payee": bool(item.caution_payee),
                "visite_effectuee": bool(item.visite_effectuee),
                "intervention_started_at": item.intervention_started_at.isoformat()
                if item.intervention_started_at
                else None,
                "prestation_terminee_at": item.prestation_terminee_at.isoformat()
                if item.prestation_terminee_at
                else None,
                "client_confirme_prestation_at": item.client_confirme_prestation_at.isoformat()
                if item.client_confirme_prestation_at
                else None,
                "dispute_ouverte": bool(item.dispute_ouverte),
                # ORDRE MÉTIER : le client CONFIRME les travaux D'ABORD (il vérifie
                # que c'est bien fait), PUIS il paie le solde. « Confirmer » apparaît
                # donc dès que le presta a terminé, tant que le client n'a pas encore
                # confirmé — y compris si un solde Mobile Money reste dû.
                "can_confirm_service": item.statut in ("En attente client", "Terminee")
                and item.client_user_id == uid
                and not item.client_confirme_prestation_at,
                "can_pay": item.statut == "Terminee"
                and bool(item.client_confirme_prestation_at)
                and not Payment.objects.filter(
                    reservation=item, etat=Payment.State.COMPLETE
                ).exists(),
                "can_view_devis": item.statut == "DEVIS_ENVOYE"
                and item.client_user_id == uid,
                "can_accept_devis": item.statut == "DEVIS_ENVOYE"
                and item.client_user_id == uid,
                "can_pay_deposit": item.statut == "DEVIS_ACCEPTE"
                and item.client_user_id == uid
                and not item.acompte_valide,
                # Caution de visite de diagnostic (Phase 3).
                "caution_montant": float(item.caution_montant or 0),
                "caution_motif": item.caution_motif or "",
                "caution_payee": bool(item.caution_payee),
                "visite_effectuee": bool(item.visite_effectuee),
                "can_pay_caution": item.statut == "VISITE_DIAGNOSTIC"
                and item.client_user_id == uid
                and (item.caution_montant or 0) > 0
                and not item.caution_payee,
                # Gating fiabilité (Phase 4) — surface uniquement (non bloquant
                # tant que l'app n'en tient pas compte). False si gating inactif.
                "prepaiement_requis": _prepaiement_requis,
                # MM : le solde 70 % se paie APRÈS la confirmation des travaux
                # (ordre métier : vérifier puis payer). Le paiement du solde
                # déclenche la libération des fonds au prestataire.
                "can_pay_remainder": item.statut in ("En attente client", "Terminee")
                and item.client_user_id == uid
                and bool(item.client_confirme_prestation_at)
                and item.acompte_valide
                and not item.solde_valide
                and (item.montant_restant or 0) > 0
                and item.payment_type == "MOBILE_MONEY",
                "need_cash_remainder": item.statut in ("En attente client", "Terminee")
                and item.client_user_id == uid
                and item.acompte_valide
                and not item.solde_valide
                and item.payment_type == "ESPECES",
                "receipt_available": item.solde_valide,
                "latitude": item.latitude,
                "longitude": item.longitude,
                "address_label": (item.address_label or "")[:500],
                "address_street": (item.address_street or "")[:200],
                "address_quartier": (item.address_quartier or "")[:120],
                "address_ville": (item.address_ville or "")[:120],
                "address_pays": (item.address_pays or "")[:80],
                "address_repere": (item.address_repere or "")[:300],
                "address_is_approximate": item.address_is_approximate,
            }
        )

    # Scope strict au client authentifié (client_user_id) pour éviter toute
    # fuite de réservations d'autres comptes partageant le même libellé "client".
    # On garde le repli sur le nom UNIQUEMENT pour les réservations sans
    # client_user_id (créées côté admin) afin de ne rien casser.
    _res_qs = Reservation.objects.filter(
        Q(client_user_id=uid)
        | (Q(client_user_id__isnull=True) & Q(client=client_name))
    ).distinct().order_by("-id")[:50]
    for item in _res_qs:
        _push_reservation_row(item)
    news = [
        {"title": item.title, "subtitle": item.time}
        for item in Notification.objects.all()[:6]
    ]
    actualites = [
        _actualite_to_json(request, a, summary=True)
        for a in Actualite.objects.filter(
            publie=True, cible__in=["client", "tous"]
        ).order_by("-date_publication")[:12]
    ]
    payment_methods = [
        {"id": mid, "label": label, "logo_url": _static_absolute(request, path)}
        for mid, path, label in PAYMENT_METHOD_STATIC
    ]
    recent_providers = []
    for p in (
        Provider.objects.filter(statut=Provider.Status.VALID, is_deleted=False)
        .select_related("category", "user")
        # Disponibles d'abord, puis les plus récents : les indisponibles
        # se retrouvent tout en bas de la liste « Nouveaux prestataires ».
        .order_by("-disponible", "-user__date_joined")[:12]
    ):
        recent_providers.append(
            {
                "id": int(p.id),
                "nom": p.nom,
                "specialite": p.specialite,
                "ville": p.ville,
                "image_url": _safe_photo_url(p.photo_portrait_url or "", request),
                "category_nom": (p.category.nom if p.category_id else "") or "",
                "category_icone_url": _category_icon_url(
                    request, p.category if p.category_id else None
                )
                if p.category_id
                else "",
                "tarif_horaire": float(p.tarif_horaire)
                if p.tarif_horaire is not None
                else None,
                "disponible": p.disponible,
                "distance_km": _provider_distance_km(clat, clon, p),
            }
        )
    site = SiteContent.objects.filter(key="contact_admin_email").first()
    contact_admin = (site.value or "").strip() if site else ""
    return JsonResponse(
        {
            "services": services,
            "reservations": reservations,
            "news": news,
            "actualites": actualites,
            "payment_methods": payment_methods,
            "recent_providers": recent_providers,
            "contact_admin_email": contact_admin,
        }
    )


@require_GET
@require_api_auth(["client", "prestataire", "admin"])
def api_client_actualites(request):
    _bootstrap_data()
    audience = (request.GET.get("cible") or "").strip().lower()
    qs = Actualite.objects.filter(publie=True)
    if audience == "client":
        qs = qs.filter(cible__in=["client", "tous"])
    elif audience == "prestataire":
        qs = qs.filter(cible__in=["prestataire", "tous"])
    rows = [
        _actualite_to_json(request, a, summary=True)
        for a in qs.order_by("-date_publication")
    ]
    return JsonResponse({"items": rows})


@require_GET
def api_public_actualites(request):
    """
    Variante publique (sans authentification) — retourne uniquement les
    actualités à cible 'tous' qui n'ont pas vocation à être réservées
    aux clients/prestataires inscrits. Permet aux visiteurs anonymes
    de voir les annonces publiques de BABIFIX sur l'écran « À la une ».
    """
    _bootstrap_data()
    qs = Actualite.objects.filter(publie=True, cible__in=["tous", ""])
    rows = [
        _actualite_to_json(request, a, summary=True)
        for a in qs.order_by("-date_publication")[:30]
    ]
    return JsonResponse({"items": rows})


@require_GET
@require_api_auth(["client", "prestataire", "admin"])
def api_client_actualite_detail(request, pk: int):
    _bootstrap_data()
    a = Actualite.objects.filter(pk=pk, publie=True).first()
    if not a:
        return JsonResponse({"error": "not_found"}, status=404)
    return JsonResponse({"item": _actualite_to_json(request, a, summary=False)})


@require_GET
def api_public_actualite_detail(request, pk: int):
    """
    Variante publique (sans authentification) pour lire une actualité.
    Accessible aux visiteurs anonymes.
    """
    _bootstrap_data()
    a = Actualite.objects.filter(
        pk=pk, publie=True, cible__in=["tous", ""]
    ).first()
    if not a:
        return JsonResponse({"error": "not_found"}, status=404)
    return JsonResponse({"item": _actualite_to_json(request, a, summary=False)})


@require_GET
def api_public_provider_availability(request, provider_id):
    """Disponibilités publiques d'un prestataire (pour le calendrier client).

    Retourne les créneaux hebdomadaires, les périodes bloquées, et les
    21 prochains jours avec leur disponibilité (jour avec créneau + non bloqué).
    """
    from datetime import date, timedelta
    from .models import PrestataireAvailabilitySlot, PrestataireUnavailability

    prov = Provider.objects.filter(pk=provider_id).first()
    if not prov:
        return JsonResponse({"error": "not_found"}, status=404)

    slots = list(
        PrestataireAvailabilitySlot.objects.filter(provider=prov, actif=True)
    )
    slots_by_day: dict[int, list] = {}
    for s in slots:
        slots_by_day.setdefault(s.jour_semaine, []).append(
            {
                "start": s.heure_debut.strftime("%H:%M"),
                "end": s.heure_fin.strftime("%H:%M"),
            }
        )
    for v in slots_by_day.values():
        v.sort(key=lambda x: x["start"])

    periods = list(PrestataireUnavailability.objects.filter(provider=prov))

    def _blocked(d):
        return any(p.date_debut <= d <= p.date_fin for p in periods)

    today = date.today()
    days = []
    for i in range(21):
        d = today + timedelta(days=i)
        wd = d.weekday()  # 0 = lundi
        day_slots = slots_by_day.get(wd, [])
        blocked = _blocked(d)
        days.append(
            {
                "date": d.isoformat(),
                "weekday": wd,
                "available": bool(day_slots) and not blocked,
                "blocked": blocked,
                "slots": day_slots,
            }
        )

    return JsonResponse(
        {
            "provider_id": prov.id,
            "provider_nom": prov.nom,
            "has_availability": bool(slots),
            "weekly_slots": {str(k): v for k, v in slots_by_day.items()},
            "days": days,
        }
    )


def _geocode_ci_city(ville: str):
    """Géocode une ville ivoirienne → (lat, lon). Mis en cache 30 j (par ville).
    Renvoie un tuple, ou False si introuvable. Best-effort (jamais d'exception)."""
    from django.core.cache import cache

    key = "geocode_ci:" + ville.strip().lower()
    cached = cache.get(key)
    if cached is not None:
        return cached  # tuple (lat, lon) OU False (déjà tenté, introuvable)
    result = False
    try:
        import requests as _req

        r = _req.get(
            "https://nominatim.openstreetmap.org/search",
            params={
                "q": f"{ville}, Côte d'Ivoire",
                "format": "json",
                "limit": 1,
                "countrycodes": "ci",
            },
            headers={"User-Agent": "BABIFIX/1.0 backend"},
            timeout=4,
        )
        if r.status_code == 200:
            data = r.json()
            if data:
                result = (float(data[0]["lat"]), float(data[0]["lon"]))
    except Exception:
        result = False
    cache.set(key, result, 60 * 60 * 24 * 30)
    return result


def _ensure_provider_coordinates(provider) -> bool:
    """Si le prestataire n'a pas de GPS mais une ville, on géocode la ville et
    on sauvegarde les coords (une seule fois). Retourne True si un appel réseau
    de géocodage a réellement été fait (pour borner le budget par requête)."""
    if provider.latitude is not None and provider.longitude is not None:
        return False
    ville = (provider.ville or "").strip()
    if not ville:
        return False
    from django.core.cache import cache

    did_network = cache.get("geocode_ci:" + ville.lower()) is None
    coords = _geocode_ci_city(ville)
    if coords:
        provider.latitude, provider.longitude = coords[0], coords[1]
        try:
            provider.save(update_fields=["latitude", "longitude"])
        except Exception:
            pass
    return did_network


@require_GET
def api_public_provider_reviews(request, pk):
    """Avis publics d'un prestataire (note + commentaire), du plus récent au plus ancien."""
    qs = (
        Rating.objects.filter(provider_id=pk)
        .select_related("client")
        .order_by("-created_at")[:150]
    )
    # Nombre total d'avis par client (pour indiquer « a noté N prestations »
    # sans répéter le même commentaire en boucle).
    from collections import defaultdict
    client_counts = defaultdict(int)
    for r in qs:
        client_counts[r.client_id] += 1

    # Déduplication : on saute les DOUBLONS EXACTS (même client + même texte) —
    # typiquement quand le presta est revenu plusieurs fois. On garde les
    # commentaires DIFFÉRENTS du même client (prestations différentes).
    seen = set()
    reviews = []
    for r in qs:
        u = r.client
        author = ""
        if u:
            author = (u.first_name or "").strip() or u.username
        text = (r.commentaire or "").strip()
        key = (r.client_id, text.lower())
        if key in seen:
            continue
        seen.add(key)
        reviews.append(
            {
                "author": author or "Client",
                "rate": int(r.note or 0),
                "text": text,
                "date": r.created_at.isoformat() if r.created_at else "",
                # Combien de prestations ce client a notées chez ce presta
                # (> 1 ⇒ l'app peut afficher « client fidèle · N avis »).
                "client_reviews": client_counts.get(r.client_id, 1),
            }
        )
        if len(reviews) >= 50:
            break
    return JsonResponse({"reviews": reviews, "count": len(reviews)})


@require_api_auth(["client", "admin"])
@require_GET
def api_client_check_duplicate(request):
    """Pré-vérifie un doublon de réservation AVANT création :
    - même prestataire, réservation active → blocage strict ;
    - même catégorie chez un autre prestataire → avertissement.
    """
    uid = request.api_user_id
    provider_id = request.GET.get("provider_id")
    _TERMINAL = ("Terminee", "Annulee")
    dup_provider = None
    dup_category = None
    if provider_id and str(provider_id).isdigit():
        prov = Provider.objects.filter(pk=int(provider_id)).select_related("category").first()
        if prov:
            existing = (
                Reservation.objects.filter(client_user_id=uid, assigned_provider=prov)
                .exclude(statut__in=_TERMINAL)
                .first()
            )
            if existing:
                dup_provider = {
                    "reference": existing.reference,
                    "provider": prov.nom,
                    "statut": existing.statut,
                }
            elif prov.category_id:
                other = (
                    Reservation.objects.filter(
                        client_user_id=uid,
                        assigned_provider__category_id=prov.category_id,
                    )
                    .exclude(statut__in=_TERMINAL)
                    .exclude(assigned_provider=prov)
                    .select_related("assigned_provider")
                    .first()
                )
                if other:
                    dup_category = {
                        "reference": other.reference,
                        "category": prov.category.nom if prov.category_id else "",
                        "provider": other.assigned_provider.nom
                        if other.assigned_provider_id
                        else (other.prestataire or ""),
                    }
    return JsonResponse(
        {"duplicate_provider": dup_provider, "duplicate_category": dup_category}
    )


@require_GET
def api_public_providers(request):
    """
    Liste publique des prestataires (sans authentification).
    Recherche + filtres.
    """
    _bootstrap_data()
    qs = Provider.objects.filter(
        statut=Provider.Status.VALID, is_deleted=False
    ).select_related("category")

    # Filtre textuel
    q = (request.GET.get("q") or "").strip()
    if q:
        qs = qs.filter(
            Q(nom__icontains=q) | Q(specialite__icontains=q) | Q(ville__icontains=q)
        )

    # Filtre catégorie
    category_id = request.GET.get("category")
    if category_id and str(category_id).isdigit():
        qs = qs.filter(category_id=int(category_id))

    # Filtre disponibilité - PAR DÉFAUT: tous mais triés dispo'abord
    disponible_param = request.GET.get("disponible", "").lower()
    if disponible_param == "true":
        qs = qs.filter(disponible=True)
    elif disponible_param == "false":
        qs = qs.filter(disponible=False)
    else:
        # Par défaut: tous mais disponibles'abord (grisés en bas)
        qs = qs.order_by("-disponible")

    # Filtre note minimale
    min_rating_param = request.GET.get("min_rating")
    if min_rating_param:
        try:
            min_r = float(min_rating_param)
            qs = qs.filter(average_rating__gte=min_r)
        except ValueError:
            pass

    # Filtre géographique (latitude, longitude, rayon en km).
    # On garde lat_f / lon_f pour calculer ensuite la distance Haversine et
    # potentiellement trier les prestataires par proximité.
    lat = request.GET.get("lat")
    lon = request.GET.get("lon")
    radius = request.GET.get("radius")
    # Mode adaptatif (5 → 15 → 30 → 50 km) si pas de rayon fixe demandé.
    PUB_RADIUS_STEPS = [5, 15, 30, 50]
    pub_is_adaptive = bool(lat and lon and (not radius or str(radius).lower() == "auto"))
    lat_f = lon_f = None

    if lat and lon:
        try:
            lat_f = float(lat)
            lon_f = float(lon)
            from django.db.models import Q
            if pub_is_adaptive:
                # CATALOGUE (rayon « auto ») : BABIFIX est un marché NATIONAL à
                # faible densité. On ne cache JAMAIS un prestataire à cause de la
                # distance — on montre TOUS ceux de Côte d'Ivoire (triés par
                # proximité ensuite). On exclut seulement l'étranger (coords hors
                # CIV, ex. émulateur Shanghai) ; on garde ceux sans coordonnées.
                qs = qs.filter(
                    Q(latitude__isnull=True)
                    | Q(longitude__isnull=True)
                    | Q(
                        latitude__gte=4.0,
                        latitude__lte=11.0,
                        longitude__gte=-9.0,
                        longitude__lte=-2.0,
                    )
                )
            else:
                # Rayon explicite (carte « près de moi ») : on borne réellement.
                radius_km = float(radius)
                lat_delta = radius_km / 111.0
                lon_delta = radius_km / (111.0 * abs(math.cos(math.radians(lat_f))))
                qs = qs.filter(
                    Q(
                        latitude__isnull=False,
                        longitude__isnull=False,
                        latitude__gte=lat_f - lat_delta,
                        latitude__lte=lat_f + lat_delta,
                        longitude__gte=lon_f - lon_delta,
                        longitude__lte=lon_f + lon_delta,
                    )
                    | Q(latitude__isnull=True)
                    | Q(longitude__isnull=True)
                )
        except (ValueError, TypeError):
            lat_f = lon_f = None

    # Tri — on ne fait `order_by` ici QUE pour les modes non-distance, car le
    # tri par distance se fait après calcul Haversine en Python.
    sort_param = (request.GET.get("sort", "rating") or "rating").strip().lower()
    if sort_param == "tarif_asc":
        qs = qs.order_by("tarif_horaire")
    elif sort_param == "tarif_desc":
        qs = qs.order_by("-tarif_horaire")
    elif sort_param == "distance":
        # Tri en Python plus bas. SQL : on garde l'ordre dispo'abord puis rating
        # comme stable secondary key au cas où la distance est nulle.
        qs = qs.order_by("-disponible", "-average_rating")
    else:
        qs = qs.order_by("-average_rating", "-rating_count")

    def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
        """Distance Haversine en kilomètres entre deux points GPS."""
        r = 6371.0
        phi1 = math.radians(lat1)
        phi2 = math.radians(lat2)
        dphi = math.radians(lat2 - lat1)
        dlmb = math.radians(lon2 - lon1)
        a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlmb / 2) ** 2
        c = 2 * math.asin(min(1.0, math.sqrt(a)))
        return round(r * c, 2)

    items = []
    # Budget de géocodage réseau par requête (les villes déjà en cache sont
    # gratuites) : un prestataire sans GPS mais avec une ville obtient des
    # coordonnées approximatives → il apparaît sur la carte et a une distance.
    geo_budget = 8
    for p in qs:
        if (
            geo_budget > 0
            and (p.latitude is None or p.longitude is None)
            and (p.ville or "").strip()
        ):
            if _ensure_provider_coordinates(p):
                geo_budget -= 1

        uid = p.user_id
        avg = (
            round(float(p.average_rating), 2)
            if (p.rating_count and p.average_rating)
            else None
        )

        # Distance client → prestataire (None si l'un des deux n'a pas de GPS).
        distance_km = None
        if (
            lat_f is not None
            and lon_f is not None
            and p.latitude is not None
            and p.longitude is not None
        ):
            try:
                distance_km = _haversine_km(
                    lat_f, lon_f, float(p.latitude), float(p.longitude)
                )
            except (TypeError, ValueError):
                distance_km = None

        items.append(
            {
                "id": int(p.id),
                "nom": p.nom,
                "specialite": p.specialite,
                "ville": p.ville,
                "bio": p.bio[:200] if p.bio else "",
                "years_experience": int(p.years_experience or 0),
                "user_id": int(uid) if uid else None,
                "can_message": uid is not None,
                "average_rating": avg,
                "rating_count": int(p.rating_count or 0),
                "tarif_horaire": float(p.tarif_horaire)
                if p.tarif_horaire is not None
                else None,
                "disponible": p.disponible,
                "category_nom": (p.category.nom if p.category_id else "") or "",
                "category_icone_slug": (p.category.icone_slug or "").strip()
                if p.category_id
                else "",
                "category_icone_url": _category_icon_url(
                    request, p.category if p.category_id else None
                )
                if p.category_id
                else "",
                "has_portfolio": bool(p.portfolio_photos),
                "photo_portrait_url": _safe_photo_url(p.photo_portrait_url or "", request),
                "image_url": _safe_photo_url(p.photo_portrait_url or "", request),
                "premium_tier": (p.premium_tier if p.is_premium else "standard"),
                "premium_badge": _premium_badge_label(p),
                # Coordonnées + distance (utilisées par les apps pour afficher
                # « à 1.4 km de vous » et trier par proximité côté UI au besoin).
                "latitude": float(p.latitude) if p.latitude is not None else None,
                "longitude": float(p.longitude) if p.longitude is not None else None,
                "distance_km": distance_km,
            }
        )

    # Tri par distance demandé : on remonte les plus proches.
    # Les prestataires sans coordonnées (distance None) sont placés à la fin.
    if sort_param == "distance" and lat_f is not None and lon_f is not None:
        items.sort(
            key=lambda it: (
                0 if it.get("disponible") else 1,
                it["distance_km"] if it["distance_km"] is not None else 9_999.0,
                -1 * (it["average_rating"] or 0.0),
            )
        )

    # Rayon adaptatif : on garde le plus petit palier qui produit ≥ 1 résultat GPS.
    radius_used = None
    if pub_is_adaptive:
        gps_items = [it for it in items if it.get("distance_km") is not None]
        nogps_items = [it for it in items if it.get("distance_km") is None]
        for step in PUB_RADIUS_STEPS:
            within = [it for it in gps_items if it["distance_km"] <= step]
            if within:
                radius_used = step
                items = within + nogps_items
                break
        if radius_used is None:
            radius_used = PUB_RADIUS_STEPS[-1]
            items = nogps_items
    elif lat_f is not None and lon_f is not None:
        try:
            radius_used = float(radius) if radius else None
        except (ValueError, TypeError):
            radius_used = None

    return JsonResponse({
        "providers": items,
        "count": len(items),
        "radius_used": radius_used,
        "radius_adaptive": pub_is_adaptive,
        "radius_steps": PUB_RADIUS_STEPS,
    })


@require_GET
@require_api_auth(["client", "admin"])
def api_client_prestataires(request):
    """
    Recherche + filtres prestataires.
    Params GET :
      q          — recherche textuelle (nom, spécialité, ville)
      category   — id catégorie
      disponible — true/false
      min_rating — note minimale (0.0–5.0)
      max_tarif  — tarif horaire maximum
      sort       — 'rating' | 'tarif_asc' | 'tarif_desc' (défaut : rating desc)
    """
    _bootstrap_data()
    qs = Provider.objects.filter(
        statut=Provider.Status.VALID, is_deleted=False
    ).select_related("category")
    # Filtre textuel
    q = (request.GET.get("q") or "").strip()
    if q:
        qs = qs.filter(
            Q(nom__icontains=q) | Q(specialite__icontains=q) | Q(ville__icontains=q)
        )
    # Filtre géolocalisation avec rayon (Haversine) — supporte le mode adaptatif :
    # si radius_km est absent ou == 'auto', on essaie progressivement 5 → 15 → 30 → 50 km.
    lat = request.GET.get("lat")
    lon = request.GET.get("lon")
    radius_km = request.GET.get("radius_km")
    RADIUS_STEPS_KM = [5, 15, 30, 50]
    is_adaptive = bool(lat and lon and (not radius_km or str(radius_km).lower() == "auto"))
    if lat and lon:
        try:
            client_lat = float(lat)
            client_lon = float(lon)
            # En mode adaptatif on prend le plus large pour ne rien manquer ;
            # ensuite on filtre par paliers en Python.
            max_radius = RADIUS_STEPS_KM[-1] if is_adaptive else float(radius_km)

            lat_float = float(lat)
            lon_float = float(lon)
            approx_deg = max_radius / 111.0
            from django.db.models import Q
            qs = qs.filter(
                Q(
                    latitude__isnull=False,
                    longitude__isnull=False,
                    latitude__gte=lat_float - approx_deg,
                    latitude__lte=lat_float + approx_deg,
                    longitude__gte=lon_float - approx_deg,
                    longitude__lte=lon_float + approx_deg,
                )
                | Q(latitude__isnull=True)
                | Q(longitude__isnull=True)
            )
        except (ValueError, TypeError):
            pass

    # Filtre catégorie
    category_id = request.GET.get("category")
    if category_id and str(category_id).isdigit():
        qs = qs.filter(category_id=int(category_id))
    # Filtre disponibilité
    disponible_param = request.GET.get("disponible", "").lower()
    if disponible_param == "true":
        qs = qs.filter(disponible=True)
    elif disponible_param == "false":
        qs = qs.filter(disponible=False)
    # Filtre note minimale
    min_rating_param = request.GET.get("min_rating")
    if min_rating_param:
        try:
            min_r = float(min_rating_param)
            qs = qs.filter(average_rating__gte=min_r)
        except ValueError:
            pass
    # Filtre tarif maximum
    max_tarif_param = request.GET.get("max_tarif")
    if max_tarif_param:
        try:
            max_t = float(max_tarif_param)
            qs = qs.filter(tarif_horaire__lte=max_t)
        except ValueError:
            pass
    # Rang premium : Gold (2) > Silver (1) > Standard (0) — mise en avant des abonnés
    from django.db.models import Case, When, Value, IntegerField
    qs = qs.annotate(
        premium_rank=Case(
            When(is_premium=True, premium_tier="gold", then=Value(2)),
            When(is_premium=True, premium_tier="silver", then=Value(1)),
            default=Value(0),
            output_field=IntegerField(),
        )
    )
    # Tri (le premium est toujours mis en avant en tête de tri)
    sort_param = request.GET.get("sort", "rating")
    if sort_param == "tarif_asc":
        qs = qs.order_by("-premium_rank", "tarif_horaire")
    elif sort_param == "tarif_desc":
        qs = qs.order_by("-premium_rank", "-tarif_horaire")
    else:
        qs = qs.order_by("-premium_rank", "-average_rating", "-rating_count")

    # Préparer le calcul de distance Haversine
    import math as _math

    client_lat_f = None
    client_lon_f = None
    max_radius_f = None
    if lat and lon:
        try:
            client_lat_f = float(lat)
            client_lon_f = float(lon)
            # Cap au plus large palier en mode adaptatif (50 km),
            # ou rayon explicite si fourni.
            max_radius_f = (
                float(RADIUS_STEPS_KM[-1]) if is_adaptive else float(radius_km)
            )
        except (ValueError, TypeError):
            pass

    def haversine_km(lat1, lon1, lat2, lon2):
        R = 6371.0
        dlat = _math.radians(lat2 - lat1)
        dlon = _math.radians(lon2 - lon1)
        a = (
            _math.sin(dlat / 2) ** 2
            + _math.cos(_math.radians(lat1))
            * _math.cos(_math.radians(lat2))
            * _math.sin(dlon / 2) ** 2
        )
        return R * 2 * _math.atan2(_math.sqrt(a), _math.sqrt(1 - a))

    # Pagination
    try:
        page = max(1, int(request.GET.get("page", 1)))
        page_size = min(50, max(1, int(request.GET.get("page_size", 20))))
    except ValueError:
        page = 1
        page_size = 20
    total_filtered = qs.count()
    offset = (page - 1) * page_size
    qs = qs[offset:offset + page_size]

    items = []
    # Géocodage best-effort ville → coords (cache + sauvegarde) pour les
    # prestataires sans GPS, afin qu'ils apparaissent sur la carte.
    geo_budget = 8
    for p in qs:
        if (
            geo_budget > 0
            and (p.latitude is None or p.longitude is None)
            and (p.ville or "").strip()
        ):
            if _ensure_provider_coordinates(p):
                geo_budget -= 1

        uid = p.user_id
        avg = (
            round(float(p.average_rating), 2)
            if (p.rating_count and p.average_rating)
            else None
        )
        # Calcul distance si position dispo
        dist_km = None
        if client_lat_f and client_lon_f and p.latitude and p.longitude:
            try:
                dist_km = haversine_km(
                    client_lat_f, client_lon_f, float(p.latitude), float(p.longitude)
                )
                if max_radius_f and dist_km > max_radius_f:
                    continue  # Skip if beyond radius
            except (ValueError, TypeError):
                pass
        items.append(
            {
                "id": int(p.id),
                "nom": p.nom,
                "specialite": p.specialite,
                "ville": p.ville,
                "bio": p.bio[:200] if p.bio else "",
                "years_experience": int(p.years_experience or 0),
                "user_id": int(uid) if uid else None,
                "can_message": uid is not None,
                "average_rating": avg,
                "rating_count": int(p.rating_count or 0),
                "tarif_horaire": float(p.tarif_horaire)
                if p.tarif_horaire is not None
                else None,
                "disponible": p.disponible,
                "latitude": p.latitude,
                "longitude": p.longitude,
                "distance_km": round(dist_km, 1) if dist_km else None,
                "category_nom": (p.category.nom if p.category_id else "") or "",
                "category_icone_slug": (p.category.icone_slug or "").strip()
                if p.category_id
                else "",
                "category_icone_url": _category_icon_url(
                    request, p.category if p.category_id else None
                )
                if p.category_id
                else "",
                "has_portfolio": bool(p.portfolio_photos),
                "is_certified": p.is_certified,
                "photo_portrait_url": _safe_photo_url(p.photo_portrait_url or "", request),
                "premium_tier": (p.premium_tier if p.is_premium else "standard"),
                "premium_badge": _premium_badge_label(p),
            }
        )
    # ── Rayon adaptatif : choisir le plus petit palier non vide ────────────────
    radius_used = None
    if is_adaptive:
        gps_items = [it for it in items if it.get("distance_km") is not None]
        nogps_items = [it for it in items if it.get("distance_km") is None]
        for step in RADIUS_STEPS_KM:
            within = [it for it in gps_items if it["distance_km"] <= step]
            if within:
                radius_used = step
                items = within + nogps_items
                break
        if radius_used is None:
            # Aucun prestataire GPS dans le périmètre max → on retourne ce qu'il y a.
            radius_used = RADIUS_STEPS_KM[-1]
            items = nogps_items
        total_filtered = len(items)
    elif max_radius_f:
        radius_used = max_radius_f

    return JsonResponse({
        "items": items,
        "total": total_filtered,
        "page": page,
        "page_size": page_size,
        "total_pages": (total_filtered + page_size - 1) // page_size,
        "radius_used": radius_used,
        "radius_adaptive": is_adaptive,
        "radius_steps": RADIUS_STEPS_KM,
    })


@require_GET
@require_api_auth(["client", "admin"])
def api_client_conversations(request):
    uid = request.api_user_id
    convs = (
        Conversation.objects.filter(client_id=uid)
        .select_related("prestataire", "reservation")
        .order_by("-updated_at")  # plus récentes d'abord
    )
    data = []
    for c in convs:
        last = c.messages.order_by("-created_at").first()
        # On masque les conversations VIDES (créées automatiquement avec la
        # réservation mais sans aucun échange) — elles polluaient la liste avec
        # de fausses « Nouvelle conversation ». Dès qu'un message/devis/événement
        # existe, la conversation réapparaît.
        if last is None:
            continue
        preview = (last.body[:120] if last.body else "") or (
            "[Photo]" if last.image else ""
        )
        res = c.reservation
        data.append(
            {
                "id": int(c.id),
                "prestataire_username": c.prestataire.username,
                "prestataire_id": int(c.prestataire_id),
                "last_message": preview,
                "updated_at": c.updated_at.isoformat(),
                # Alias lu par l'app (affichage de l'horodatage).
                "last_date": c.updated_at.isoformat(),
                "unread_count": _conversation_unread_for_user(c, uid),
                "reservation_reference": res.reference if res else "",
                "conversation_title": (
                    f"{res.title or res.reference} — {res.reference}"
                    if res
                    else c.prestataire.username
                ),
            }
        )
    return JsonResponse({"conversations": data})


@require_GET
def api_client_prestataire_detail(request, pk):
    """API client: get single provider detail (avec avis + photos de travaux)."""
    try:
        p = Provider.objects.filter(pk=int(pk), statut="Valide").first()
    except ValueError:
        return JsonResponse({"error": "invalid_provider_id"}, status=400)
    if not p:
        return JsonResponse({"error": "provider_not_found"}, status=404)

    # ── Avis reçus (note, commentaire, client, date, photos jointes) ──────────
    avis = []
    ratings = (
        Rating.objects.filter(provider=p)
        .select_related("client", "reservation")
        .order_by("-created_at")[:50]
    )
    for r in ratings:
        client_name = "Client"
        if r.client:
            client_name = (r.client.get_full_name() or r.client.username or "Client").strip()
        _photos = [_safe_photo_url(u, request) for u in (r.photo_attachments or [])]
        avis.append(
            {
                "note": r.note,
                "commentaire": r.commentaire or "",
                # alias multiples pour compat UI
                "client": client_name,
                "auteur": client_name,
                "client_name": client_name,
                "date": r.created_at.strftime("%d/%m/%Y") if r.created_at else "",
                "photos": _photos,
                "photo_proof": _photos,
            }
        )

    # ── Photos des travaux réalisés (avis + preuves de prestations terminées) ──
    travaux = []
    for r in ratings:
        for u in (r.photo_attachments or []):
            travaux.append(_safe_photo_url(u, request))
    done_res = (
        Reservation.objects.filter(
            assigned_provider=p, statut=Reservation.Status.DONE
        )
        .order_by("-prestation_terminee_at")[:30]
    )
    for res in done_res:
        for field in (res.preuve_photos, res.photos_apres, res.photos_avant):
            for u in (field or []):
                travaux.append(_safe_photo_url(u, request))
    # Dédoublonnage en gardant l'ordre, limite raisonnable
    seen = set()
    travaux = [u for u in travaux if u and not (u in seen or seen.add(u))][:24]

    return JsonResponse(
        {
            "id": p.id,
            # Compte utilisateur lié : indispensable pour que les boutons
            # « Message » et « Appel » de la fiche fonctionnent (sinon no-op).
            "user_id": p.user_id,
            "nom": p.nom,
            "specialite": p.specialite,
            "ville": p.ville,
            "tarif_horaire": float(p.tarif_horaire) if p.tarif_horaire else None,
            "disponible": p.disponible,
            "rating_count": p.rating_count or 0,
            "nb_avis": p.rating_count or 0,
            "average_rating": float(p.average_rating) if p.average_rating else 0.0,
            "bio": p.bio or "",
            "years_experience": p.years_experience or 0,
            "is_certified": p.is_certified,
            "is_premium": bool(p.is_premium),
            "premium_tier": (p.premium_tier if p.is_premium else "standard"),
            "premium_badge": _premium_badge_label(p),
            "latitude": p.latitude,
            "longitude": p.longitude,
            "photo_portrait_url": _safe_photo_url(p.photo_portrait_url or "", request),
            "portfolio_photos": p.portfolio_photos or [],
            "avis": avis,
            "travaux": travaux,
            "category": {"id": p.category.id, "nom": p.category.nom}
            if p.category
            else None,
        }
    )


@csrf_exempt
@require_http_methods(["GET", "POST"])
def api_messages(request):
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        return JsonResponse({"error": "missing_token"}, status=401)
    token = auth_header.split(" ", 1)[1].strip()
    payload = verify_token(token)
    if not payload:
        return JsonResponse({"error": "invalid_token"}, status=401)
    role = payload.get("role")
    if role not in {"client", "prestataire", "admin"}:
        return JsonResponse({"error": "forbidden_role"}, status=403)
    request.api_user_id = payload.get("uid")
    request.api_role = role

    if request.method == "GET":
        return _api_messages_list(request)
    return _api_messages_send(request)


@require_GET
@require_api_auth(["client", "prestataire", "admin"])
def api_messages_by_reservation(request, reservation_reference):
    """Récupère les messages pour une réservation spécifique."""
    _bootstrap_data()
    res = Reservation.objects.filter(reference=reservation_reference).first()
    if not res:
        return JsonResponse({"error": "reservation_not_found"}, status=404)

    uid = int(request.api_user_id)
    if request.api_role == "client" and res.client_user_id != uid:
        return JsonResponse({"error": "forbidden"}, status=403)
    if (
        request.api_role == "prestataire"
        and res.assigned_provider_id
        and res.prestataire_user_id != uid
    ):
        return JsonResponse({"error": "forbidden"}, status=403)

    conv = Conversation.objects.filter(reservation=res).first()
    if not conv:
        return JsonResponse({"messages": []})

    messages = (
        Message.objects.filter(conversation=conv)
        .select_related("sender")
        .order_by("created_at")
    )

    messages_data = []
    for m in messages:
        sender_type = "client" if m.sender_id == res.client_user_id else "prestataire"
        messages_data.append(
            {
                "id": m.id,
                "message": m.body,
                "sender_type": sender_type,
                "sender_name": m.sender.username if m.sender else "",
                "created_at": m.created_at.isoformat() if m.created_at else "",
            }
        )

    return JsonResponse({"messages": messages_data})


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client", "prestataire", "admin"])
def api_messages_send_by_reservation(request):
    """Envoie un message pour une réservation spécifique."""
    _bootstrap_data()
    try:
        payload_data = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)

    reservation_ref = payload_data.get("reservation_reference")
    message_text = payload_data.get("message", "").strip()

    if not reservation_ref:
        return JsonResponse({"error": "reservation_reference_required"}, status=400)
    if not message_text:
        return JsonResponse({"error": "message_required"}, status=400)

    res = Reservation.objects.filter(reference=reservation_ref).first()
    if not res:
        return JsonResponse({"error": "reservation_not_found"}, status=404)

    uid = int(request.api_user_id)
    if request.api_role == "client" and res.client_user_id != uid:
        return JsonResponse({"error": "forbidden"}, status=403)
    if (
        request.api_role == "prestataire"
        and res.prestataire_user_id
        and res.prestataire_user_id != uid
    ):
        return JsonResponse({"error": "forbidden"}, status=403)

    conv = Conversation.objects.filter(reservation=res).first()
    if not conv:
        # Conversation.prestataire est une FK vers User → utiliser le User id
        # du prestataire (prestataire_user_id), PAS l'id du Provider
        # (assigned_provider_id), sinon mauvais destinataire / violation FK.
        conv = Conversation.objects.create(
            client_id=res.client_user_id,
            prestataire_id=res.prestataire_user_id,
            reservation=res,
        )

    sender = User.objects.filter(pk=uid).first()
    from .text_utils import mask_contacts

    message = Message.objects.create(
        conversation=conv,
        sender=sender,
        body=mask_contacts(message_text),
    )

    _schedule(
        [
            res.client_user_id
            if request.api_role != "client"
            else res.prestataire_user_id
        ],
        "Nouveau message BABIFIX",
        f"Vous avez un nouveau message concernant {reservation_ref}",
        {"type": "chat.message", "reference": reservation_ref},
    )

    # Broadcast WebSocket : les 2 apps reçoivent le nouveau message en live
    # (bannière toast + son si l'app est ouverte sur l'écran chat ou même
    # ailleurs — le service WS global déclenche la notif overlay).
    try:
        from . import realtime
        realtime.broadcast_chat_message(
            conv.id,
            {
                "id": message.id,
                "conversation_id": conv.id,
                "sender_id": sender.id,
                "sender_role": request.api_role,
                "body": message.body,
                "created_at": message.created_at.isoformat() if hasattr(message, "created_at") and message.created_at else "",
                "reservation_reference": reservation_ref,
            },
        )
    except Exception as exc:
        logger.warning("WS broadcast chat_message failed: %s", exc)

    return JsonResponse(
        {
            "ok": True,
            "message_id": message.id,
        }
    )


@csrf_exempt
@require_http_methods(["GET", "POST"])
@require_api_auth(["client", "prestataire", "admin"])
def api_messages(request):
    # POST = envoi d'un message. Sans ce dispatch, /api/messages était GET-only
    # et tout envoi renvoyait 405 (« erreur » côté client/prestataire).
    if request.method == "POST":
        return _api_messages_send(request)
    uid = int(request.api_user_id)
    prestataire_id = request.GET.get("prestataire_id")
    client_id = request.GET.get("client_id")
    reservation_id = request.GET.get("reservation_id")
    conv_id = request.GET.get("conversation_id") or request.GET.get("conv_id")
    conv = None
    if conv_id and str(conv_id).isdigit():
        conv = (
            Conversation.objects.filter(id=int(conv_id))
            .select_related("reservation")
            .first()
        )
    elif reservation_id and str(reservation_id).isdigit():
        rid = int(reservation_id)
        res = Reservation.objects.filter(pk=rid).first()
        if not res:
            return JsonResponse({"error": "not_found"}, status=404)
        if (
            res.client_user_id != uid
            and res.prestataire_user_id != uid
            and request.api_role != "admin"
        ):
            return JsonResponse({"error": "forbidden"}, status=403)
        conv = (
            Conversation.objects.filter(reservation_id=rid)
            .select_related("reservation")
            .first()
        )
        if conv is None and res.client_user_id and res.prestataire_user_id:
            conv = Conversation.objects.create(
                client_id=res.client_user_id,
                prestataire_id=res.prestataire_user_id,
                reservation_id=rid,
            )
            conv = (
                Conversation.objects.filter(pk=conv.pk)
                .select_related("reservation")
                .first()
            )
    elif prestataire_id and request.api_role == "client":
        return JsonResponse(
            {
                "error": "reservation_required",
                "detail": "Le chat BABIFIX est ouvert uniquement après une réservation (passer reservation_id).",
            },
            status=400,
        )
    elif client_id and request.api_role == "prestataire":
        return JsonResponse(
            {
                "error": "reservation_required",
                "detail": "Le chat BABIFIX est ouvert uniquement après une réservation (passer reservation_id).",
            },
            status=400,
        )
    else:
        return JsonResponse({"error": "conversation_or_peer_required"}, status=400)

    if conv is None:
        return JsonResponse({"error": "not_found"}, status=404)
    if (
        conv.client_id != uid
        and conv.prestataire_id != uid
        and request.api_role != "admin"
    ):
        return JsonResponse({"error": "forbidden"}, status=403)
    _mark_conversation_messages_read(conv, uid)
    msgs = [_msg_dict(request, m) for m in conv.messages.filter(deleted=False)]
    res_ref = ""
    res_title = ""
    if conv.reservation_id:
        r0 = conv.reservation
        if r0:
            res_ref = r0.reference
            res_title = r0.title or r0.reference
    return JsonResponse(
        {
            "conversation_id": int(conv.id),
            "reservation_reference": res_ref,
            "reservation_title": res_title,
            "messages": msgs,
        }
    )


def _api_messages_send(request):
    uid = int(request.api_user_id)
    conv_id = None
    body = ""
    reply_to_id = None
    image = None
    audio = None
    audio_duration = 0

    ct = request.content_type or ""
    if "multipart/form-data" in ct:
        try:
            conv_id = int(request.POST.get("conversation_id") or "0")
        except ValueError:
            conv_id = 0
        body = request.POST.get("body", "") or ""
        rt = request.POST.get("reply_to_id")
        if rt:
            try:
                reply_to_id = int(rt)
            except ValueError:
                reply_to_id = None
        image = request.FILES.get("image")
        if image is not None:
            from .secure_uploads import SafeUploadError, validate_image_upload
            try:
                image = validate_image_upload(image, max_mb=8)
            except SafeUploadError as exc:
                return JsonResponse({"error": str(exc)}, status=400)
        audio = request.FILES.get("audio")
        if audio is not None:
            from .secure_uploads import SafeUploadError, validate_audio_upload
            try:
                audio = validate_audio_upload(audio, max_mb=12)
            except SafeUploadError as exc:
                return JsonResponse({"error": str(exc)}, status=400)
        try:
            audio_duration = int(request.POST.get("audio_duration") or 0)
        except (TypeError, ValueError):
            audio_duration = 0
    else:
        try:
            payload = json.loads(request.body.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            return JsonResponse({"error": "invalid_json"}, status=400)
        try:
            conv_id = int(payload.get("conversation_id") or 0)
        except (TypeError, ValueError):
            conv_id = 0
        body = str(payload.get("body", "") or "")
        rt = payload.get("reply_to_id")
        if rt is not None:
            try:
                reply_to_id = int(rt)
            except (TypeError, ValueError):
                reply_to_id = None

    if not conv_id:
        return JsonResponse({"error": "conversation_id_required"}, status=400)

    conv = Conversation.objects.filter(id=conv_id).first()
    if not conv:
        return JsonResponse({"error": "not_found"}, status=404)
    if (
        conv.client_id != uid
        and conv.prestataire_id != uid
        and request.api_role != "admin"
    ):
        return JsonResponse({"error": "forbidden"}, status=403)

    # Règle métier : pas de message avant accord. Les messages SYSTEM/DEVIS_CARD
    # (générés par le serveur, sender = système) ne sont pas concernés ; ici on
    # bloque les messages utilisateurs tant que le prestataire n'a pas accepté.
    if request.api_role != "admin" and conv.reservation_id:
        res_link = conv.reservation
        if res_link and not res_link.contact_allowed():
            return JsonResponse(
                {
                    "error": "contact_not_allowed",
                    "detail": (
                        "Vous pourrez échanger des messages une fois que le "
                        "prestataire aura accepté la demande."
                    ),
                },
                status=403,
            )
        # Après la prestation terminée, la messagerie est clôturée — SAUF si un
        # litige est ouvert (pour échanger sur le problème). Pour signaler un
        # souci, on passe par « Signaler un problème » (avec preuves).
        if (
            res_link
            and normalize_reservation_status(res_link.statut) == "Terminee"
            and not getattr(res_link, "dispute_ouverte", False)
        ):
            return JsonResponse(
                {
                    "error": "prestation_terminee",
                    "detail": (
                        "La prestation est terminée : la messagerie est clôturée. "
                        "En cas de problème, utilisez « Signaler un problème » "
                        "(avec photos à l'appui)."
                    ),
                },
                status=403,
            )

    msg = Message(
        conversation=conv,
        sender_id=uid,
        body=body,
        reply_to_id=reply_to_id,
    )
    if image:
        msg.image = image
    if audio:
        msg.audio = audio
        msg.audio_duration = max(0, min(audio_duration, 600))  # plafonné à 10 min
    msg.save()
    conv.save(update_fields=[])  # bump updated_at
    Conversation.objects.filter(pk=conv.pk).update(updated_at=timezone.now())
    return JsonResponse({"ok": True, "message": _msg_dict(request, msg)}, status=201)


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client", "admin"])
def api_client_create_reservation(request):
    _bootstrap_data()
    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    title = str(payload.get("title", "")).strip()
    amount_raw = payload.get("amount", payload.get("montant", "0"))
    amount_numeric = float(parse_money_amount(amount_raw, default="0"))
    if not title:
        return JsonResponse({"error": "title_required"}, status=400)

    user = User.objects.filter(id=request.api_user_id).first()
    client_label = (user.get_full_name() or user.username) if user else "Client Mobile"

    prov = None
    pid = payload.get("provider_id")
    if pid is not None and str(pid).isdigit():
        prov = Provider.objects.filter(
            id=int(pid), statut=Provider.Status.VALID
        ).first()

    # Vérifier si le prestataire est disponible
    if prov and not prov.disponible:
        return JsonResponse(
            {
                "error": "provider_unavailable",
                "message": "Ce prestataire n'est pas disponible actuellement.",
            },
            status=400,
        )

    # NOTE : on NE bloque PAS la réservation selon les indisponibilités « du
    # jour ». Une réservation est une DEMANDE dont la date réelle est négociée
    # ensuite (devis + créneau choisi). Bloquer sur la date du jour empêchait à
    # tort toute réservation (même pour une date future) → « impossible
    # aujourd'hui ». La disponibilité par date est gérée via le calendrier de
    # créneaux (le client choisit un créneau réellement libre).

    # Règle métier : un client ne peut pas avoir 2 réservations EN COURS avec le
    # même prestataire. Tant qu'une n'est pas « Terminee » ou « Annulee », on
    # bloque la création d'une nouvelle (message clair côté app).
    if prov:
        _TERMINAL_STATUSES = ("Terminee", "Annulee")
        has_active = (
            Reservation.objects.filter(
                client_user_id=request.api_user_id,
                assigned_provider=prov,
            )
            .exclude(statut__in=_TERMINAL_STATUSES)
            .exists()
        )
        if has_active:
            return JsonResponse(
                {
                    "error": "reservation_already_active",
                    "message": (
                        "Vous avez déjà une réservation en cours avec ce "
                        "prestataire. Terminez-la avant d'en créer une nouvelle."
                    ),
                },
                status=409,
            )

    prest_label = prov.nom if prov else "A affecter"
    prest_user_id = prov.user_id if prov else None

    lat = payload.get("latitude")
    lon = payload.get("longitude")
    try:
        lat_f = float(lat) if lat is not None and lat != "" else None
    except (TypeError, ValueError):
        lat_f = None
    try:
        lon_f = float(lon) if lon is not None and lon != "" else None
    except (TypeError, ValueError):
        lon_f = None

    address_label = str(payload.get("address_label", "") or "")[:500]
    # Champs structurés (peut être envoyés explicitement par le client).
    address_street = str(payload.get("address_street", "") or "")[:200]
    address_quartier = str(payload.get("address_quartier", "") or "")[:120]
    address_ville = str(payload.get("address_ville", "") or "")[:120]
    address_pays = str(payload.get("address_pays", "") or "Côte d'Ivoire")[:80]
    address_repere = str(payload.get("address_repere", "") or "")[:300]

    # Fallback : si aucune adresse texte n'a été fournie mais qu'on a des
    # coordonnées GPS, le backend fait lui-même un reverse geocoding
    # Nominatim et remplit les 5 champs structurés + le label résumé.
    _need_geocode = (
        not (address_label.strip() or address_street.strip()
             or address_quartier.strip() or address_ville.strip())
        and lat_f is not None and lon_f is not None
    )
    if _need_geocode:
        try:
            import requests as _req
            nom = _req.get(
                "https://nominatim.openstreetmap.org/reverse",
                params={
                    "lat": lat_f,
                    "lon": lon_f,
                    "format": "json",
                    "addressdetails": 1,
                    "accept-language": "fr",
                    "zoom": 16,
                },
                headers={"User-Agent": "BABIFIX/1.0 backend"},
                timeout=4,
            )
            if nom.status_code == 200:
                jd = nom.json()
                ad = jd.get("address") or {}
                # Rue (+ numéro si dispo)
                house = (ad.get("house_number") or "").strip()
                road = (ad.get("road") or ad.get("street")
                        or ad.get("pedestrian") or "").strip()
                if road:
                    address_street = (f"{house} {road}".strip())[:200]
                # Quartier
                q = (ad.get("suburb") or ad.get("neighbourhood")
                     or ad.get("quarter") or ad.get("city_district")
                     or ad.get("hamlet") or "").strip()
                if q:
                    address_quartier = q[:120]
                # Ville
                v = (ad.get("city") or ad.get("town")
                     or ad.get("municipality") or ad.get("village")
                     or ad.get("county") or "").strip()
                if v:
                    address_ville = v[:120]
                # Pays
                p = (ad.get("country") or "").strip()
                if p:
                    address_pays = p[:80]
                # Résumé compact
                pieces = [x for x in [address_street, address_quartier, address_ville] if x]
                if pieces:
                    address_label = ", ".join(pieces)[:500]
                elif jd.get("display_name"):
                    parts = [p.strip() for p in str(jd["display_name"]).split(",")][:3]
                    address_label = ", ".join([p for p in parts if p])[:500]
        except Exception:
            # Échec silencieux : la résa est créée quand même avec lat/lon
            # seuls. L'app prestataire pourra ouvrir Google Maps avec les
            # coordonnées brutes.
            pass
    # Si address_label vide mais champs structurés remplis (cas où le client
    # envoie déjà la décomposition), on reconstruit le résumé compact.
    if not address_label.strip():
        pieces = [x for x in [address_street, address_quartier, address_ville] if x.strip()]
        if pieces:
            address_label = ", ".join(pieces)[:500]
    loc_time = timezone.now() if (lat_f is not None and lon_f is not None) else None

    pt_raw = str(payload.get("payment_type", "") or "").upper().replace(" ", "_")
    payment_type = Reservation.PaymentType.ESPECES
    if pt_raw in {Reservation.PaymentType.MOBILE_MONEY, "MOBILE_MONEY"}:
        payment_type = Reservation.PaymentType.MOBILE_MONEY
    elif pt_raw in {Reservation.PaymentType.CARTE, "CARTE"}:
        payment_type = Reservation.PaymentType.CARTE
    elif pt_raw in {Reservation.PaymentType.AUTRE, "AUTRE"}:
        payment_type = Reservation.PaymentType.AUTRE
    client_message = str(
        payload.get("message", "") or payload.get("client_message", "") or ""
    )[:2000]
    mobile_money_operator = _parse_mobile_money_operator(payload, payment_type)
    # Prix proposé par le client (optionnel)
    prix_propose_raw = payload.get("prix_propose")
    try:
        prix_propose = (
            float(prix_propose_raw)
            if prix_propose_raw not in (None, "", 0, "0")
            else None
        )
    except (TypeError, ValueError):
        prix_propose = None

    preuve_list: list[str] = []
    raw_photos = payload.get("photo_attachments") or payload.get("preuve_photos") or []
    if isinstance(raw_photos, list):
        for entry in raw_photos[:6]:
            s = str(entry).strip()
            if not s.startswith("data:image/"):
                continue
            if len(s) > 600_000:
                s = s[:600_000]
            preuve_list.append(s)

    use_quote_flow = bool(payload.get("use_devis", False)) or any(
        [
            bool(str(payload.get("description_probleme", "") or "").strip()),
            bool(str(payload.get("disponibilites_client", "") or "").strip()),
            bool(preuve_list),
            prix_propose is not None,
            bool(payload.get("is_urgent", False)),
        ]
    )
    initial_status = (
        Reservation.Status.DEMANDE_ENVOYEE
        if use_quote_flow
        else Reservation.Status.PENDING
    )

    # Génération de la référence. ATTENTION : ne PAS utiliser
    # `select_for_update().count()` → PostgreSQL interdit FOR UPDATE avec une
    # fonction d'agrégat (COUNT) → « FOR UPDATE is not allowed with aggregate
    # functions » → 500 à CHAQUE création de réservation. On compte simplement
    # et la boucle `while` règle les collisions de référence.
    existing_count = Reservation.objects.count() + 1
    while Reservation.objects.filter(
        reference=f"RES-{existing_count:03d}"
    ).exists():
        existing_count += 1
    reference = f"RES-{existing_count:03d}"

    # Générer clé d'idempotence pour éviter double paiement
    idem_key = str(uuid.uuid4())

    # Surcharge urgence +20%
    is_urgent = bool(payload.get("is_urgent", False))
    urgence_surcharge_pct = 0
    if is_urgent and amount_numeric > 0:
        urgence_surcharge_pct = 20
        amount_numeric = round(amount_numeric * 1.20, 2)

    # Date prévue de l'intervention choisie par le client (ISO yyyy-mm-dd).
    scheduled_date_val = None
    _sd_raw = str(payload.get("scheduled_date", "") or "").strip()
    if _sd_raw:
        try:
            from datetime import date as _date
            scheduled_date_val = _date.fromisoformat(_sd_raw[:10])
        except ValueError:
            scheduled_date_val = None

    try:
      res_obj = Reservation.objects.create(
        scheduled_date=scheduled_date_val,
        reference=reference,
        title=title or "Demande de service",
        client=client_label,
        prestataire=prest_label,
        montant=amount_numeric,
        statut=initial_status,
        latitude=lat_f,
        longitude=lon_f,
        address_label=address_label,
        address_street=address_street,
        address_quartier=address_quartier,
        address_ville=address_ville,
        address_pays=address_pays,
        address_repere=address_repere,
        location_captured_at=loc_time,
        client_user=user,
        prestataire_user_id=prest_user_id,
        assigned_provider=prov,
        payment_type=payment_type,
        mobile_money_operator=mobile_money_operator,
        client_message=client_message,
        preuve_photos=preuve_list,
        prix_propose=prix_propose,
        description_probleme=str(payload.get("description_probleme", "") or "")[:2000],
        demande_type=str(payload.get("demande_type", "") or "")[:20],
        audio_probleme=str(payload.get("audio_probleme", "") or "")[:500],
        reponses_exigences=(
            payload.get("reponses_exigences")
            if isinstance(payload.get("reponses_exigences"), dict)
            else {}
        ),
        disponibilites_client=str(payload.get("disponibilites_client", "") or "")[:255],
        is_urgent=is_urgent,
        urgence_surcharge_pct=urgence_surcharge_pct,
        idempotency_key=idem_key,
        appel_masque=True,  # Activer masquage par défaut
        # Privacy : adresse fine masquée tant qu'aucun prestataire n'a accepté.
        # Bascule à False dans api_prestataire_decide_request (action ACCEPT).
        address_is_approximate=True,
      )
    except Exception:  # Filet de sécurité : on logue la vraie cause, message neutre côté client.
        import traceback as _tb
        logger.error("create_reservation FAILED:\n%s", _tb.format_exc())
        return JsonResponse(
            {
                "error": "create_failed",
                "message": "La création de la réservation a échoué. Réessayez.",
            },
            status=500,
        )
    if res_obj.client_user_id and res_obj.prestataire_user_id:
        Conversation.objects.get_or_create(
            reservation=res_obj,
            defaults={
                "client_id": res_obj.client_user_id,
                "prestataire_id": res_obj.prestataire_user_id,
            },
        )
    Notification.objects.create(title=f"Nouvelle reservation creee: {title}")

    # Notification WhatsApp urgence au prestataire
    if is_urgent and prov and prov.user_id:
        try:
            from adminpanel.services.whatsapp_service import notify_user_if_opted_in, send_urgent_request
            from django.contrib.auth.models import User as DjUser
            prest_user = DjUser.objects.filter(pk=prov.user_id).first()
            if prest_user:
                notify_user_if_opted_in(
                    prest_user,
                    message="",
                    template_fn=send_urgent_request,
                    nom_prestataire=prov.nom,
                    reference=reference,
                    adresse=address_label or "Non précisée",
                )
        except Exception:
            pass

    return JsonResponse({
        "ok": True,
        "reference": reference,
        "montant_final": float(amount_numeric),
        "urgence_surcharge_pct": urgence_surcharge_pct,
        "is_urgent": is_urgent,
    }, status=201)


@csrf_exempt
@require_http_methods(["POST"])
def api_prestataire_register(request):
    """
    Crée ou met à jour le dossier prestataire (Provider).
    Recommandé : JWT rôle prestataire (compte créé via POST /api/auth/register) pour lier user_id
    (FCM, /api/prestataire/me, notifications).
    Sans JWT : dossier orphelin (visible admin) — déconseillé pour l’app mobile.
    """
    _bootstrap_data()
    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    nom = str(payload.get("nom", "")).strip()
    specialite = str(payload.get("specialite", "")).strip()
    ville_raw = (
        str(payload.get("service_city") or "").strip()
        or str(payload.get("ville") or "").strip()
        or str(payload.get("service_address_label") or "").strip()
    )
    if "," in ville_raw:
        ville_raw = ville_raw.split(",", 1)[0].strip()
    ville = (ville_raw or "Non precisee")[:80]
    category_id = payload.get("category_id")
    cat_obj = None
    if category_id is not None and str(category_id).strip() != "":
        try:
            cid = int(category_id)
            cat_obj = Category.objects.filter(pk=cid, actif=True).first()
        except (TypeError, ValueError):
            cat_obj = None
        if cat_obj:
            specialite = (cat_obj.nom or specialite or "").strip()
    if not nom or not specialite:
        return JsonResponse({"error": "nom_specialite_required"}, status=400)

    try:
        years_exp = int(payload.get("years_experience", 0))
    except (TypeError, ValueError):
        years_exp = 0
    years_exp = max(0, min(years_exp, 60))

    bio = str(payload.get("bio", "") or "")[:2000]
    phone_e164 = str(payload.get("phone_e164", "") or "")[:24]
    email = str(payload.get("email", "") or "").strip()[:254]
    # Photo portrait — base64 → fichier sur disque
    photo_portrait_url = str(payload.get("photo_portrait_url", "") or "").strip()
    if not photo_portrait_url:
        b64 = payload.get("photo_portrait_b64") or ""
        if isinstance(b64, str) and b64.startswith("data:"):
            photo_portrait_url = _decode_and_save_media(b64, "portraits", "portrait")
    # CNI — base64 → fichier sur disque
    cni_url = str(
        payload.get("cni_url", "") or payload.get("kyc_document_url", "") or ""
    ).strip()
    if not cni_url:
        b64 = payload.get("cni_b64") or ""
        if isinstance(b64, str) and b64.startswith("data:"):
            cni_url = _decode_and_save_media(b64, "cni", "cni")
    cni_recto_url = str(payload.get("cni_recto_url", "") or "").strip()
    if not cni_recto_url:
        b64 = payload.get("cni_recto_b64") or ""
        if isinstance(b64, str) and b64.startswith("data:"):
            cni_recto_url = _decode_and_save_media(b64, "cni", "cni_recto")
    cni_verso_url = str(payload.get("cni_verso_url", "") or "").strip()
    if not cni_verso_url:
        b64 = payload.get("cni_verso_b64") or ""
        if isinstance(b64, str) and b64.startswith("data:"):
            cni_verso_url = _decode_and_save_media(b64, "cni", "cni_verso")
    selfie_url = str(payload.get("selfie_url", "") or "").strip()
    if not selfie_url:
        b64 = payload.get("selfie_b64") or ""
        if isinstance(b64, str) and b64.startswith("data:"):
            selfie_url = _decode_and_save_media(b64, "selfies", "selfie")
    video_intro_url = str(payload.get("video_intro_url", "") or "").strip()
    if not video_intro_url:
        b64 = payload.get("video_intro_b64") or ""
        if isinstance(b64, str) and b64.startswith("data:"):
            video_intro_url = _decode_and_save_media(b64, "videos", "video_intro")
    # Si recto fourni, on l'utilise aussi comme cni_url pour rétrocompatibilité
    if cni_recto_url and not cni_url:
        cni_url = cni_recto_url

    auth_header = request.headers.get("Authorization", "")
    user_id = None
    pl = None
    if auth_header.startswith("Bearer "):
        tok = auth_header.split(" ", 1)[1].strip()
        pl = verify_token(tok)
        if pl and pl.get("role") == UserProfile.Role.PRESTATAIRE:
            user_id = pl.get("uid")

    if user_id:
        provider = Provider.objects.filter(user_id=user_id).first()
        if provider:
            provider.nom = nom
            provider.specialite = specialite
            provider.ville = ville
            provider.years_experience = years_exp
            provider.bio = bio
            if cat_obj:
                provider.category = cat_obj
            if provider.statut != Provider.Status.VALID:
                if photo_portrait_url:
                    provider.photo_portrait_url = photo_portrait_url
                if cni_url:
                    provider.cni_url = cni_url
                if cni_recto_url:
                    provider.cni_recto_url = cni_recto_url
                if cni_verso_url:
                    provider.cni_verso_url = cni_verso_url
                if selfie_url:
                    provider.selfie_url = selfie_url
                if video_intro_url:
                    provider.video_intro_url = video_intro_url
            if provider.statut == Provider.Status.REFUSED:
                provider.statut = Provider.Status.PENDING
                provider.refusal_reason = ""
            provider.save()
        else:
            provider = Provider.objects.create(
                user_id=user_id,
                nom=nom,
                specialite=specialite,
                ville=ville,
                statut=Provider.Status.PENDING,
                years_experience=years_exp,
                bio=bio,
                photo_portrait_url=photo_portrait_url,
                cni_url=cni_url,
                cni_recto_url=cni_recto_url,
                cni_verso_url=cni_verso_url,
                selfie_url=selfie_url,
                video_intro_url=video_intro_url,
                category=cat_obj,
            )
        prof = UserProfile.objects.filter(user_id=user_id).first()
        if prof and phone_e164:
            prof.phone_e164 = phone_e164
            prof.save(update_fields=["phone_e164"])
    else:
        provider = Provider.objects.create(
            nom=nom,
            specialite=specialite,
            ville=ville,
            statut=Provider.Status.PENDING,
            years_experience=years_exp,
            bio=bio,
            photo_portrait_url=photo_portrait_url,
            cni_url=cni_url,
            cni_recto_url=cni_recto_url,
            cni_verso_url=cni_verso_url,
            selfie_url=selfie_url,
            video_intro_url=video_intro_url,
            category=cat_obj,
        )

    # ── Moteur KYC automatique ────────────────────────────────────────────────
    # On utilise les b64 bruts du payload (avant conversion en fichier disque)
    # pour alimenter le moteur sans re-lire le fichier sauvegardé.
    _cni_recto_b64  = payload.get("cni_recto_b64") or payload.get("cni_b64") or ""
    _cni_verso_b64  = payload.get("cni_verso_b64") or ""
    _selfie_b64     = payload.get("selfie_b64") or ""
    _cni_number     = str(payload.get("cni_number") or "").strip()

    if _cni_recto_b64 or _selfie_b64:
        try:
            import hashlib as _hashlib
            import base64 as _b64mod

            def _sha256_b64(s: str) -> str:
                raw = s.split(",", 1)[-1].strip()
                try:
                    return _hashlib.sha256(_b64mod.b64decode(raw)).hexdigest()
                except Exception:
                    return _hashlib.sha256(s.encode()).hexdigest()

            from .kyc_engine import run_kyc_verification
            verification = run_kyc_verification(
                cni_number=_cni_number or "NON_FOURNI",
                cni_recto_b64=_cni_recto_b64,
                cni_verso_b64=_cni_verso_b64,
                selfie_b64=_selfie_b64,
                hash_recto=_sha256_b64(_cni_recto_b64) if _cni_recto_b64 else "",
                hash_verso=_sha256_b64(_cni_verso_b64) if _cni_verso_b64 else "",
                hash_selfie=_sha256_b64(_selfie_b64) if _selfie_b64 else "",
            )
            provider.auto_check_score  = verification.score
            provider.auto_check_result = verification.to_dict()
            provider.auto_check_at     = timezone.now()

            if verification.auto_decision == "rejected":
                blocking_reasons = [
                    c.detail for c in verification.checks
                    if c.is_blocking and not c.passed
                ]
                provider.statut = Provider.Status.REFUSED
                provider.refusal_reason = (
                    " | ".join(blocking_reasons)
                    or "Vérification automatique échouée (score insuffisant)."
                )
                provider.save(update_fields=[
                    "auto_check_score", "auto_check_result", "auto_check_at",
                    "statut", "refusal_reason",
                ])
                # Notifier le prestataire du rejet automatique
                if user_id:
                    from .push_dispatch import _schedule as _push_schedule
                    _push_schedule(
                        [user_id],
                        "Dossier KYC refusé",
                        f"Votre dossier n'a pas passé la vérification automatique. "
                        f"Motif : {provider.refusal_reason[:200]}",
                    )
            else:
                provider.save(update_fields=[
                    "auto_check_score", "auto_check_result", "auto_check_at",
                ])
                score_label = f"score auto : {verification.score}/100"
                Notification.objects.create(
                    title=f"Nouveau prestataire en attente: {provider.nom} ({score_label})"
                )
        except Exception as _kyc_err:
            import logging as _log
            _log.getLogger(__name__).error(
                f"KYC engine error for provider {provider.id}: {_kyc_err}"
            )
            Notification.objects.create(
                title=f"Nouveau prestataire en attente: {provider.nom}"
            )
    else:
        Notification.objects.create(title=f"Nouveau prestataire en attente: {provider.nom}")

    return JsonResponse(
        {
            "ok": True,
            "provider_id": int(provider.id),
            "status": provider.statut,
            "kyc_score": provider.auto_check_score,
            "linked_user": bool(user_id),
            "email_hint": email[:80] if email else "",
        },
        status=201,
    )


@require_GET
@require_api_auth(["prestataire", "admin"])
def api_prestataire_requests(request):
    _bootstrap_data()
    status = request.GET.get("status")
    uid = request.api_user_id
    prov = _prestataire_provider_for_user(uid)

    queryset = Reservation.objects.all()
    if prov:
        queryset = queryset.filter(
            Q(prestataire_user_id=uid)
            | Q(prestataire=prov.nom)
            | Q(assigned_provider_id=prov.id)
        )
    if status:
        queryset = queryset.filter(statut=status)
    # Filtre optionnel par référence (récupération fiable d'une résa précise,
    # ex. écran « En attente de paiement » — évite le faux 404 dû à la pagination).
    ref_filter = request.GET.get("reference")
    if ref_filter:
        queryset = queryset.filter(reference=ref_filter)
    # Tri récent d'abord pour que les dernières demandes soient toujours visibles.
    queryset = queryset.order_by("-id")

    # Pré-fetch des réservations déjà notées par le prestataire (évite N+1) →
    # permet à l'app de masquer « Évaluer le client » une fois la note posée.
    from .models import ClientRating as _ClientRating

    _rated_ids = set(
        _ClientRating.objects.filter(reservation__in=queryset[:100]).values_list(
            "reservation_id", flat=True
        )
    )
    data = []
    for item in queryset[:100]:
        prov_obj = item.assigned_provider
        ravg = (
            round(float(prov_obj.average_rating), 1)
            if prov_obj and prov_obj.rating_count
            else 4.7
        )
        client_text = (
            item.description_probleme or item.client_message or ""
        ).strip()
        client_photos = [
            str(p).strip()
            for p in (item.preuve_photos or item.photos_probleme or [])
            if str(p).strip()
        ]
        # Privacy : tant que le prestataire n'a pas accepté la demande, on
        # cache la rue, le repère et on dégrade lat/lon à ~1 km (2 décimales).
        # Le quartier/ville/pays restent visibles pour qu'il puisse décider.
        # On révèle l'adresse EXACTE dès que la demande est ACCEPTÉE (devis
        # accepté ou au-delà) : le prestataire doit pouvoir s'y rendre. Avant
        # l'acceptation, on masque (rue/repère cachés, lat/lon dégradés ~1 km)
        # pour la vie privée du client.
        _ACCEPTED_STATUSES = {
            "DEVIS_ACCEPTE",
            "Confirmee",
            "INTERVENTION_EN_COURS",
            "En attente client",
            "Terminee",
            "DONE",
        }
        # L'adresse exacte se débloque aussi dès que la caution de visite est
        # réglée (le presta doit pouvoir s'y rendre pour le diagnostic).
        accepted = item.statut in _ACCEPTED_STATUSES or bool(item.caution_payee)
        approx = bool(item.address_is_approximate) and not accepted
        if approx:
            street_out = ""
            repere_out = ""
            label_out = (
                ", ".join(
                    p for p in [item.address_quartier, item.address_ville] if p
                )
                or item.address_quartier
                or item.address_ville
                or "Zone approximative"
            )
            lat_out = round(item.latitude, 2) if item.latitude is not None else None
            lon_out = round(item.longitude, 2) if item.longitude is not None else None
        else:
            street_out = item.address_street or ""
            repere_out = item.address_repere or ""
            label_out = item.address_label or "—"
            lat_out = item.latitude
            lon_out = item.longitude

        # Motif du dernier devis refusé par le client (affiché au presta).
        _last_refused = (
            Devis.objects.filter(reservation=item, statut=Devis.Statut.REFUSE)
            .order_by("-id")
            .first()
        )
        _refus_motif = (_last_refused.refus_motif if _last_refused else "") or ""

        data.append(
            {
                "id": item.id,
                "reference": item.reference,
                "client": item.client,
                "devis_refus_motif": _refus_motif,
                "service": item.title or "Intervention domiciliaire",
                "date": item.location_captured_at.strftime("%d %b %Y")
                if item.location_captured_at
                else "—",
                "hour": item.location_captured_at.strftime("%H:%M")
                if item.location_captured_at
                else "—",
                "address": label_out,
                # Adresse structurée — affichage pro côté prestataire avec une
                # icône par champ (rue / quartier / ville / pays / repère).
                "address_street": street_out,
                "address_quartier": item.address_quartier or "",
                "address_ville": item.address_ville or "",
                "address_pays": item.address_pays or "",
                "address_repere": repere_out,
                "address_lat": lat_out,
                "address_lon": lon_out,
                "address_is_approximate": approx,
                # Distance réservation ↔ prestataire (km) : permet au presta de
                # juger le trajet AVANT d'accepter, sans dévoiler l'adresse exacte.
                "distance_km": _provider_distance_km(
                    item.latitude, item.longitude, prov
                ),
                # Réponses du client aux questions dynamiques de la catégorie.
                "reponses_exigences": item.reponses_exigences or {},
                # Caution de visite de diagnostic (Phase 3).
                "caution_montant": float(item.caution_montant or 0),
                "caution_motif": item.caution_motif or "",
                "caution_payee": bool(item.caution_payee),
                "visite_effectuee": bool(item.visite_effectuee),
                "description": (
                    client_text or f"Detail de la demande {item.reference}"
                )[:500],
                "client_message": client_text,
                "client_photos": client_photos,
                "disponibilites_client": item.disponibilites_client or "",
                "is_urgent": item.is_urgent,
                "urgence_surcharge_pct": item.urgence_surcharge_pct or 0,
                "amount": float(item.montant) if item.montant else 0,
                "status": item.statut,
                "payment_type": item.payment_type,
                "mobile_money_operator": item.mobile_money_operator or "",
                "cash_flow_status": item.cash_flow_status,
                # Acompte versé par le client ? Permet de griser le bouton
                # « Démarrer » tant que l'acompte n'est pas reçu.
                "acompte_valide": bool(item.acompte_valide),
                # Date prévue choisie par le client (créneau). Sert à afficher
                # « Disponible dans X jours » et à n'autoriser « Démarrer » que le
                # jour J.
                "scheduled_date": (
                    item.scheduled_date.isoformat()
                    if item.scheduled_date
                    else None
                ),
                "rating": ravg,
                "client_rated": item.id in _rated_ids,
                "prix_propose": float(item.prix_propose) if item.prix_propose else None,
                # Chrono de la prestation : début (Démarrer) + fin (Terminé).
                # Permet d'afficher la durée — preuve horodatée côté presta/client.
                "intervention_started_at": item.intervention_started_at.isoformat()
                if item.intervention_started_at
                else None,
                "prestation_terminee_at": item.prestation_terminee_at.isoformat()
                if item.prestation_terminee_at
                else None,
                "bookingId": item.id,
            }
        )
    return JsonResponse({"items": data})


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["prestataire", "admin"])
def api_prestataire_location_update(request):
    """Met à jour la position GPS ACTUELLE du prestataire connecté.

    Appelé par l'app (LocationReporter) au démarrage et à chaque retour en
    foreground → la position "suit" le prestataire quand il se déplace, au lieu
    de rester figée sur un point d'inscription. Diffuse aussi le changement aux
    clients (temps réel) pour que la carte reflète la nouvelle position.
    """
    prov = _prestataire_provider_for_user(request.api_user_id)
    if not prov:
        return JsonResponse({"error": "provider_not_found"}, status=404)
    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    try:
        lat = float(payload.get("latitude"))
        lon = float(payload.get("longitude"))
    except (TypeError, ValueError):
        return JsonResponse({"error": "invalid_coordinates"}, status=400)
    # Bornes plausibles (évite d'enregistrer des coordonnées aberrantes).
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        return JsonResponse({"error": "coordinates_out_of_range"}, status=400)
    # Défense en profondeur : BABIFIX opère en Côte d'Ivoire. On REFUSE toute
    # position hors CIV (ex. GPS d'émulateur à Shanghai) — sinon la position du
    # prestataire serait écrasée par une localisation étrangère. On ignore
    # silencieusement (ok=True) pour ne pas faire échouer l'app.
    if not (4.0 <= lat <= 11.0 and -9.0 <= lon <= -2.0):
        return JsonResponse({"ok": True, "ignored": "out_of_country"})

    fields = ["latitude", "longitude"]
    prov.latitude = lat
    prov.longitude = lon
    ville = str(payload.get("ville", "") or "").strip()[:80]
    if ville:
        prov.ville = ville
        fields.append("ville")
    prov.save(update_fields=fields)

    # Temps réel : informer les clients que la position a changé (best-effort).
    try:
        from . import realtime
        realtime.broadcast_client_event(
            "provider.location_changed",
            {"provider_id": prov.id, "latitude": lat, "longitude": lon},
        )
    except Exception:
        pass

    return JsonResponse({"ok": True, "latitude": lat, "longitude": lon})


def _saved_address_json(a):
    return {
        "id": a.id,
        "label": a.label,
        "latitude": a.latitude,
        "longitude": a.longitude,
        "address_label": a.address_label,
        "address_repere": a.address_repere,
        "is_default": a.is_default,
    }


@csrf_exempt
@require_http_methods(["GET", "POST", "PATCH", "DELETE"])
@require_api_auth(["client", "admin"])
def api_client_saved_addresses(request, addr_id=None):
    """Carnet d'adresses du client.

    GET    /api/client/addresses              → liste
    POST   /api/client/addresses              → créer {label, latitude, longitude, ...}
    PATCH  /api/client/addresses/<id>         → définir par défaut / renommer
    DELETE /api/client/addresses/<id>         → supprimer
    """
    from .models import ClientSavedAddress

    uid = int(request.api_user_id)

    if request.method == "GET":
        items = ClientSavedAddress.objects.filter(user_id=uid)
        return JsonResponse({"addresses": [_saved_address_json(a) for a in items]})

    if request.method == "DELETE":
        if not addr_id:
            return JsonResponse({"error": "id_required"}, status=400)
        ClientSavedAddress.objects.filter(id=addr_id, user_id=uid).delete()
        return JsonResponse({"ok": True})

    if request.method == "PATCH":
        if not addr_id:
            return JsonResponse({"error": "id_required"}, status=400)
        addr = ClientSavedAddress.objects.filter(id=addr_id, user_id=uid).first()
        if not addr:
            return JsonResponse({"error": "not_found"}, status=404)
        try:
            payload = json.loads(request.body.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            return JsonResponse({"error": "invalid_json"}, status=400)
        fields = []
        if "label" in payload:
            new_label = str(payload.get("label") or "").strip()[:60]
            if new_label:
                addr.label = new_label
                fields.append("label")
        if payload.get("is_default") is True:
            ClientSavedAddress.objects.filter(user_id=uid, is_default=True).update(
                is_default=False
            )
            addr.is_default = True
            fields.append("is_default")
        if fields:
            addr.save(update_fields=fields)
        return JsonResponse({"ok": True, "address": _saved_address_json(addr)})

    # POST — créer / mettre à jour
    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    label = str(payload.get("label", "") or "").strip()[:60]
    if not label:
        return JsonResponse({"error": "label_required"}, status=400)
    try:
        lat = float(payload.get("latitude"))
        lon = float(payload.get("longitude"))
    except (TypeError, ValueError):
        return JsonResponse({"error": "invalid_coordinates"}, status=400)
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        return JsonResponse({"error": "coordinates_out_of_range"}, status=400)

    is_default = bool(payload.get("is_default", False))
    if is_default:
        # Une seule adresse par défaut à la fois.
        ClientSavedAddress.objects.filter(user_id=uid, is_default=True).update(
            is_default=False
        )
    addr = ClientSavedAddress.objects.create(
        user_id=uid,
        label=label,
        latitude=lat,
        longitude=lon,
        address_label=str(payload.get("address_label", "") or "")[:255],
        address_repere=str(payload.get("address_repere", "") or "")[:300],
        is_default=is_default,
    )
    return JsonResponse({"ok": True, "address": _saved_address_json(addr)}, status=201)


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["prestataire", "admin"])
def api_prestataire_decide_request(request, reference):
    _bootstrap_data()
    reservation = Reservation.objects.filter(reference=reference).first()
    if not reservation:
        return JsonResponse({"error": "not_found"}, status=404)
    uid = request.api_user_id
    prov = _prestataire_provider_for_user(uid)
    if (
        prov
        and reservation.assigned_provider_id
        and reservation.assigned_provider_id != prov.id
    ):
        if reservation.prestataire_user_id and reservation.prestataire_user_id != uid:
            return JsonResponse({"error": "forbidden"}, status=403)
    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    decision = str(payload.get("decision", "")).strip().lower()
    current_status = normalize_reservation_status(reservation.statut)
    new_status = None
    if decision == "accept":
        if current_status == Reservation.Status.PENDING:
            new_status = Reservation.Status.CONFIRMED
        else:
            new_status = Reservation.Status.DEVIS_EN_COURS
    elif decision == "refuse":
        new_status = Reservation.Status.CANCELLED
        reservation.motif_refus_demande = str(payload.get("motif", "") or "")[:500]
    else:
        return JsonResponse({"error": "invalid_decision"}, status=400)

    # Validation transition de statut
    is_valid, allowed = validate_reservation_transition(reservation.statut, new_status)
    if not is_valid:
        return JsonResponse(
            {
                "error": "invalid_transition",
                "current": reservation.statut,
                "allowed": allowed,
            },
            status=400,
        )

    reservation.statut = normalize_reservation_status(new_status)
    update_fields = ["statut", "motif_refus_demande"]
    # Privacy : à l'acceptation, l'adresse fine est révélée au prestataire
    # qui prend la demande (rue + repère + lat/lon précise).
    if decision == "accept" and reservation.address_is_approximate:
        reservation.address_is_approximate = False
        update_fields.append("address_is_approximate")
    reservation.save(update_fields=update_fields)
    return JsonResponse({"ok": True, "status": reservation.statut})


@require_GET
@require_api_auth(["prestataire", "admin"])
def api_prestataire_ratings(request):
    """Avis reçus par le prestataire connecté (avec commentaires et photos)."""
    _bootstrap_data()
    prov = _prestataire_provider_for_user(request.api_user_id)
    if not prov:
        return JsonResponse({"error": "no_provider"}, status=404)
    ratings = (
        Rating.objects.filter(provider=prov)
        .select_related("client", "reservation")
        .order_by("-created_at")[:60]
    )
    items = []
    for r in ratings:
        client_name = r.client.get_full_name() or r.client.username if r.client else "—"
        items.append(
            {
                "id": r.id,
                "note": r.note,
                "commentaire": r.commentaire,
                "photo_attachments": r.photo_attachments or [],
                "client": client_name,
                "service": r.reservation.title if r.reservation else "",
                "reference": r.reservation.reference if r.reservation else "",
                "date": r.created_at.strftime("%d/%m/%Y") if r.created_at else "",
            }
        )
    return JsonResponse(
        {
            "items": items,
            "average_rating": float(prov.average_rating or 0),
            "rating_count": prov.rating_count or 0,
        }
    )


# ── Vérification disponibilité prestataire ───────────────────────────────────
@require_GET
@require_api_auth(["client"])
def api_client_check_provider_availability(request):
    """Vérifie si un prestataire est disponible à une date/heure donnée."""
    provider_id = request.GET.get("provider_id")
    date_str = request.GET.get("date")
    time_str = request.GET.get("time")

    if not provider_id or not date_str:
        return JsonResponse({"error": "provider_id and date required"}, status=400)

    try:
        prov = Provider.objects.filter(
            id=int(provider_id), statut=Provider.Status.VALID
        ).first()
    except (ValueError, TypeError):
        return JsonResponse({"error": "invalid_provider_id"}, status=400)

    if not prov:
        return JsonResponse({"error": "provider_not_found"}, status=404)

    if not prov.disponible:
        return JsonResponse(
            {
                "available": False,
                "reason": "prestataire_indisponible",
                "message": "Ce prestataire n'est pas disponible actuellement.",
            }
        )

    from datetime import date, time as dt_time

    try:
        check_date = date.fromisoformat(date_str)
    except ValueError:
        return JsonResponse({"error": "invalid_date_format"}, status=400)

    unavail = PrestataireUnavailability.objects.filter(
        provider=prov,
        date_debut__lte=check_date,
        date_fin__gte=check_date,
    ).exists()

    if unavail:
        return JsonResponse(
            {
                "available": False,
                "reason": "conge",
                "message": "Ce prestataire est en congés cette journée.",
            }
        )

    slots = PrestataireAvailabilitySlot.objects.filter(
        provider=prov,
        jour_semaine=check_date.weekday(),
        actif=True,
    )

    if not slots.exists():
        return JsonResponse(
            {
                "available": False,
                "reason": "pas_creneau",
                "message": "Ce prestataire ne travaille pas ce jour.",
                "available_days": list(
                    PrestataireAvailabilitySlot.objects.filter(
                        provider=prov,
                        actif=True,
                    )
                    .values_list("jour_semaine", flat=True)
                    .distinct()
                ),
            }
        )

    if time_str:
        try:
            time_str_clean = time_str.replace(":", ".")
            check_time = dt_time.fromisoformat(time_str_clean)
            check_time_minutes = check_time.hour * 60 + check_time.minute

            for slot in slots:
                debut_minutes = slot.heure_debut.hour * 60 + slot.heure_debut.minute
                fin_minutes = slot.heure_fin.hour * 60 + slot.heure_fin.minute

                if debut_minutes <= check_time_minutes <= fin_minutes:
                    return JsonResponse(
                        {
                            "available": True,
                            "provider": {
                                "id": prov.id,
                                "nom": prov.nom,
                                "specialite": prov.specialite,
                            },
                        }
                    )

            return JsonResponse(
                {
                    "available": False,
                    "reason": "hors_creneau",
                    "message": "Ce prestataire n'est pas disponible à cette heure.",
                    "creneaux": [
                        {"debut": str(s.heure_debut), "fin": str(s.heure_fin)}
                        for s in slots
                    ],
                }
            )
        except ValueError:
            pass

    # Avis de conflit NON BLOQUANT (#9) : si le presta a déjà une intervention
    # prévue ce jour-là, on le signale et on propose les prochains jours libres.
    # Le client reste libre de réserver quand même (optionnel).
    _TERMINAL = ("Terminee", "Annulee", "CANCELLED")
    busy_count = (
        Reservation.objects.filter(assigned_provider=prov, scheduled_date=check_date)
        .exclude(statut__in=_TERMINAL)
        .count()
    )
    suggested = []
    notice = ""
    if busy_count > 0:
        from datetime import timedelta as _td
        work_days = set(
            PrestataireAvailabilitySlot.objects.filter(provider=prov, actif=True)
            .values_list("jour_semaine", flat=True)
        )
        d = check_date
        for _ in range(45):
            d = d + _td(days=1)
            if work_days and d.weekday() not in work_days:
                continue
            if PrestataireUnavailability.objects.filter(
                provider=prov, date_debut__lte=d, date_fin__gte=d
            ).exists():
                continue
            taken = (
                Reservation.objects.filter(assigned_provider=prov, scheduled_date=d)
                .exclude(statut__in=_TERMINAL)
                .exists()
            )
            if taken:
                continue
            suggested.append(d.isoformat())
            if len(suggested) >= 3:
                break
        notice = (
            "Ce prestataire a déjà une intervention prévue ce jour-là. "
            "Vous pouvez réserver quand même, ou choisir un autre jour."
        )

    return JsonResponse(
        {
            "available": True,
            "busy_that_day": busy_count > 0,
            "notice": notice,
            "suggested_dates": suggested,
            "provider": {
                "id": prov.id,
                "nom": prov.nom,
                "specialite": prov.specialite,
            },
            "creneaux": [
                {
                    "jour": s.get_jour_semaine_display(),
                    "debut": str(s.heure_debut),
                    "fin": str(s.heure_fin),
                }
                for s in slots
            ],
        }
    )


def _safe_decimal(value) -> Decimal:
    """Convertit une valeur Payment.montant/commission en Decimal."""
    if value is None:
        return Decimal("0")
    try:
        if isinstance(value, (int, float)):
            return Decimal(str(value))
        if hasattr(value, "__float__"):
            return Decimal(str(float(value)))
        raw = str(value).replace("€", "").replace("FCFA", "").replace("XOF", "").strip()
        return Decimal(raw or "0")
    except (ValueError, TypeError):
        return Decimal("0")


@require_GET
@require_api_auth(["prestataire", "admin"])
def api_prestataire_earnings(request):
    _bootstrap_data()
    prov = _prestataire_provider_for_user(request.api_user_id)
    name = prov.nom if prov else ""

    # Détection route /monthly/ — retourne le graphique 6 mois
    if request.path.rstrip("/").endswith("/monthly"):
        return _earnings_monthly_chart(name)

    period = request.GET.get("period", "month")
    qs = Payment.objects.filter(prestataire=name) if name else Payment.objects.none()

    # Filtrage par période via created_at
    from datetime import timedelta
    now = timezone.now()
    if period == "day":
        since = now - timedelta(days=1)
    elif period == "week":
        since = now - timedelta(weeks=1)
    elif period == "all":
        since = None
    else:  # month (default)
        since = now - timedelta(days=30)
    if since is not None:
        qs = qs.filter(created_at__gte=since)

    gross_total = Decimal("0")
    commission_total = Decimal("0")
    net_total = Decimal("0")

    transactions = []
    for x in qs.order_by("-pk")[:20]:
        m = _safe_decimal(x.montant)
        c = _safe_decimal(x.commission)
        net = m - c
        gross_total += m
        commission_total += c
        net_total += net
        transactions.append(
            {
                "client": x.client,
                "service": "Prestation",
                "gross": str(m.quantize(Decimal("1"))),
                "commission": str(c.quantize(Decimal("1"))),
                "net": str(net.quantize(Decimal("1"))),
                "status": x.etat,
            }
        )

    return JsonResponse({
        "summary": {
            "gross": int(gross_total),
            "commission": int(commission_total),
            "net": int(net_total),
            "count": len(transactions),
        },
        "transactions": transactions,
    })


def _earnings_monthly_chart(prestataire_nom: str) -> JsonResponse:
    """Retourne les 6 derniers mois de revenus pour le graphique du dashboard."""
    from datetime import timedelta
    now = timezone.now()
    months = []
    for i in range(5, -1, -1):
        month_start = now.replace(day=1) - timedelta(days=30 * i)
        month_start = month_start.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        if i > 0:
            month_end = month_start + timedelta(days=32)
            month_end = month_end.replace(day=1) - timedelta(seconds=1)
        else:
            month_end = now
        label = _month_label(month_start)
        total = Decimal("0")
        if prestataire_nom:
            qs = Payment.objects.filter(
                prestataire=prestataire_nom,
                created_at__gte=month_start,
                created_at__lte=month_end,
            )
            for p in qs:
                total += _safe_decimal(p.montant) - _safe_decimal(p.commission)
        months.append({
            "label": label,
            "total_amount": int(total),
        })
    return JsonResponse({"months": months})


def _month_label(dt) -> str:
    """Retourne 'Janv.', 'Févr.', … selon la locale."""
    mois = [
        "", "Janv.", "Févr.", "Mars", "Avr.", "Mai", "Juin",
        "Juill.", "Août", "Sept.", "Oct.", "Nov.", "Déc.",
    ]
    return mois[dt.month]


@require_GET
@require_api_auth(["admin"])
def api_admin_financial_summary(request):
    """Résumé financier global pour l'admin."""
    _bootstrap_data()
    from django.db.models import Sum
    from decimal import Decimal

    all_payments = Payment.objects.all()
    all_reservations = Reservation.objects.all()

    total_montant = all_payments.aggregate(Sum("montant"))["montant__sum"] or Decimal(
        "0"
    )
    total_commission = Decimal("0")
    for p in all_payments:
        if p.commission:
            try:
                total_commission += Decimal(str(p.commission).replace(",", "."))
            except:
                pass

    reservations_by_status = {}
    for status_choice in Reservation.Status.choices:
        status_val = status_choice[0]
        count = all_reservations.filter(statut=status_val).count()
        reservations_by_status[status_val] = count

    pending_payments = all_reservations.filter(
        statut__in=[Reservation.Status.DONE, Reservation.Status.INTERVENTION_EN_COURS],
        cash_flow_status__in=[
            Reservation.CashFlowStatus.PENDING_PRESTATAIRE,
            Reservation.CashFlowStatus.PENDING_ADMIN,
        ],
    ).count()

    return JsonResponse(
        {
            "total_revenu": float(total_montant),
            "total_commission": float(total_commission),
            "total_net": float(total_montant - total_commission),
            "reservations_count": all_reservations.count(),
            "payments_count": all_payments.count(),
            "pending_payments": pending_payments,
            "reservations_by_status": reservations_by_status,
        }
    )


@require_GET
@require_api_auth(["client", "prestataire", "admin"])
def api_messages_unread_total(request):
    """Nombre total de messages non lus (badge apps client / prestataire)."""
    uid = int(request.api_user_id)
    return JsonResponse({"total": _unread_messages_total_for_user(uid)})


def _commission_rate_pct_for(provider) -> int:
    """Taux de commission EFFECTIF en % (entier) pour un prestataire, en
    déléguant à la même source que le devis (_get_effective_commission_rate)."""
    try:
        from .services.wallet_service import _get_effective_commission_rate
        frac = _get_effective_commission_rate(provider)
        return int((Decimal(str(frac)) * Decimal("100")).quantize(Decimal("1")))
    except Exception:
        return 18


@require_GET
@require_api_auth(["prestataire", "admin"])
def api_prestataire_me(request):
    """Profil prestataire + stats reelles (sans donnees de demo)."""
    _bootstrap_data()
    uid = request.api_user_id
    prov = Provider.objects.select_related("category").filter(user_id=uid).first()
    if not prov:
        return JsonResponse(
            {"error": "no_provider_profile", "provider": None}, status=404
        )
    qs = Reservation.objects.filter(
        Q(prestataire_user_id=uid)
        | Q(assigned_provider_id=prov.id)
        | Q(prestataire=prov.nom)
    )
    from datetime import timedelta
    month_ago = timezone.now() - timedelta(days=30)
    monthly_payments = Payment.objects.filter(
        prestataire=prov.nom, created_at__gte=month_ago
    )
    # « Gains » = ce que le prestataire touche réellement = NET (brut − commission
    # BABIFIX). Doit correspondre EXACTEMENT au net de l'écran « Mes gains » et au
    # wallet (sinon les chiffres ne coïncident pas).
    pay_sum = Decimal("0")
    for pay in monthly_payments:
        pay_sum += _safe_decimal(pay.montant) - _safe_decimal(pay.commission)
    cat = prov.category
    return JsonResponse(
        {
            "provider": {
                "id": int(prov.id),
                "nom": prov.nom,
                "specialite": prov.specialite,
                "ville": prov.ville,
                "statut": prov.statut,
                "refusal_reason": prov.refusal_reason,
                "photo_url": _safe_photo_url(
                    prov.photo_portrait_url or prov.cni_url or "", request
                ),
                "bio": prov.bio,
                "average_rating": float(prov.average_rating or 0),
                "rating_count": int(prov.rating_count or 0),
                "fiabilite_score": int(getattr(prov, "fiabilite_score", 100) or 100),
                "tarif_horaire": float(prov.tarif_horaire)
                if prov.tarif_horaire is not None
                else None,
                "disponible": prov.disponible,
                "category_nom": (cat.nom if cat else "") or "",
                "category_id": int(cat.id) if cat else None,
                "category_icone_url": (cat.icone_url or "").strip() if cat else "",
                "years_experience": int(prov.years_experience or 0),
                # Champs lus par l'app prestataire au boot pour décider de la
                # route (contrat obligatoire / dashboard / KYC / premium).
                "contrat_signe": bool(prov.contrat_accepte_at),
                "a_numero_retrait": bool((prov.wallet_phone or "").strip()),
                "contrat_accepte_at": prov.contrat_accepte_at.isoformat()
                    if prov.contrat_accepte_at else None,
                "contrat_version": prov.contrat_version or "",
                "kyc_status": prov.kyc_status or "not_submitted",
                "premium_tier": prov.premium_tier or "standard",
                "is_premium": bool(prov.is_premium),
                "is_premium_annual": bool(getattr(prov, "is_premium_annual", False)),
                # Taux de commission EFFECTIF (réduction premium incluse) — le
                # même que celui réellement appliqué au devis → l'éditeur de
                # devis l'affiche au lieu d'un 18% figé.
                "commission_rate_effective": _commission_rate_pct_for(prov),
            },
            "stats": {
                "reservations_total": qs.count(),
                "reservations_actives": qs.filter(
                    statut__in=[
                        "DEMANDE_ENVOYEE",
                        "DEVIS_EN_COURS",
                        "DEVIS_ENVOYE",
                        "DEVIS_ACCEPTE",
                        "En attente",
                        "Confirmee",
                        "En cours",
                    ]
                ).count(),
                "prestations_terminees": qs.filter(statut="Terminee").count(),
                "chiffre_paiements": int(pay_sum),
                "nb_paiements": monthly_payments.count(),
            },
            "unread_chat_messages": _unread_messages_total_for_user(uid),
        }
    )


@csrf_exempt
@require_http_methods(["POST"])
def api_auth_login(request):
    from .throttle import check_rate_limit, rate_limited_response

    if check_rate_limit(request, "login", max_requests=10, window=60):
        return rate_limited_response()
    _bootstrap_data()
    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    username = str(payload.get("username", "")).strip()
    email = str(payload.get("email", "")).strip()
    password = str(payload.get("password", "")).strip()
    if not password:
        return JsonResponse({"error": "username_password_required"}, status=400)

    # Login par email ou username
    login_field = email or username
    if not login_field:
        return JsonResponse({"error": "username_password_required"}, status=400)

    # On accepte comme identifiant : l'email, le nom d'utilisateur, OU le nom
    # complet choisi à l'inscription (Provider.nom / prénom+nom). On rassemble
    # tous les comptes candidats puis on valide le mot de passe sur chacun.
    ident = (email or username).strip()
    ident_l = ident.lower()
    candidates: list = []

    def _add(qs):
        for u in qs:
            if u and all(u.pk != c.pk for c in candidates):
                candidates.append(u)

    if email:
        _add(User.objects.filter(email__iexact=email))
    if username:
        _add(User.objects.filter(username__iexact=username))
        if "@" in username:
            _add(User.objects.filter(email__iexact=username))
    # Par email complet quand l'identifiant en est un (champ générique côté app).
    if "@" in ident:
        _add(User.objects.filter(email__iexact=ident))
    # Par nom complet : prestataires (Provider.nom) puis prénom + nom.
    if ident:
        try:
            prov_uids = [
                uid
                for uid in Provider.objects.filter(nom__iexact=ident)
                .values_list("user_id", flat=True)
                if uid
            ]
            if prov_uids:
                _add(User.objects.filter(id__in=prov_uids))
        except Exception:
            pass
        parts = ident.split()
        if len(parts) >= 2:
            _add(
                User.objects.filter(
                    first_name__iexact=parts[0],
                    last_name__iexact=" ".join(parts[1:]),
                )
            )
        # Nom d'utilisateur exact insensible à la casse (repli).
        _add(User.objects.filter(username__iexact=ident_l))

    # Anti-timing-attack : on hash TOUJOURS un mot de passe — même si user inconnu —
    # pour que la durée de la réponse ne révèle pas l'existence d'un compte.
    from django.contrib.auth.hashers import check_password as _hasher_check
    _DUMMY_HASH = (
        "argon2$argon2id$v=19$m=102400,t=2,p=8$"
        "ZHVtbXktc2FsdC1iYWJpZml4$KW5fF3nq3a3WZ9o/9c8Z4w"
    )
    user = None
    for c in candidates:
        if c.check_password(password):
            user = c
            break
    if not user:
        _hasher_check(password, _DUMMY_HASH)
        return JsonResponse({"error": "invalid_credentials"}, status=401)
    if not user.is_active:
        return JsonResponse({"error": "account_disabled"}, status=403)
    profile = UserProfile.objects.filter(user=user, active=True).first()
    if not profile:
        return JsonResponse({"error": "user_role_not_found"}, status=403)
    token = create_token(user.id, profile.role)
    refresh = create_refresh_token(user.id, profile.role)
    # Mémoriser la dernière connexion (utile pour audits / detection compromise).
    try:
        from django.utils import timezone
        User.objects.filter(pk=user.pk).update(last_login=timezone.now())
    except Exception:
        pass
    return JsonResponse(
        {
            "token": token,
            "access": token,
            "refresh": refresh,
            "role": profile.role,
            "username": user.username,
        }
    )


@csrf_exempt
@require_http_methods(["POST"])
def api_auth_register(request):
    from .throttle import check_rate_limit, rate_limited_response

    if check_rate_limit(request, "register", max_requests=5, window=300):
        return rate_limited_response()
    _bootstrap_data()
    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    email = str(payload.get("email", "")).strip().lower()
    email_prefix = email.split("@", 1)[0] if "@" in email else email
    username = str(payload.get("username", "")).strip() or email_prefix
    password = str(payload.get("password", "")).strip()
    role = str(payload.get("role", "")).strip()
    phone_e164 = str(payload.get("phone_e164", "") or "")[:24]
    country_code = str(payload.get("country_code", "CI") or "CI")[:5]
    if role not in {
        UserProfile.Role.CLIENT,
        UserProfile.Role.PRESTATAIRE,
        UserProfile.Role.ADMIN,
    }:
        return JsonResponse({"error": "invalid_role"}, status=400)

    # Username obligatoire, utiliser email prefix si non fourni
    if not username and email:
        username = email_prefix
    if not username:
        return JsonResponse({"error": "username_required"}, status=400)
    if not password:
        return JsonResponse({"error": "password_required"}, status=400)
    if len(password) < 6:
        return JsonResponse({"error": "password_too_short"}, status=400)
    if User.objects.filter(username=username).exists():
        return JsonResponse({"error": "username_exists"}, status=400)

    import secrets as _secrets

    # Nom complet choisi à l'inscription (stocké dans first_name pour persister
    # côté serveur — sinon le nom serait perdu à la reconnexion / réinstallation).
    full_name = str(payload.get("name") or payload.get("full_name") or "").strip()[:150]
    user = User.objects.create_user(
        username=username,
        password=password,
        email=email if email else None,
    )
    if full_name:
        user.first_name = full_name
        user.save(update_fields=["first_name"])
    email_token = _secrets.token_urlsafe(32)
    profile = UserProfile.objects.create(
        user=user,
        role=role,
        active=True,
        phone_e164=phone_e164,
        country_code=country_code,
        email_verify_token=email_token,
    )
    # Envoi email de vérification uniquement pour les prestataires.
    # NE DOIT JAMAIS faire échouer l'inscription : si le SMTP est indisponible
    # (ex. clés mail non configurées sur Render), on log et on continue.
    if user.email and role == UserProfile.Role.PRESTATAIRE:
        try:
            from .views_v2 import _send_verification_email

            _send_verification_email(user.email, email_token)
        except Exception as e:  # noqa: BLE001
            logger.warning(
                "Email de vérification non envoyé pour %s: %s", user.email, e
            )

    # Email de bienvenue — EN ARRIÈRE-PLAN (thread daemon). Sur Render, le SMTP
    # peut être lent/bloqué : un envoi synchrone faisait traîner la réponse
    # jusqu'à ce que l'app coupe (timeout 45 s) → CancelledError + inscription
    # qui « n'aboutit pas ». Le compte est déjà créé : l'email ne doit JAMAIS
    # bloquer ni faire échouer l'inscription.
    def _send_welcome_async(u, r):
        try:
            from .views_extra import email_welcome

            email_welcome(u, r)
        except Exception as _e:  # noqa: BLE001
            logger.warning("email_welcome échoué pour %s: %s", getattr(u, "email", "?"), _e)

    try:
        import threading

        threading.Thread(
            target=_send_welcome_async, args=(user, role), daemon=True
        ).start()
    except Exception:
        pass

    # Synchroniser le Client dans la table admin dès l'inscription
    if role == UserProfile.Role.CLIENT:
        try:
            client_email = user.email or username
            Client.objects.create(
                nom=full_name or username,
                email=client_email,
                ville=country_code,
                reservations=0,
                depense=Decimal("0"),
            )
        except Exception:
            pass  # Ne pas bloquer l'inscription si la synchro échoue

    token = create_token(user.id, role)
    refresh = create_refresh_token(user.id, role)
    return JsonResponse(
        {
            "token": token,
            "access": token,
            "refresh": refresh,
            "role": role,
            "username": user.username,
        },
        status=201,
    )


@csrf_exempt
@require_http_methods(["GET", "POST"])
@require_api_auth()
def api_auth_me(request):
    user = User.objects.filter(id=request.api_user_id).first()
    if not user:
        return JsonResponse({"error": "user_not_found"}, status=404)
    profile = UserProfile.objects.filter(user=user).first()

    # POST : mise à jour du numéro enregistré (réutilisé pour paiement/retraits).
    if request.method == "POST":
        try:
            payload = json.loads(request.body.decode("utf-8") or "{}")
        except (json.JSONDecodeError, TypeError):
            return JsonResponse({"error": "invalid_json"}, status=400)
        if not profile:
            profile = UserProfile.objects.create(
                user=user, role=request.api_role or "client", active=True
            )
        phone_e164 = str(payload.get("phone_e164") or payload.get("phone") or "").strip()[:24]
        country = str(payload.get("country_code") or "").strip()[:5]
        # Nom complet + email modifiables depuis l'écran « Mon profil ».
        name = str(payload.get("name") or payload.get("full_name") or "").strip()[:150]
        new_email = str(payload.get("email") or "").strip()[:254]
        user_fields = []
        if name and name != user.first_name:
            user.first_name = name
            user_fields.append("first_name")
        if new_email and new_email != (user.email or ""):
            user.email = new_email
            user_fields.append("email")
        if user_fields:
            user.save(update_fields=user_fields)
        fields = []
        if phone_e164:
            profile.phone_e164 = phone_e164
            fields.append("phone_e164")
        if country:
            profile.country_code = country
            fields.append("country_code")
        # Photo de profil (avatar) — base64 data:image → fichier (Cloudinary).
        # Ne JAMAIS faire échouer la requête à cause de l'avatar : on isole.
        photo = str(
            payload.get("photo_b64") or payload.get("avatar_b64") or ""
        )
        if photo.startswith("data:image/"):
            try:
                saved = _decode_and_save_media(photo, "avatars", "avatar")
                if saved:
                    profile.avatar_url = saved
                    fields.append("avatar_url")
                else:
                    logger.warning("Avatar non enregistré (données invalides) user=%s", user.id)
            except Exception as exc:  # noqa: BLE001
                logger.warning("Echec enregistrement avatar user=%s: %s", user.id, exc)
        if fields:
            profile.save(update_fields=fields)

    full_name = (user.first_name or "").strip() or (
        f"{user.first_name} {user.last_name}".strip()
    )
    return JsonResponse(
        {
            "id": int(user.id),
            "username": user.username,
            "name": full_name,
            "email": user.email or "",
            "role": request.api_role,
            "phone_e164": profile.phone_e164 if profile else "",
            "country_code": profile.country_code if profile else "CI",
            "avatar_url": _safe_photo_url(
                (profile.avatar_url if profile else "") or "", request
            ),
        }
    )


@csrf_exempt
@require_http_methods(["POST", "DELETE"])
@require_api_auth(["client", "prestataire"])
def api_auth_fcm_token(request):
    """Enregistre ou supprime un jeton FCM pour l’utilisateur JWT courant."""
    uid = request.api_user_id
    if request.method == "DELETE":
        try:
            payload = json.loads(request.body.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            payload = {}
        token = (payload.get("token") or "").strip()
        if not token:
            return JsonResponse({"error": "token_required"}, status=400)
        DeviceToken.objects.filter(user_id=uid, token=token).delete()
        return JsonResponse({"ok": True})
    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    token = (payload.get("token") or "").strip()
    if not token or len(token) > 512:
        return JsonResponse({"error": "token_required"}, status=400)
    platform = (payload.get("platform") or "android").strip().lower()[:16]
    if platform not in {"android", "ios", "web"}:
        platform = DeviceToken.Platform.ANDROID
    # App d'origine du jeton : 'client' (BABIFIX) ou 'pro' (BABIFIX PRO).
    app = (payload.get("app") or "client").strip().lower()
    if app not in {"client", "pro"}:
        app = "client"
    DeviceToken.objects.update_or_create(
        token=token,
        defaults={"user_id": uid, "platform": platform, "app": app},
    )
    return JsonResponse({"ok": True})


@csrf_exempt
@require_http_methods(["POST"])
def api_auth_google(request):
    from django.conf import settings

    # En production, Google Client ID doit être configuré
    if not settings.GOOGLE_CLIENT_ID:
        return JsonResponse(
            {
                "error": "google_auth_not_configured",
                "message": " GOOGLE_CLIENT_ID non configuré sur le serveur. Veuillez configurer GOOGLE_CLIENT_ID dans les variables d'environnement.",
            },
            status=500,
        )
    return JsonResponse(
        {
            "error": "google_auth_not_configured",
            "message": "Configurez Firebase (google-services.json, GoogleService-Info.plist) et verifiez idToken cote serveur.",
        },
        status=501,
    )


@csrf_exempt
@require_http_methods(["POST"])
def api_auth_apple(request):
    from django.conf import settings

    # En production, Apple config doit être complète
    if not (
        settings.APPLE_BUNDLE_ID
        and settings.APPLE_TEAM_ID
        and settings.APPLE_KEY_ID
        and settings.APPLE_PRIVATE_KEY
    ):
        return JsonResponse(
            {
                "error": "apple_auth_not_configured",
                "message": "Apple Sign-In non configuré sur le serveur. Completez APPLE_BUNDLE_ID, APPLE_TEAM_ID, APPLE_KEY_ID et APPLE_PRIVATE_KEY.",
            },
            status=500,
        )
    return JsonResponse(
        {
            "error": "apple_auth_not_configured",
            "message": "Activez Sign in with Apple sur developer.apple.com et validez le token cote serveur.",
        },
        status=501,
    )


@require_GET
@require_api_auth(["prestataire", "admin"])
def api_prestataire_conversations(request):
    uid = request.api_user_id
    convs = (
        Conversation.objects.filter(prestataire_id=uid)
        .select_related("client", "reservation")
        .order_by("-updated_at")  # plus récentes d'abord
    )
    data = []
    for c in convs:
        last = c.messages.order_by("-created_at").first()
        # Masquer les conversations vides (sans aucun échange).
        if last is None:
            continue
        preview = (last.body[:120] if last.body else "") or (
            "[Photo]" if last.image else ""
        )
        res = c.reservation
        data.append(
            {
                "id": int(c.id),
                "client_username": c.client.username,
                "client_id": int(c.client_id),
                "last_message": preview,
                "updated_at": c.updated_at.isoformat(),
                # Alias lu par l'app (affichage de l'horodatage).
                "last_date": c.updated_at.isoformat(),
                "unread_count": _conversation_unread_for_user(c, uid),
                "reservation_reference": res.reference if res else "",
                "conversation_title": (
                    f"{res.title or res.reference} — {res.reference}"
                    if res
                    else c.client.username
                ),
            }
        )
    return JsonResponse({"conversations": data})


def _get_reservation_for_ref(reference):
    return (
        Reservation.objects.filter(reference=reference)
        .select_related("assigned_provider")
        .first()
    )


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client", "admin"])
def api_client_rate_reservation(request, reference):
    """Notation 1–5 après prestation terminée (diagramme d'activité notation)."""
    _bootstrap_data()
    res = _get_reservation_for_ref(reference)
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)
    uid = request.api_user_id
    if res.client_user_id != uid and request.api_role != "admin":
        return JsonResponse({"error": "forbidden"}, status=403)
    _done = (
        res.statut in ("Terminee", "En attente client")
        or bool(getattr(res, "prestation_terminee_at", None))
        or bool(getattr(res, "client_confirme_prestation_at", None))
    )
    if not _done:
        return JsonResponse({"error": "reservation_not_completed"}, status=400)
    if Rating.objects.filter(reservation=res).exists():
        return JsonResponse({"error": "already_rated"}, status=400)
    prov = res.assigned_provider
    if not prov:
        return JsonResponse({"error": "no_provider"}, status=400)
    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    try:
        note = int(payload.get("note", 0))
    except (TypeError, ValueError):
        note = 0
    if note < 1 or note > 5:
        return JsonResponse({"error": "note_1_to_5"}, status=400)
    commentaire = str(payload.get("commentaire", "") or "")[:2000]
    photo_rows: list[str] = []
    raw_avis = payload.get("photo_attachments") or payload.get("avis_photos") or []
    if isinstance(raw_avis, list):
        for entry in raw_avis[:5]:
            s = str(entry).strip()
            if not s.startswith("data:image/"):
                continue
            if len(s) > 600_000:
                s = s[:600_000]
            photo_rows.append(s)
    Rating.objects.create(
        reservation=res,
        client_id=uid,
        provider=prov,
        note=note,
        commentaire=commentaire,
        photo_attachments=photo_rows,
    )
    recalc_provider_rating_stats(prov)
    return JsonResponse(
        {
            "ok": True,
            "average_rating": prov.average_rating,
            "rating_count": prov.rating_count,
        }
    )


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client", "admin"])
def api_client_declare_cash(request, reference):
    """Client déclare avoir payé en espèces (séquence paiement espèces)."""
    _bootstrap_data()
    res = _get_reservation_for_ref(reference)
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)
    uid = request.api_user_id
    if res.client_user_id != uid and request.api_role != "admin":
        return JsonResponse({"error": "forbidden"}, status=403)
    if res.payment_type != Reservation.PaymentType.ESPECES:
        return JsonResponse({"error": "not_cash_reservation"}, status=400)
    # Ordre STRICT : on ne peut déclarer le paiement espèces qu'APRÈS que le
    # prestataire a terminé ET que le client a confirmé la prestation (statut
    # « Terminee » + confirmation). Sinon le cash se bouclerait dès l'acompte,
    # avant même que le presta démarre (« logique bizarre »).
    if res.statut != "Terminee" or not res.client_confirme_prestation_at:
        return JsonResponse(
            {
                "error": "prestation_not_confirmed",
                "message": "Confirmez d'abord la prestation terminée avant de régler en espèces.",
            },
            status=400,
        )
    if res.cash_client_declared_at:
        return JsonResponse({"error": "already_declared"}, status=400)
    with transaction.atomic():
        res.cash_client_declared_at = timezone.now()
        res.cash_flow_status = Reservation.CashFlowStatus.PENDING_PRESTATAIRE
        res.save(
            update_fields=[
                "cash_client_declared_at",
                "cash_flow_status",
            ]
        )
        Notification.objects.create(title=f"Client a declare paiement especes: {reference}")
    return JsonResponse({"ok": True, "cash_flow_status": res.cash_flow_status})


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["prestataire", "admin"])
def api_prestataire_confirm_cash(request, reference):
    _bootstrap_data()
    res = _get_reservation_for_ref(reference)
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)
    uid = request.api_user_id
    prov = _prestataire_provider_for_user(uid)
    if request.api_role != "admin":
        if not prov or res.assigned_provider_id != prov.id:
            if res.prestataire_user_id != uid:
                return JsonResponse({"error": "forbidden"}, status=403)
    # HANDSHAKE : le client déclare « j'ai remis l'argent » D'ABORD, puis le
    # prestataire confirme « j'ai reçu » → c'est seulement là que la commission
    # est reconnue et les fonds libérés. Le presta attend donc la déclaration.
    if not res.cash_client_declared_at:
        return JsonResponse(
            {
                "error": "client_not_declared",
                "message": "En attente : le client doit d'abord confirmer avoir remis l'argent.",
            },
            status=400,
        )
    if res.cash_prestataire_confirmed_at:
        return JsonResponse({"error": "already_confirmed"}, status=400)
    # Les deux parties ont confirmé (client a remis, presta a reçu) → auto-
    # validation sans admin.
    with transaction.atomic():
        res.cash_prestataire_confirmed_at = timezone.now()
        res.cash_admin_validated_at = timezone.now()
        res.cash_flow_status = Reservation.CashFlowStatus.VALIDATED
        res.solde_valide = True
        ref_pay = f"PAY-CASH-{res.reference}"
        # Le presta a reçu en CASH le NET (= total − commission). La commission a
        # déjà été encaissée en ligne via l'acompte espèces → ici commission = 0
        # pour ne PAS la compter deux fois. montant = net réellement reçu.
        commission_val = res.commission or Decimal("0")
        net_cash = res.montant_restant if res.montant_restant else (
            (res.montant or Decimal("0")) - commission_val
        )
        payment, created = Payment.objects.get_or_create(
            reference=ref_pay,
            defaults={
                "client": res.client,
                "prestataire": res.prestataire,
                "montant": net_cash,
                "commission": Decimal("0"),
                "etat": Payment.State.COMPLETE,
                "reservation": res,
                "type_paiement": Payment.TypePaiement.ESPECES,
                "valide_par_admin": True,
            },
        )
        if not created:
            payment.etat = Payment.State.COMPLETE
            payment.valide_par_admin = True
            payment.save(update_fields=["etat", "valide_par_admin"])
        res.save(update_fields=[
            "cash_prestataire_confirmed_at", "cash_admin_validated_at",
            "cash_flow_status", "solde_valide", "commission",
        ])
        # Enregistrer la commission en PlatformRevenue et créditer
        # le surplus éventuel dans le wallet du prestataire
        try:
            from .services.escrow_service import EscrowService
            EscrowService.release_funds(res)
        except Exception as exc:
            logger.exception("release_funds auto-cash %s: %s", res.reference, exc)
    # Reçu détaillé au prestataire : preuve + traçabilité (montant total,
    # commission BABIFIX déjà prélevée en ligne, net reçu en espèces).
    _schedule(
        [res.prestataire_user_id] if res.prestataire_user_id else [],
        "BABIFIX — Paiement espèces confirmé",
        f"Net reçu {net_cash:.0f} FCFA · commission BABIFIX {commission_val:.0f} FCFA "
        f"(prélevée en ligne) · total {(res.montant or 0):.0f} FCFA — {res.reference}.",
        {
            "type": "cash.confirmed",
            "reference": res.reference,
            "gross": str(res.montant or 0),
            "commission": str(commission_val),
            "net": str(net_cash),
        },
    )
    return JsonResponse({
        "ok": True,
        "cash_flow_status": res.cash_flow_status,
        "gross": str(res.montant or 0),
        "commission": str(commission_val),
        "net": str(net_cash),
    })


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["prestataire", "admin"])
def api_prestataire_reservation_status(request, reference):
    """Met à jour le statut métier (En cours / Terminee) — aligné UML statuts réservation."""
    _bootstrap_data()
    res = _get_reservation_for_ref(reference)
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)
    uid = request.api_user_id
    prov = _prestataire_provider_for_user(uid)
    if request.api_role != "admin":
        if not prov or (
            res.assigned_provider_id and res.assigned_provider_id != prov.id
        ):
            if res.prestataire_user_id != uid:
                return JsonResponse({"error": "forbidden"}, status=403)
    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    new_status = normalize_reservation_status(payload.get("status", ""))

    current = normalize_reservation_status(res.statut)
    is_valid, allowed = validate_reservation_transition(current, new_status)
    if not is_valid:
        return JsonResponse(
            {
                "error": "invalid_transition",
                "current": current,
                "allowed": allowed,
            },
            status=400,
        )

    update_fields = ["statut"]
    res.statut = new_status
    if new_status == "En attente client":
        res.prestation_terminee_at = timezone.now()
        update_fields.append("prestation_terminee_at")
        _schedule(
            [res.client_user_id],
            "BABIFIX — Prestation terminée",
            f"Confirmez la prestation {res.reference} avant paiement.",
            {"type": "prestation.terminee", "reference": res.reference},
        )
    res.save(update_fields=update_fields)
    return JsonResponse({"ok": True, "status": res.statut})


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["admin"])
def api_admin_validate_cash(request, reference):
    _bootstrap_data()
    res = _get_reservation_for_ref(reference)
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)
    if res.cash_flow_status != Reservation.CashFlowStatus.PENDING_ADMIN:
        return JsonResponse({"error": "not_pending_admin"}, status=400)
    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    action = str(payload.get("action", "validate")).strip().lower()
    if action == "validate":
        # DÉSACTIVÉ : l'admin ne valide plus le cash. La validation est
        # automatique via la poignée de main (client « j'ai remis » →
        # prestataire « j'ai reçu ») qui libère les fonds sans intervention
        # admin. On bloque cette voie pour éviter tout double comptage.
        return JsonResponse(
            {
                "error": "deprecated",
                "message": "La validation du cash est automatique (poignée de main "
                           "client/prestataire). L'admin n'a pas à valider.",
            },
            status=410,
        )
    if action == "refuse":
        motif = str(payload.get("motif", "") or "")[:500]
        res.cash_flow_status = Reservation.CashFlowStatus.REFUSED
        res.cash_refusal_motif = motif
        res.save(update_fields=["cash_flow_status", "cash_refusal_motif"])
        return JsonResponse({"ok": True, "cash_flow_status": res.cash_flow_status})
    return JsonResponse({"error": "invalid_action"}, status=400)


@require_GET
def api_public_payment_methods(request):
    """5 moyens de paiement (Espèces + 4 Mobile Money CI) avec logos static."""
    rows = [
        {"id": mid, "label": label, "logo_url": _static_absolute(request, path)}
        for mid, path, label in PAYMENT_METHOD_STATIC
    ]
    return JsonResponse({"payment_methods": rows})


@require_GET
def api_public_categories(request):
    """Categories pour vitrine / apps (UML Categorie).

    - Sans paramètre (CLIENT) : seules les catégories ayant au moins 1
      prestataire validé sont renvoyées (pas de catégorie vide côté client).
    - Avec ?all=1 (PRESTATAIRE, à l'inscription) : TOUTES les catégories,
      car c'est là qu'il choisit son métier.
    """
    _bootstrap_data()
    include_all = request.GET.get("all") == "1"
    cache_key = (
        "babifix:public:categories:all" if include_all
        else "babifix:public:categories:client"
    )
    # Redis cache (5 min) pour eviter de requeter la DB a chaque appel
    try:
        from django.core.cache import cache
        cached = cache.get(cache_key)
        if cached is not None:
            return JsonResponse({"categories": cached})
    except Exception:
        pass  # Pas de Redis = degrade gracieusement
    rows = []
    cats = (
        Category.objects.filter(actif=True, is_deleted=False)
        .annotate(
            providers_count=Count(
                "providers",
                filter=Q(providers__statut=Provider.Status.VALID, providers__is_deleted=False),
            )
        )
        .order_by("ordre_affichage", "nom")
    )
    for cat in cats:
        # Côté client : on masque les catégories sans aucun prestataire validé.
        if not include_all and cat.providers_count == 0:
            continue
        icon_url = ""
        if (cat.icone_url or "").strip().startswith("http"):
            icon_url = cat.icone_url.strip()
        elif (cat.icone_slug or "").strip():
            slug = cat.icone_slug.strip()
            relative = f"/{settings.STATIC_URL.strip('/')}/category-icons/{slug}.svg"
            try:
                icon_url = request.build_absolute_uri(relative)
            except Exception:
                icon_url = relative
        rows.append({
            "id": cat.id,
            "nom": cat.nom,
            "icone_slug": cat.icone_slug or "",
            "icone_url": icon_url,
            "icon_emoji": "",
            "services": cat.services,
            "reservations": cat.reservations,
            "providers_count": cat.providers_count,
            # Devis intelligent (Phase 2) : profil + questions dynamiques.
            # STANDARD + liste vide = formulaire actuel (rétrocompatible).
            "profil_devis": cat.profil_devis or "STANDARD",
            "template_exigences": cat.template_exigences or [],
        })
    # Mise en cache Redis (5 min TTL)
    try:
        from django.core.cache import cache
        cache.set(cache_key, rows, 300)
    except Exception:
        pass
    return JsonResponse(
        {
            "categories": rows,
            "icon_library": [{"slug": s, "label": lb} for s, lb in CATEGORY_ICON_SLUGS],
        }
    )


@require_GET
def api_provider_requirements(request, provider_id):
    """Profil de devis + questions dynamiques de la catégorie d'un prestataire.

    L'app client appelle cet endpoint avec l'id du prestataire choisi (qu'elle
    possède déjà) pour savoir quelles questions afficher au moment de la demande.
    Réponse par défaut (prestataire/catégorie introuvable, ou catégorie STANDARD
    non configurée) : profil STANDARD + liste vide → l'app garde son formulaire
    actuel (rétrocompatible).
    """
    prov = (
        Provider.objects.select_related("category")
        .filter(pk=provider_id)
        .first()
    )
    cat = prov.category if prov else None
    if not cat:
        return JsonResponse({
            "profil_devis": "STANDARD",
            "template_exigences": [],
        })
    return JsonResponse({
        "profil_devis": cat.profil_devis or "STANDARD",
        "template_exigences": cat.template_exigences or [],
        "category_id": cat.id,
        "category_nom": cat.nom,
    })


def _payment_complete_exists(res: Reservation) -> bool:
    return Payment.objects.filter(reservation=res, etat=Payment.State.COMPLETE).exists()


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client", "admin"])
def api_client_confirm_prestation(request, reference):
    """Client confirme la prestation terminée par le prestataire (avant paiement)."""
    _bootstrap_data()
    res = _get_reservation_for_ref(reference)
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)
    uid = int(request.api_user_id)
    if res.client_user_id != uid and request.api_role != "admin":
        return JsonResponse({"error": "forbidden"}, status=403)
    if res.statut not in ("En attente client", "Terminee"):
        return JsonResponse(
            {"error": "invalid_state", "detail": "Statut attendu: En attente client ou Terminee"},
            status=400,
        )
    if res.dispute_ouverte:
        return JsonResponse({"error": "dispute_open"}, status=400)
    res.statut = "Terminee"
    res.client_confirme_prestation_at = timezone.now()
    res.save(update_fields=["statut", "client_confirme_prestation_at"])
    # Programme de fidélité : créditer les points au client
    points_gagnes = 0
    try:
        from .services.fidelite_service import FideliteService
        points_gagnes = FideliteService.award_for_reservation(res)
    except Exception:
        logger.exception("fidélité: échec attribution points %s", res.reference)
    _schedule(
        [res.prestataire_user_id],
        "BABIFIX — Client a confirmé",
        f"Réservation {res.reference} — vous pouvez demander le paiement.",
        {"type": "client.confirmed", "reference": res.reference},
    )
    # Reçu FINAL par e-mail à la confirmation (fin du parcours). On envoie le
    # reçu du dernier paiement complété (le PDF récapitule le total de la
    # prestation). Silencieux en cas d'échec — ne bloque jamais la confirmation.
    try:
        from .geniuspay import _send_receipt_email
        last_pay = (
            Payment.objects.filter(reservation=res, etat=Payment.State.COMPLETE)
            .order_by("-id")
            .first()
        )
        if last_pay:
            _send_receipt_email(last_pay)
    except Exception:
        logger.warning("Reçu final: échec envoi pour %s", res.reference, exc_info=True)
    return JsonResponse({"ok": True, "status": res.statut, "points_fidelite_gagnes": points_gagnes})


from django.db import transaction

@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client", "admin"])
def api_client_pay_post_prestation(request, reference):
    """Enregistre le paiement après prestation (MVP : statut + historique, pas agrégateur)."""
    _bootstrap_data()
    res = _get_reservation_for_ref(reference)
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)
    uid = int(request.api_user_id)
    if res.client_user_id != uid and request.api_role != "admin":
        return JsonResponse({"error": "forbidden"}, status=403)
    if res.statut != "Terminee" or not res.client_confirme_prestation_at:
        return JsonResponse({"error": "invalid_state"}, status=400)
    if res.dispute_ouverte:
        return JsonResponse({"error": "dispute_open"}, status=400)
    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    mid = str(payload.get("payment_method_id", "") or "").strip().upper()
    valid_ids = {x[0] for x in PAYMENT_METHOD_STATIC}
    if mid not in valid_ids:
        return JsonResponse(
            {"error": "invalid_payment_method", "allowed": list(valid_ids)}, status=400
        )
    note = str(payload.get("message", "") or "")[:2000]
    ref_pay = f"PAY-{res.reference}-{int(timezone.now().timestamp())}"
    commission = res.commission or Decimal("0")
    # Utiliser le payment_type déjà choisi par le client lors de la création
    # (ne pas le redemander ici)
    if res.payment_type == Reservation.PaymentType.ESPECES:
        tp = Payment.TypePaiement.ESPECES
    else:
        tp = Payment.TypePaiement.MOBILE_MONEY
    idem_key = payload.get("idempotency_key", "")
    try:
        with transaction.atomic():
            res.payment_client_note = note
            # Ne pas ré-écrire payment_type — il a été choisi à la création
            # Seulement mettre à jour l'opérateur si Mobile Money
            if res.payment_type != Reservation.PaymentType.ESPECES:
                op_map = {
                    "ORANGE_MONEY": Reservation.MobileMoneyOperator.ORANGE_MONEY,
                    "MTN_MOMO": Reservation.MobileMoneyOperator.MTN_MOMO,
                    "WAVE": Reservation.MobileMoneyOperator.WAVE,
                    "MOOV": Reservation.MobileMoneyOperator.MOOV,
                }
                op = op_map.get(str(payload.get("mobile_money_operator", "")).strip().upper())
                if op:
                    res.mobile_money_operator = op
            res.save(update_fields=["payment_client_note", "mobile_money_operator"])
            Payment.objects.create(
                reference=ref_pay,
                client=res.client,
                prestataire=res.prestataire,
                montant=res.montant,
                commission=str(commission),
                etat=Payment.State.COMPLETE,
                reservation=res,
                type_paiement=tp,
                valide_par_admin=False,
                idempotency_key=idem_key,
            )
    except Exception as e:
        return JsonResponse({"error": "transaction_failed", "detail": str(e)}, status=500)
    _schedule(
        [res.prestataire_user_id],
        "BABIFIX - Paiement enregistre",
        f"{res.reference} - {mid}",
        {"type": "payment.recorded", "reference": res.reference},
    )
    return JsonResponse({"ok": True, "payment_reference": ref_pay})


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client"])
def api_client_pay_deposit(request, reference):
    """Le client paie l'acompte après acceptation du devis.

    L'acompte est TOUJOURS payé par mobile money (c'est la commission BABIFIX).
    Le pourcentage dépend du mode global choisi :
      - MOBILE_MONEY global → 30% d'acompte, solde 70% aussi en mobile money
      - ESPECES global      → 18% d'acompte, solde 82% en cash au prestataire
    """
    from decimal import Decimal
    res = Reservation.objects.filter(reference=reference).first()
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)
    uid = int(request.api_user_id)
    if res.client_user_id != uid:
        return JsonResponse({"error": "forbidden"}, status=403)
    if res.statut != Reservation.Status.DEVIS_ACCEPTE:
        return JsonResponse({"error": "invalide", "detail": "Le devis doit d'abord être accepté."}, status=400)
    if res.acompte_valide:
        return JsonResponse({"error": "deja_paye", "detail": "L'acompte a déjà été payé."}, status=409)

    montant_total = res.montant or Decimal("0")

    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        payload = {}

    # Opérateur mobile money pour le paiement de l'acompte (obligatoire)
    operator = str(payload.get("mobile_money_operator", "") or "").strip().upper()
    valid_operators = {"ORANGE_MONEY", "MTN_MOMO", "WAVE", "MOOV"}
    if operator not in valid_operators:
        return JsonResponse(
            {"error": "operateur_invalide", "allowed": list(valid_operators)},
            status=400,
        )

    # Mode global (espèces ou mobile money) — déduit de la réservation
    overall = res.payment_type
    if not overall:
        overall = str(payload.get("overall_type", "")).strip().upper()
    if overall not in ("ESPECES", "MOBILE_MONEY"):
        return JsonResponse(
            {"error": "type_global_invalide", "detail": "Précisez overall_type : ESPECES ou MOBILE_MONEY."},
            status=400,
        )

    # Acompte = part payée en ligne. Pour ESPECES, l'acompte EST la commission
    # BABIFIX : il doit donc suivre le taux EFFECTIF du prestataire (réductions
    # premium / abonnement incluses), jamais un 18% figé — sinon un prestataire
    # premium serait surfacturé. Pour MOBILE_MONEY, l'acompte reste 30% (séquestre).
    if overall == "ESPECES":
        pct = Decimal("0.18")
        prov_for_rate = res.assigned_provider
        if prov_for_rate is not None:
            try:
                from .services.wallet_service import _get_effective_commission_rate
                pct = _get_effective_commission_rate(prov_for_rate)
            except Exception:
                pct = Decimal("0.18")
    else:
        pct = Decimal("0.30")
    acompte = (montant_total * pct).quantize(Decimal("1"))
    if acompte < Decimal("500"):
        acompte = Decimal("500")
    if acompte > montant_total:
        acompte = montant_total
    restant = montant_total - acompte

    with transaction.atomic():
        res.montant_verse = acompte
        res.montant_restant = restant
        res.acompte_valide = True
        # N'écrase pas payment_type — il a été choisi à la création
        res.mobile_money_operator = operator
        res.save(update_fields=[
            "montant_verse", "montant_restant", "acompte_valide",
            "mobile_money_operator",
        ])
        # Pour ESPECES, l'acompte payé en ligne EST la commission BABIFIX : on
        # l'enregistre comme telle (commission = montant ⇒ net 0 pour le presta).
        # Ainsi les gains du presta ne comptent PAS l'acompte (pas de double
        # comptage), et la commission est comptée une seule fois.
        # Pour MOBILE_MONEY, l'acompte fait partie du séquestre destiné au
        # prestataire → commission = 0.
        acompte_commission = acompte if overall == "ESPECES" else Decimal("0")
        Payment.objects.create(
            reference=f"ACOMPTE-{res.reference}-{int(timezone.now().timestamp())}",
            client=res.client,
            prestataire=res.prestataire,
            montant=acompte,
            commission=acompte_commission,
            etat=Payment.State.COMPLETE,
            reservation=res,
            type_paiement=Payment.TypePaiement.MOBILE_MONEY,
            valide_par_admin=False,
        )

    _schedule(
        [res.prestataire_user_id],
        "BABIFIX — Acompte reçu",
        f"L'acompte de {acompte} FCFA a été payé pour {res.reference}. Vous pouvez démarrer.",
        {"type": "deposit.paid", "reference": res.reference},
    )
    return JsonResponse({
        "ok": True,
        "acompte": str(acompte),
        "restant": str(restant),
        "overall_type": overall,
        "pct": str(pct),
    })


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client"])
def api_client_pay_caution(request, reference):
    """Le client règle la caution de visite de diagnostic.

    Suit le même modèle que l'acompte (enregistre un Payment + une commission
    de plateforme). La caution débloque l'adresse exacte et fait repartir la
    demande vers le devis. Elle sera déduite du prix final si le devis est
    accepté.
    """
    from decimal import Decimal
    res = Reservation.objects.filter(reference=reference).first()
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)
    if res.client_user_id != int(request.api_user_id):
        return JsonResponse({"error": "forbidden"}, status=403)
    if res.statut != Reservation.Status.VISITE_DIAGNOSTIC:
        return JsonResponse(
            {"error": "invalide", "detail": "Aucune visite en attente de caution."},
            status=400,
        )
    if res.caution_payee:
        return JsonResponse(
            {"error": "deja_paye", "detail": "La caution a déjà été réglée."},
            status=409,
        )
    montant = res.caution_montant or Decimal("0")
    if montant <= 0:
        return JsonResponse({"error": "caution_absente"}, status=400)

    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        payload = {}
    operator = str(payload.get("mobile_money_operator", "") or "").strip().upper()
    valid_operators = {"ORANGE_MONEY", "MTN_MOMO", "WAVE", "MOOV"}
    if operator not in valid_operators:
        return JsonResponse(
            {"error": "operateur_invalide", "allowed": list(valid_operators)},
            status=400,
        )

    from .models import PlatformRevenue, PlatformConfig
    # Commission de VISITE : 12 % (configurable) prélevés sur la caution. C'est
    # une commission DISTINCTE de celle du devis (18/13/8 %) — elle rémunère
    # spécifiquement la mise en relation et la visite-diagnostic. Le MONTANT de
    # la caution reste, lui, intégralement déduit du devis final (pas de surplus
    # pour le client) ; les 12 % sont le revenu BABIFIX sur cette étape.
    pct = Decimal(str(PlatformConfig.get_solo().caution_commission_pct)) / Decimal("100")
    caution_commission = (montant * pct).quantize(Decimal("1"))

    with transaction.atomic():
        res.caution_payee = True
        res.mobile_money_operator = operator
        # La caution réglée débloque l'adresse et relance le devis.
        res.statut = Reservation.Status.DEVIS_EN_COURS
        res.save(update_fields=["caution_payee", "mobile_money_operator", "statut"])
        pay = Payment.objects.create(
            reference=f"CAUTION-{res.reference}-{int(timezone.now().timestamp())}",
            client=res.client,
            prestataire=res.prestataire,
            montant=montant,
            commission=caution_commission,
            etat=Payment.State.COMPLETE,
            reservation=res,
            type_paiement=Payment.TypePaiement.MOBILE_MONEY,
            valide_par_admin=False,
        )
        PlatformRevenue.objects.create(
            amount_fcfa=caution_commission,
            source=PlatformRevenue.Source.COMMISSION,
            reference=res.reference,
            description=f"Commission visite (caution) {res.reference}",
            payment=pay,
        )

    _schedule(
        [res.prestataire_user_id] if res.prestataire_user_id else [],
        "Caution réglée",
        (
            f"La caution de {int(montant)} FCFA est payée pour {res.reference}. "
            "Vous pouvez organiser la visite puis envoyer le devis."
        ),
        {"type": "caution.paid", "reference": res.reference},
    )
    return JsonResponse({
        "ok": True,
        "caution": str(montant),
        "commission": str(caution_commission),
        "statut": res.statut,
    })


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client"])
def api_client_pay_remainder(request, reference):
    """Le client paie le solde restant par mobile money (uniquement si mode global MOBILE_MONEY).

    Si le mode global est ESPECES, le solde est payé en cash au prestataire (pas via cette API).
    """
    from decimal import Decimal
    res = Reservation.objects.filter(reference=reference).first()
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)
    uid = int(request.api_user_id)
    if res.client_user_id != uid:
        return JsonResponse({"error": "forbidden"}, status=403)
    if res.statut not in ("Terminee", "En attente client"):
        return JsonResponse({"error": "invalide", "detail": "Le prestataire doit d'abord terminer l'intervention."}, status=400)
    if not res.acompte_valide:
        return JsonResponse({"error": "acompte_requis", "detail": "L'acompte doit d'abord être payé."}, status=400)
    if res.solde_valide:
        return JsonResponse({"error": "deja_paye", "detail": "Le solde a déjà été payé."}, status=409)
    if res.payment_type != "MOBILE_MONEY":
        return JsonResponse(
            {"error": "pas_en_ligne", "detail": "Paiement en espèces — réglez le solde directement au prestataire."},
            status=400,
        )

    montant_restant = res.montant_restant or Decimal("0")
    if montant_restant <= Decimal("0"):
        return JsonResponse({"error": "rien_a_payer", "detail": "Aucun solde restant dû."}, status=400)

    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        payload = {}
    operator = str(payload.get("mobile_money_operator", "") or "").strip().upper()
    valid_operators = {"ORANGE_MONEY", "MTN_MOMO", "WAVE", "MOOV"}
    if operator not in valid_operators:
        return JsonResponse({"error": "operateur_invalide", "allowed": list(valid_operators)}, status=400)

    with transaction.atomic():
        res.montant_verse = (res.montant_verse or Decimal("0")) + montant_restant
        res.montant_restant = Decimal("0")
        res.solde_valide = True
        res.mobile_money_operator = operator
        res.save(update_fields=["montant_verse", "montant_restant", "solde_valide", "mobile_money_operator"])
        Payment.objects.create(
            reference=f"SOLDE-{res.reference}-{int(timezone.now().timestamp())}",
            client=res.client,
            prestataire=res.prestataire,
            montant=montant_restant,
            commission=Decimal("0"),
            etat=Payment.State.COMPLETE,
            reservation=res,
            type_paiement=Payment.TypePaiement.MOBILE_MONEY,
            valide_par_admin=False,
        )

    try:
        from .services.escrow_service import EscrowService
        EscrowService.release_funds(res)
    except Exception as e:
        logger.exception("release_funds %s: %s", res.reference, e)

    _schedule(
        [res.prestataire_user_id],
        "BABIFIX — Paiement final reçu",
        f"Le solde de {montant_restant} FCFA a été payé pour {res.reference}.",
        {"type": "remainder.paid", "reference": res.reference},
    )
    return JsonResponse({"ok": True, "montant": str(montant_restant), "solde_valide": True})


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client", "prestataire", "admin"])
def api_client_message_delete(request, message_id):
    """Suppression logique d’un message (auteur ou destinataire de la conversation)."""
    _bootstrap_data()
    try:
        mid = int(message_id)
    except ValueError:
        return JsonResponse({"error": "invalid_id"}, status=400)
    msg = Message.objects.filter(pk=mid).select_related("conversation").first()
    if not msg:
        return JsonResponse({"error": "not_found"}, status=404)
    uid = int(request.api_user_id)
    conv = msg.conversation
    if uid not in (conv.client_id, conv.prestataire_id) and request.api_role != "admin":
        return JsonResponse({"error": "forbidden"}, status=403)
    msg.deleted = True
    msg.save(update_fields=["deleted"])
    return JsonResponse({"ok": True})


# ── Gestionnaires d'erreurs HTTP ──────────────────────────────────────────────
def error_404(request, exception=None):
    return JsonResponse({"error": "not_found"}, status=404)


# ── Devis API ───────────────────────────────────────────────────────────────────


# Prestataire : accepter de faire un devis
@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["prestataire"])
def api_prestataire_accept_demande(request, reference):
    """Le prestataire accepte de préparer un devis pour cette demande."""
    _bootstrap_data()
    res = Reservation.objects.filter(reference=reference).first()
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)

    provider = Provider.objects.filter(user_id=request.api_user_id).first()
    if not provider:
        return JsonResponse({"error": "provider_not_found"}, status=403)

    if res.assigned_provider_id != provider.id:
        return JsonResponse({"error": "not_authorized"}, status=403)

    if res.statut != Reservation.Status.DEMANDE_ENVOYEE:
        return JsonResponse({"error": "invalid_state"}, status=400)

    res.statut = Reservation.Status.DEVIS_EN_COURS
    res.save(update_fields=["statut"])

    _schedule(
        [res.client_user_id] if res.client_user_id else [],
        "Demande acceptée",
        f"{provider.nom} va vous envoyer un devis détaillé.",
        {"type": "demande.accepted", "reference": res.reference},
    )

    return JsonResponse({"ok": True, "statut": res.statut})


# Prestataire : demander une VISITE de diagnostic (avec caution)
@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["prestataire"])
def api_prestataire_request_visit(request, reference):
    """Le prestataire demande une visite de diagnostic avec caution.

    Alternative au devis direct : quand une visite sur place est nécessaire
    pour chiffrer (gros chantier, accès, mesures), le presta fixe une caution
    (déductible du prix final). Le client la règle AVANT le déblocage de
    l'adresse exacte. Reste 100% optionnel : le devis direct fonctionne comme
    avant.
    """
    _bootstrap_data()
    from decimal import Decimal
    res = Reservation.objects.filter(reference=reference).first()
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)

    provider = Provider.objects.filter(user_id=request.api_user_id).first()
    if not provider:
        return JsonResponse({"error": "provider_not_found"}, status=403)

    if res.assigned_provider_id != provider.id:
        return JsonResponse({"error": "not_authorized"}, status=403)

    if res.statut not in (
        Reservation.Status.DEMANDE_ENVOYEE,
        Reservation.Status.DEVIS_EN_COURS,
    ):
        return JsonResponse({"error": "invalid_state"}, status=400)

    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)

    montant = parse_money_amount(payload.get("caution_montant", 0))
    motif = str(payload.get("caution_motif", "") or "")[:300]
    if montant <= 0:
        return JsonResponse(
            {"error": "caution_invalide", "detail": "Indiquez un montant de caution."},
            status=400,
        )
    # Garde-fou : caution de visite plafonnée à 5 000 FCFA (règle métier).
    if montant > Decimal("5000"):
        return JsonResponse(
            {
                "error": "caution_trop_elevee",
                "detail": "La caution de visite ne peut pas dépasser 5 000 FCFA.",
            },
            status=400,
        )

    res.caution_montant = montant
    res.caution_motif = motif
    res.caution_payee = False
    res.caution_deduite = False
    res.statut = Reservation.Status.VISITE_DIAGNOSTIC
    res.save(update_fields=[
        "caution_montant", "caution_motif", "caution_payee",
        "caution_deduite", "statut",
    ])

    _schedule(
        [res.client_user_id] if res.client_user_id else [],
        "Visite de diagnostic proposée",
        (
            f"{provider.nom} propose une visite pour évaluer votre demande "
            f"(caution {int(montant)} FCFA, déductible du devis)."
        ),
        {"type": "visit.requested", "reference": res.reference},
    )

    return JsonResponse({
        "ok": True,
        "statut": res.statut,
        "caution_montant": float(montant),
        "caution_motif": motif,
    })


# Annuler une demande de VISITE tant que la caution n'a pas été réglée.
# Accessible au prestataire (il se rétracte / modifie) ET au client (il refuse).
@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["prestataire", "client"])
def api_cancel_visit_request(request, reference):
    from decimal import Decimal
    _bootstrap_data()
    res = Reservation.objects.filter(reference=reference).first()
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)
    uid = int(request.api_user_id)
    is_client = res.client_user_id == uid
    prov = Provider.objects.filter(user_id=uid).first()
    is_presta = bool(prov and res.assigned_provider_id == prov.id)
    if not (is_client or is_presta):
        return JsonResponse({"error": "not_authorized"}, status=403)
    if res.caution_payee:
        return JsonResponse(
            {"error": "deja_paye",
             "detail": "La caution est déjà réglée : passez par un signalement/remboursement."},
            status=409,
        )
    if res.statut != Reservation.Status.VISITE_DIAGNOSTIC:
        return JsonResponse(
            {"error": "invalid_state", "detail": "Aucune demande de visite en attente."},
            status=400,
        )
    res.caution_montant = Decimal("0")
    res.caution_motif = ""
    res.caution_payee = False
    res.caution_deduite = False
    # Retour à l'état « en cours » : le presta peut envoyer un devis direct.
    res.statut = Reservation.Status.DEVIS_EN_COURS
    res.save(update_fields=[
        "caution_montant", "caution_motif", "caution_payee",
        "caution_deduite", "statut",
    ])
    who = "Le client" if is_client else "Le prestataire"
    target = ([res.prestataire_user_id] if is_client else
              ([res.client_user_id] if res.client_user_id else []))
    _schedule(
        [t for t in target if t],
        "Visite annulée",
        f"{who} a annulé la demande de visite pour {res.reference}.",
        {"type": "visit.cancelled", "reference": res.reference},
    )
    return JsonResponse({"ok": True, "statut": res.statut})


# Prestataire : marquer la visite de diagnostic comme effectuée
@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["prestataire"])
def api_prestataire_visite_done(request, reference):
    """Le prestataire déclare avoir effectué la visite de diagnostic.

    Détermine qui garde la caution en cas d'annulation : une fois la visite
    faite, le presta la conserve (compensation du déplacement).
    """
    res = Reservation.objects.filter(reference=reference).first()
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)
    provider = Provider.objects.filter(user_id=request.api_user_id).first()
    if not provider:
        return JsonResponse({"error": "provider_not_found"}, status=403)
    if res.assigned_provider_id != provider.id:
        return JsonResponse({"error": "not_authorized"}, status=403)
    if not res.caution_payee:
        return JsonResponse(
            {"error": "caution_non_payee", "detail": "La caution n'est pas encore réglée."},
            status=400,
        )
    if res.visite_effectuee:
        return JsonResponse({"ok": True, "visite_effectuee": True})

    from decimal import Decimal
    from .models import PlatformConfig, WalletTransaction

    # Caution acquise au prestataire : elle a été réglée par mobile, on lui
    # verse sa part = caution − commission de visite (12 %). BABIFIX garde les
    # 12 % (déjà comptabilisés en revenu à l'encaissement de la caution). Ce
    # crédit est distinct du règlement du devis (qui, lui, porte sur le RESTE au
    # complètement) → aucun double paiement. Le garde `visite_effectuee`
    # ci-dessus rend l'opération idempotente (une seule fois).
    caution = res.caution_montant or Decimal("0")
    part_presta = Decimal("0")
    with transaction.atomic():
        res.visite_effectuee = True
        res.visite_effectuee_at = timezone.now()
        res.save(update_fields=["visite_effectuee", "visite_effectuee_at"])

        if caution > 0:
            pct = Decimal(str(PlatformConfig.get_solo().caution_commission_pct)) / Decimal("100")
            caution_comm = (caution * pct).quantize(Decimal("1"))
            part_presta = caution - caution_comm
            if part_presta > 0:
                prov = Provider.objects.select_for_update().get(pk=provider.pk)
                prov.solde_fcfa = (prov.solde_fcfa or Decimal("0")) + part_presta
                prov.save(update_fields=["solde_fcfa"])
                WalletTransaction.objects.create(
                    provider=prov,
                    tx_type="credit",
                    amount_fcfa=part_presta,
                    reference=res.reference,
                    description=(
                        f"Caution de visite acquise — {res.reference} "
                        f"(net après commission visite {int(pct * 100)} %)"
                    ),
                    status="success",
                )

    # Notifie le presta du crédit (rafraîchit son solde en temps réel).
    if part_presta > 0:
        try:
            from asgiref.sync import async_to_sync
            from channels.layers import get_channel_layer
            channel_layer = get_channel_layer()
            async_to_sync(channel_layer.group_send)(
                f"prestataire_{provider.user_id}",
                {
                    "type": "prestataire_notify",
                    "event_type": "wallet.credited",
                    "payload": {
                        "net": float(part_presta),
                        "reference": res.reference,
                        "motif": "caution_visite",
                    },
                },
            )
        except Exception:
            pass

    _schedule(
        [res.client_user_id] if res.client_user_id else [],
        "Visite effectuée",
        f"{provider.nom} a effectué la visite. Vous recevrez le devis sous peu.",
        {"type": "visit.done", "reference": res.reference},
    )
    return JsonResponse({
        "ok": True,
        "visite_effectuee": True,
        "caution_versee_presta": float(part_presta),
    })


# Prestataire : refuser la demande
@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["prestataire"])
def api_prestataire_refuse_demande(request, reference):
    """Le prestataire refuse la demande avec un motif."""
    _bootstrap_data()
    res = Reservation.objects.filter(reference=reference).first()
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)

    provider = Provider.objects.filter(user_id=request.api_user_id).first()
    if not provider:
        return JsonResponse({"error": "provider_not_found"}, status=403)

    if res.assigned_provider_id != provider.id:
        return JsonResponse({"error": "not_authorized"}, status=403)

    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)

    motif = str(payload.get("motif", "") or "")[:500]

    res.statut = Reservation.Status.CANCELLED
    res.motif_refus_demande = motif
    res.save(update_fields=["statut", "motif_refus_demande"])

    _schedule(
        [res.client_user_id] if res.client_user_id else [],
        "Demande refusée",
        f"{provider.nom} a refusé votre demande. Motif: {motif}",
        {"type": "demande.refused", "reference": res.reference},
    )

    return JsonResponse({"ok": True, "statut": res.statut})


# Prestataire : démarrer l'intervention
@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["prestataire"])
def api_prestataire_demarrer_intervention(request, reference):
    """Le prestataire démarre l'intervention sur place."""
    _bootstrap_data()
    res = Reservation.objects.filter(reference=reference).first()
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)

    provider = Provider.objects.filter(user_id=request.api_user_id).first()
    if not provider:
        return JsonResponse({"error": "provider_not_found"}, status=403)

    if res.assigned_provider_id != provider.id:
        return JsonResponse({"error": "not_authorized"}, status=403)

    if not res.acompte_valide:
        return JsonResponse(
            {"error": "acompte_requis", "detail": "Le client n'a pas encore payé l'acompte."},
            status=400,
        )

    # On ne peut pas démarrer DEUX prestations en même temps : si une autre est
    # déjà INTERVENTION_EN_COURS pour ce prestataire, on refuse (message clair).
    other_active = (
        Reservation.objects.filter(
            assigned_provider_id=provider.id,
            statut=Reservation.Status.INTERVENTION_EN_COURS,
        )
        .exclude(pk=res.pk)
        .first()
    )
    if other_active:
        return JsonResponse(
            {
                "error": "another_in_progress",
                "message": (
                    "Vous avez déjà une prestation en cours "
                    f"({other_active.reference}). Terminez-la avant d'en "
                    "démarrer une autre."
                ),
                "reference": other_active.reference,
            },
            status=409,
        )

    # On ne peut pas démarrer AVANT le jour prévu de l'intervention.
    if res.scheduled_date and res.scheduled_date > timezone.localdate():
        return JsonResponse(
            {
                "error": "too_early",
                "message": (
                    "Cette prestation est prévue le "
                    f"{res.scheduled_date.strftime('%d/%m/%Y')}. Vous pourrez la "
                    "démarrer le jour même, pas avant."
                ),
                "scheduled_date": res.scheduled_date.isoformat(),
            },
            status=409,
        )

    # Validation transition de statut
    is_valid, allowed = validate_reservation_transition(
        res.statut, Reservation.Status.INTERVENTION_EN_COURS
    )
    if not is_valid:
        return JsonResponse(
            {"error": "invalid_transition", "current": res.statut, "allowed": allowed},
            status=400,
        )

    res.statut = Reservation.Status.INTERVENTION_EN_COURS
    _start_fields = ["statut"]
    # Démarre le chrono une seule fois (un éventuel redémarrage ne réinitialise
    # pas l'heure de début — la durée affichée reste fidèle à la réalité).
    if not res.intervention_started_at:
        res.intervention_started_at = timezone.now()
        _start_fields.append("intervention_started_at")
    res.save(update_fields=_start_fields)

    _schedule(
        [res.client_user_id] if res.client_user_id else [],
        "Intervention démarrée",
        f"{provider.nom} a démarré l'intervention.",
        {"type": "intervention.started", "reference": res.reference},
    )

    return JsonResponse({"ok": True, "statut": res.statut})


# Prestataire : déclarer travaux terminés
@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["prestataire"])
def api_prestataire_terminer_intervention(request, reference):
    """Le prestataire declare que les travaux sont termines."""
    _bootstrap_data()
    res = Reservation.objects.filter(reference=reference).first()
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)

    provider = Provider.objects.filter(user_id=request.api_user_id).first()
    if not provider:
        return JsonResponse({"error": "provider_not_found"}, status=403)

    if res.assigned_provider_id != provider.id:
        return JsonResponse({"error": "not_authorized"}, status=403)

    # Vérifier que l'acompte a été payé (indépendant du mode de paiement)
    if not res.acompte_valide:
        return JsonResponse(
            {
                "error": "acompte_required",
                "message": "Le client doit d'abord payer l'acompte pour démarrer l'intervention.",
            },
            status=400,
        )

    # Le prestataire déclare les travaux terminés → on passe en « En attente
    # client » (le CLIENT doit ensuite confirmer la prestation, ce qui fera
    # passer en « Terminee »). On NE saute PAS directement à « Terminee ».
    is_valid, allowed = validate_reservation_transition(res.statut, "En attente client")
    if not is_valid:
        return JsonResponse(
            {"error": "invalid_transition", "current": res.statut, "allowed": allowed},
            status=400,
        )

    res.statut = "En attente client"
    res.prestation_terminee_at = timezone.now()
    res.save(update_fields=["statut", "prestation_terminee_at"])

    _schedule(
        [res.client_user_id] if res.client_user_id else [],
        "Travaux terminés",
        f"{provider.nom} a terminé l'intervention. Veuillez confirmer la prestation.",
        {"type": "intervention.finished", "reference": res.reference},
    )

    return JsonResponse({"ok": True, "statut": res.statut})


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["prestataire"])
def api_prestataire_upload_photos(request, reference):
    """Upload des photos avant/après intervention par le prestataire."""
    _bootstrap_data()
    res = Reservation.objects.filter(reference=reference).first()
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)

    provider = Provider.objects.filter(user_id=request.api_user_id).first()
    if not provider or res.assigned_provider_id != provider.id:
        return JsonResponse({"error": "not_authorized"}, status=403)

    try:
        data = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)

    photos_avant = data.get("photos_avant", [])
    photos_apres = data.get("photos_apres", [])
    type_photo = data.get("type", "avant")  # "avant" ou "apres"

    if type_photo == "avant" and photos_avant:
        current = res.photos_avant or []
        res.photos_avant = current + photos_avant
    elif type_photo == "apres" and photos_apres:
        current = res.photos_apres or []
        res.photos_apres = current + photos_apres
    elif photos_avant:
        current = res.photos_avant or []
        res.photos_avant = current + photos_avant
    elif photos_apres:
        current = res.photos_apres or []
        res.photos_apres = current + photos_apres

    res.save(update_fields=["photos_avant", "photos_apres"])

    return JsonResponse(
        {
            "ok": True,
            "photos_avant": res.photos_avant,
            "photos_apres": res.photos_apres,
        }
    )


# Client : confirmer les travaux et ouvrir le paiement
@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client"])
def api_client_confirmer_travaux(request, reference):
    """Le client confirme que les travaux sont termines conformement au devis."""
    _bootstrap_data()
    res = Reservation.objects.filter(reference=reference).first()
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)

    uid = int(request.api_user_id)
    if res.client_user_id != uid and request.api_role != "admin":
        return JsonResponse({"error": "forbidden"}, status=403)

    # ORDRE MÉTIER : le client confirme les travaux AVANT de payer le solde.
    # Mobile Money avec un solde encore dû → on enregistre juste la confirmation
    # et on RESTE « En attente client » : le bouton « Payer le solde » apparaît
    # ensuite, et c'est le paiement du solde qui libère les fonds + passe Terminee.
    montant_restant = Decimal(str(res.montant_restant or 0))
    solde_du_mm = (
        res.payment_type != Reservation.PaymentType.ESPECES
        and res.acompte_valide
        and montant_restant > 0
        and not res.solde_valide
    )

    if solde_du_mm:
        res.client_confirme_prestation_at = timezone.now()
        res.save(update_fields=["client_confirme_prestation_at"])
        return JsonResponse(
            {
                "ok": True,
                "statut": res.statut,
                "solde_du": True,
                "montant_restant": float(montant_restant),
                "payment_type": res.payment_type,
            }
        )

    # Sinon (espèces, ou MM déjà soldé) → on passe « Terminee ».
    target_status = Reservation.Status.DONE
    is_valid, allowed = validate_reservation_transition(res.statut, target_status)
    if not is_valid:
        return JsonResponse(
            {"error": "invalid_transition", "current": res.statut, "allowed": allowed},
            status=400,
        )

    res.client_confirme_prestation_at = timezone.now()
    res.statut = target_status
    res.save(update_fields=["client_confirme_prestation_at", "statut"])

    # Mobile Money déjà soldé : la confirmation libère les fonds bloqués en escrow.
    # ESPÈCES : on NE libère RIEN ici — c'est le handshake qui s'applique
    # (le client déclare « j'ai payé en espèces », PUIS le prestataire confirme
    # « j'ai reçu » → seulement là la commission est reconnue).
    if res.payment_type != Reservation.PaymentType.ESPECES:
        try:
            from .services.escrow_service import EscrowService

            escrow_result = EscrowService.release_funds(res)
            logger.info("release_funds %s: %s", res.reference, escrow_result)
        except Exception as exc:
            logger.exception("release_funds %s: %s", res.reference, exc)

    return JsonResponse(
        {
            "ok": True,
            "statut": res.statut,
            "montant": float(res.montant) if res.montant else 0,
            "payment_type": res.payment_type,
        }
    )


# Client : annuler la demande
@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client"])
def api_client_annuler_demande(request, reference):
    """Le client annule sa demande (si pas encore accepted)."""
    _bootstrap_data()
    res = Reservation.objects.filter(reference=reference).first()
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)

    uid = int(request.api_user_id)
    if res.client_user_id != uid and request.api_role != "admin":
        return JsonResponse({"error": "forbidden"}, status=403)

    if res.statut in [
        Reservation.Status.INTERVENTION_EN_COURS,
        Reservation.Status.DONE,
    ]:
        return JsonResponse({"error": "cannot_cancel"}, status=400)

    res.statut = Reservation.Status.CANCELLED
    res.save(update_fields=["statut"])

    if res.assigned_provider and res.assigned_provider.user_id:
        _schedule(
            [res.assigned_provider.user_id],
            "Demande annulée",
            f"Le client a annulé la demande {res.reference}",
            {"type": "demande.cancelled", "reference": res.reference},
        )

    return JsonResponse({"ok": True, "statut": res.statut})


# Client : lister ses demandes
@require_GET
@require_api_auth(["client"])
def api_client_demandes_list(request):
    """Liste toutes les demandes du client."""
    uid = request.api_user_id
    statut_filter = request.GET.get("statut", "")

    qs = (
        Reservation.objects.filter(client_user_id=uid)
        .select_related("assigned_provider")
        .order_by("-pk")
    )

    if statut_filter:
        qs = qs.filter(statut=statut_filter)

    results = []
    for res in qs:
        provider = res.assigned_provider
        results.append(
            {
                "id": res.pk,
                "reference": res.reference,
                "title": res.title or "Demande de service",
                "prestataire": provider.nom if provider else None,
                "prestataire_id": provider.id if provider else None,
                "prestataire_specialite": provider.specialite if provider else None,
                "prestataire_rating": float(provider.average_rating) if provider else 0,
                "montant": float(res.montant) if res.montant else None,
                "statut": res.statut,
                "description_probleme": res.description_probleme or "",
                "address_label": res.address_label or "",
                "address_street": res.address_street or "",
                "address_quartier": res.address_quartier or "",
                "address_ville": res.address_ville or "",
                "address_pays": res.address_pays or "",
                "address_repere": res.address_repere or "",
                "address_is_approximate": res.address_is_approximate,
                "latitude": res.latitude,
                "longitude": res.longitude,
                "disponibilites_client": res.disponibilites_client or "",
                "is_urgent": res.is_urgent,
                "created_at": str(res.location_captured_at)
                if res.location_captured_at
                else None,
            }
        )

    return JsonResponse({"demandes": results})


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["prestataire"])
def api_prestataire_create_devis(request, reference):
    """Créer un devis pour une demande de réservation."""
    _bootstrap_data()
    res = Reservation.objects.filter(reference=reference).first()
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)

    provider = Provider.objects.filter(user_id=request.api_user_id).first()
    if not provider:
        return JsonResponse({"error": "provider_not_found"}, status=403)

    if res.assigned_provider_id != provider.id:
        return JsonResponse({"error": "not_authorized"}, status=403)

    if res.statut not in [
        Reservation.Status.DEMANDE_ENVOYEE,
        Reservation.Status.DEVIS_EN_COURS,
    ]:
        return JsonResponse({"error": "invalid_state"}, status=400)

    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)

    diagnostic = str(payload.get("diagnostic", "")).strip()[:2000]
    date_proposee = payload.get("date_proposee")
    heure_debut = payload.get("heure_debut")
    heure_fin = payload.get("heure_fin")
    try:
        validite_jours = int(payload.get("validite_jours", 7))
    except (TypeError, ValueError):
        validite_jours = 7
    if validite_jours <= 0:
        validite_jours = 7
    note_prestataire = str(payload.get("note_prestataire", "")).strip()[:1000]
    lignes_data = payload.get("lignes", [])
    if not isinstance(lignes_data, list):
        lignes_data = []

    # Devis en 2 temps : une ESTIMATION est une fourchette indicative, non
    # payable. Le presta enverra ensuite un devis ferme (montant exact).
    est_estimation = bool(payload.get("est_estimation"))
    prix_min = parse_money_amount(payload.get("prix_min", 0))
    prix_max = parse_money_amount(payload.get("prix_max", 0))
    if est_estimation and prix_max > 0 and prix_min > prix_max:
        prix_min, prix_max = prix_max, prix_min  # tolère l'inversion

    # Photos jointes au devis (data:image base64) — visibles par le client.
    raw_devis_photos = payload.get("photos") or payload.get("photos_prestataire") or []
    devis_photos = []
    if isinstance(raw_devis_photos, list):
        for entry in raw_devis_photos[:6]:
            s = str(entry).strip()
            if not s.startswith("data:image/"):
                continue
            if len(s) > 600_000:
                s = s[:600_000]
            devis_photos.append(s)

    if not diagnostic:
        return JsonResponse({"error": "diagnostic_required"}, status=400)

    # Seul un devis FERME déjà envoyé/accepté bloque un nouveau devis. Une
    # estimation (indicative) ne bloque pas : elle sera suivie d'un devis ferme.
    existing_devis = Devis.objects.filter(
        reservation=res,
        est_estimation=False,
        statut__in=[Devis.Statut.ENVOYE, Devis.Statut.ACCEPTE],
    ).first()
    if existing_devis:
        return JsonResponse({"error": "devis_already_exists"}, status=400)

    # Quota de devis actifs selon le palier (Standard 3, Silver 15, Gold illimité)
    from .services.provider_subscription_service import ProviderSubscriptionService
    quota = ProviderSubscriptionService.devis_quota(provider)
    if quota is not None:
        active_count = Devis.objects.filter(
            prestataire=provider,
            statut__in=[Devis.Statut.BROUILLON, Devis.Statut.ENVOYE],
        ).count()
        if active_count >= quota:
            return JsonResponse({
                "error": "devis_quota_reached",
                "quota": quota,
                "active": active_count,
                "message": (
                    f"Vous avez atteint votre quota de {quota} devis actifs. "
                    "Passez à un palier supérieur (Silver/Gold) pour en créer davantage."
                ),
            }, status=403)

    from datetime import date, time
    from decimal import Decimal

    parsed_date = None
    if date_proposee:
        try:
            parsed_date = date.fromisoformat(date_proposee)
        except (ValueError, TypeError):
            pass

    def _parse_time(val):
        if not val:
            return None
        try:
            return time.fromisoformat(val)
        except (ValueError, TypeError):
            pass
        # Support HH:mm (sans secondes) pour Python <3.11
        if isinstance(val, str) and val.count(":") == 1:
            try:
                return time.fromisoformat(f"{val}:00")
            except (ValueError, TypeError):
                pass
        return None

    parsed_heure_debut = _parse_time(heure_debut)
    parsed_heure_fin = _parse_time(heure_fin)

    from .services.wallet_service import _get_effective_commission_rate
    eff = _get_effective_commission_rate(provider)
    commission_rate = int((eff * Decimal("100")).quantize(Decimal("1")))

    # Validation transition de statut — seulement pour un devis FERME (qui fait
    # passer la demande à DEVIS_ENVOYE, état payable). Une estimation ne change
    # pas l'état payable : on ne valide donc pas cette transition.
    if not est_estimation:
        is_valid, allowed = validate_reservation_transition(res.statut, "DEVIS_ENVOYE")
        if not is_valid:
            return JsonResponse(
                {"error": "invalid_transition", "current": res.statut, "allowed": allowed},
                status=400,
            )

    try:
        devis = Devis.objects.create(
            reference="",
            reservation=res,
            prestataire=provider,
            diagnostic=diagnostic,
            date_proposee=parsed_date,
            heure_debut=parsed_heure_debut,
            heure_fin=parsed_heure_fin,
            validite_jours=validite_jours,
            note_prestataire=note_prestataire,
            photos_prestataire=devis_photos,
            commission_rate=commission_rate,
        )

        valid_types = {c[0] for c in LigneDevis.TypeLigne.choices}
        sous_total = Decimal("0")
        for ligne_data in lignes_data:
            if not isinstance(ligne_data, dict):
                continue
            type_ligne = str(ligne_data.get("type_ligne", "AUTRE")).strip().upper()
            if type_ligne not in valid_types:
                type_ligne = "AUTRE"
            description = str(ligne_data.get("description", "")).strip()[:255]
            try:
                quantite = int(ligne_data.get("quantite", 1))
            except (TypeError, ValueError):
                quantite = 1
            if quantite <= 0:
                quantite = 1
            prix_unitaire = parse_money_amount(ligne_data.get("prix_unitaire", 0))
            if not description and prix_unitaire <= 0:
                continue

            ligne = LigneDevis.objects.create(
                devis=devis,
                type_ligne=type_ligne,
                description=description or "Prestation",
                quantite=quantite,
                prix_unitaire=prix_unitaire,
            )
            sous_total += ligne.total

        if est_estimation:
            # Estimation indicative : pas de lignes / pas de total payable.
            devis.est_estimation = True
            devis.prix_min = prix_min
            devis.prix_max = prix_max
            devis.sous_total = Decimal("0")
            devis.commission_montant = Decimal("0")
            devis.total_ttc = Decimal("0")
            devis.statut = Devis.Statut.ENVOYE
            devis.save()
            # La demande reste « en cours de devis » (NON payable) pour que le
            # presta puisse ensuite envoyer un devis ferme.
            if res.statut == Reservation.Status.DEMANDE_ENVOYEE:
                res.statut = Reservation.Status.DEVIS_EN_COURS
                res.save(update_fields=["statut"])
        else:
            devis.sous_total = sous_total
            devis.commission_montant = sous_total * Decimal(commission_rate) / 100
            # Façon B : le client paie le prix annoncé (sous_total) ; la commission
            # est prélevée sur la part du prestataire au moment du versement.
            devis.total_ttc = sous_total
            devis.statut = Devis.Statut.ENVOYE
            devis.save()
            # Un devis ferme périme les estimations antérieures (évite le doublon
            # côté client).
            Devis.objects.filter(
                reservation=res,
                est_estimation=True,
                statut=Devis.Statut.ENVOYE,
            ).exclude(pk=devis.pk).update(statut=Devis.Statut.EXPIRE)

            res.statut = Reservation.Status.DEVIS_ENVOYE
            res.save(update_fields=["statut"])
    except Exception as exc:  # noqa: BLE001 — on évite toute 500 brute côté app
        logger.exception("api_prestataire_create_devis: échec création devis %s", reference)
        return JsonResponse(
            {"error": "devis_creation_failed", "detail": str(exc)[:300]},
            status=400,
        )

    # Carte devis figée dans le fil de chat : le client la consulte comme un
    # aperçu professionnel et peut l'ouvrir/accepter directement.
    try:
        from .services.conversation_service import post_devis_card
        post_devis_card(res, devis)
    except Exception:
        logger.warning("post_devis_card échoué pour %s", res.reference, exc_info=True)

    _schedule(
        [res.client_user_id],
        "Nouveau devis reçu",
        f"Prestataire {provider.nom} a envoyé un devis pour {res.reference}",
        {"type": "devis.received", "reference": res.reference},
    )

    return JsonResponse(
        {
            "ok": True,
            "devis": {
                "id": devis.id,
                "reference": devis.reference,
                "diagnostic": devis.diagnostic,
                "date_proposee": str(devis.date_proposee)
                if devis.date_proposee
                else None,
                "heure_debut": str(devis.heure_debut) if devis.heure_debut else None,
                "heure_fin": str(devis.heure_fin) if devis.heure_fin else None,
                "sous_total": float(devis.sous_total),
                "commission_montant": float(devis.commission_montant),
                "total_ttc": float(devis.total_ttc),
                "net_prestataire": float(devis.sous_total - devis.commission_montant),
                "statut": devis.statut,
                "est_estimation": devis.est_estimation,
                "prix_min": float(devis.prix_min),
                "prix_max": float(devis.prix_max),
                "lignes": [
                    {
                        "id": l.id,
                        "type_ligne": l.type_ligne,
                        "description": l.description,
                        "quantite": l.quantite,
                        "prix_unitaire": float(l.prix_unitaire),
                        "total": float(l.total),
                    }
                    for l in devis.lignes.all()
                ],
            },
        }
    )


@csrf_exempt
@require_http_methods(["GET"])
@require_api_auth(["prestataire", "client"])
def api_reservation_devis(request, reference):
    """Récupérer le devis associé à une réservation."""
    res = Reservation.objects.filter(reference=reference).first()
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)

    uid = int(request.api_user_id)
    is_client = res.client_user_id == uid
    is_prest = bool(
        res.assigned_provider
        and res.assigned_provider.user_id
        and res.assigned_provider.user_id == uid
    )

    if request.api_role != "admin" and not is_client and not is_prest:
        return JsonResponse({"error": "forbidden"}, status=403)

    devis = Devis.objects.filter(reservation=res).order_by("-created_at").first()
    if not devis:
        return JsonResponse({"devis": None})

    return JsonResponse(
        {
            "devis": {
                "id": devis.id,
                "reference": devis.reference,
                "prestataire": {
                    "id": devis.prestataire.id,
                    "nom": devis.prestataire.nom,
                    "specialite": devis.prestataire.specialite,
                },
                "diagnostic": devis.diagnostic,
                "date_proposee": str(devis.date_proposee)
                if devis.date_proposee
                else None,
                "heure_debut": str(devis.heure_debut) if devis.heure_debut else None,
                "heure_fin": str(devis.heure_fin) if devis.heure_fin else None,
                "sous_total": float(devis.sous_total),
                "commission_rate": devis.commission_rate,
                "commission_montant": float(devis.commission_montant),
                "total_ttc": float(devis.total_ttc),
                "net_prestataire": float(devis.sous_total - devis.commission_montant),
                "note_prestataire": devis.note_prestataire,
                "photos_prestataire": devis.photos_prestataire or [],
                "refus_motif": devis.refus_motif or "",
                "validite_jours": devis.validite_jours,
                "statut": devis.statut,
                "est_estimation": devis.est_estimation,
                "prix_min": float(devis.prix_min),
                "prix_max": float(devis.prix_max),
                "created_at": str(devis.created_at),
                "lignes": [
                    {
                        "id": l.id,
                        "type_ligne": l.type_ligne,
                        "description": l.description,
                        "quantite": l.quantite,
                        "prix_unitaire": float(l.prix_unitaire),
                        "total": float(l.total),
                    }
                    for l in devis.lignes.all()
                ],
            },
        }
    )


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client"])
def api_client_accept_devis(request, reference):
    """Le client accepte un devis."""
    res = Reservation.objects.filter(reference=reference).first()
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)

    uid = int(request.api_user_id)
    if res.client_user_id != uid:
        return JsonResponse({"error": "forbidden"}, status=403)

    # On n'accepte QUE des devis fermes. Une estimation n'est pas payable :
    # le client doit attendre le devis ferme.
    devis = Devis.objects.filter(
        reservation=res, est_estimation=False, statut=Devis.Statut.ENVOYE
    ).first()
    if not devis:
        if Devis.objects.filter(
            reservation=res, est_estimation=True, statut=Devis.Statut.ENVOYE
        ).exists():
            return JsonResponse(
                {
                    "error": "estimation_only",
                    "detail": (
                        "Vous avez reçu une estimation. Le prestataire vous "
                        "enverra ensuite un devis ferme à accepter."
                    ),
                },
                status=409,
            )
        return JsonResponse({"error": "devis_introuvable", "detail": "Aucun devis en attente d'acceptation."}, status=404)
    if res.statut == Reservation.Status.DEVIS_ACCEPTE:
        return JsonResponse({"error": "deja_accepte", "detail": "Ce devis a déjà été accepté."}, status=409)

    is_valid, allowed = validate_reservation_transition(res.statut, "DEVIS_ACCEPTE")
    if not is_valid:
        return JsonResponse(
            {"error": "transition_invalide", "detail": f"Impossible d'accepter le devis (statut actuel : {res.statut})."},
            status=400,
        )

    devis.statut = Devis.Statut.ACCEPTE
    devis.save()

    res.statut = Reservation.Status.DEVIS_ACCEPTE
    # Caution déductible : si une caution de visite a été réglée, on la déduit
    # du montant à payer (elle a déjà été encaissée). Une seule fois.
    final_montant = devis.total_ttc
    update_fields = ["statut", "montant", "commission"]
    if res.caution_payee and not res.caution_deduite and res.caution_montant:
        from decimal import Decimal
        final_montant = devis.total_ttc - res.caution_montant
        if final_montant < Decimal("0"):
            final_montant = Decimal("0")
        res.caution_deduite = True
        update_fields.append("caution_deduite")
    res.montant = final_montant
    res.save(update_fields=update_fields)

    # Met à jour la carte devis du fil + ajoute un événement système clair.
    try:
        from .services.conversation_service import post_devis_card, post_system_event
        post_devis_card(res, devis)  # idempotent : garde/raffraîchit la carte
        post_system_event(
            res,
            "devis.accepted",
            f"✅ Devis {devis.reference} accepté — {int(devis.total_ttc)} F CFA.",
        )
    except Exception:
        logger.warning("chat devis accept échoué pour %s", res.reference, exc_info=True)

    _schedule(
        [res.assigned_provider.user_id] if res.assigned_provider else [],
        "Devis accepté",
        f"Le client a accepté le devis {devis.reference}",
        {"type": "devis.accepted", "reference": res.reference},
    )

    return JsonResponse(
        {"ok": True, "statut": res.statut, "montant": float(res.montant)}
    )


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client"])
def api_client_refuse_devis(request, reference):
    """Le client refuse un devis."""
    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)

    motif = str(payload.get("motif", "")).strip()[:500]

    res = Reservation.objects.filter(reference=reference).first()
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)

    uid = int(request.api_user_id)
    if res.client_user_id != uid:
        return JsonResponse({"error": "forbidden"}, status=403)

    devis = Devis.objects.filter(reservation=res, statut=Devis.Statut.ENVOYE).first()
    if not devis:
        return JsonResponse({"error": "devis_not_found"}, status=404)

    devis.statut = Devis.Statut.REFUSE
    devis.refus_motif = motif
    devis.note_prestataire = (
        f"{devis.note_prestataire}\n\nRefusé par le client: {motif}".strip()[:1000]
    )
    devis.save()

    res.statut = Reservation.Status.DEMANDE_ENVOYEE
    res.save(update_fields=["statut"])

    _schedule(
        [res.assigned_provider.user_id] if res.assigned_provider else [],
        "Devis refusé",
        f"Le client a refusé le devis {devis.reference}. Motif: {motif}",
        {"type": "devis.refused", "reference": res.reference},
    )

    return JsonResponse({"ok": True, "statut": res.statut})


def error_500(request):
    # Logue la traceback complète de l'exception non gérée (sinon les 500 sont
    # opaques côté Render — on ne voit que « server_error »). Indispensable pour
    # diagnostiquer (ex. crash de création de réservation).
    import sys
    import traceback as _tb

    exc = sys.exc_info()
    try:
        if exc and exc[0] is not None:
            logger.error(
                "HTTP 500 sur %s %s\n%s",
                request.method,
                request.get_full_path(),
                "".join(_tb.format_exception(*exc)),
            )
        else:
            logger.error("HTTP 500 sur %s %s (exception indisponible)",
                         request.method, request.get_full_path())
    except Exception:
        pass
    return JsonResponse({"error": "server_error"}, status=500)


@csrf_exempt
@require_http_methods(["POST"])
@login_required
def api_admin_reservation_move(request):
    """Déplace une réservation vers une nouvelle colonne Kanban (drag & drop)."""
    try:
        data = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)

    reservation_id = data.get("id") or data.get("reservation_id")
    new_status = data.get("status")

    if not reservation_id or not new_status:
        return JsonResponse({"error": "missing_fields"}, status=400)

    try:
        res = Reservation.objects.get(pk=int(reservation_id))
    except (Reservation.DoesNotExist, ValueError):
        return JsonResponse({"error": "not_found"}, status=404)

    old_status = res.statut

    # Valider la transition
    is_valid, allowed = validate_reservation_transition(old_status, new_status)
    if not is_valid:
        return JsonResponse(
            {
                "error": "invalid_transition",
                "from": old_status,
                "to": new_status,
                "allowed": allowed,
            },
            status=400,
        )

    res.statut = new_status
    res.save(update_fields=["statut"])

    return JsonResponse(
        {
            "ok": True,
            "from": old_status,
            "to": new_status,
            "reference": res.reference,
        }
    )


@csrf_exempt
@require_http_methods(["POST"])
@login_required
def api_admin_reservation_status(request, id):
    """Change le statut d'une réservation (depuis le drag & drop Kanban)."""
    try:
        data = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)

    new_status = data.get("status")
    if not new_status:
        return JsonResponse({"error": "status_required"}, status=400)

    try:
        res = Reservation.objects.get(pk=id)
    except Reservation.DoesNotExist:
        return JsonResponse({"error": "not_found"}, status=404)

    old_status = res.statut
    is_valid, allowed = validate_reservation_transition(old_status, new_status)
    if not is_valid:
        return JsonResponse(
            {
                "error": "invalid_transition",
                "from": old_status,
                "to": new_status,
                "allowed": allowed,
            },
            status=400,
        )

    res.statut = new_status
    res.save(update_fields=["statut"])

    return JsonResponse({"ok": True, "reference": res.reference, "statut": new_status})


def _normalize_metier(nom: str) -> str:
    import unicodedata
    s = unicodedata.normalize("NFKD", (nom or "").strip().lower())
    s = "".join(c for c in s if not unicodedata.combining(c))
    return " ".join(s.split())


@csrf_exempt
@require_http_methods(["GET", "POST", "OPTIONS"])
def api_public_metiers(request):
    """Espace communautaire « Proposer un métier » (vitrine).

    GET  → liste des métiers proposés (nom, nb de demandes, seuil, statut).
    POST → {nom, email} : ajoute une demande (crée le métier si nouveau).

    CORS ouvert (*) : endpoint public, appelé par le site vitrine (autre domaine).
    """
    from .models import MetierPropose

    def _cors(resp):
        resp["Access-Control-Allow-Origin"] = "*"
        resp["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
        resp["Access-Control-Allow-Headers"] = "Content-Type"
        return resp

    if request.method == "OPTIONS":  # préflight navigateur
        return _cors(JsonResponse({}))

    if request.method == "GET":
        items = []
        for m in MetierPropose.objects.all():
            items.append({
                "id": m.id,
                "nom": m.nom,
                "votes": m.votes,
                "seuil": MetierPropose.SEUIL,
                "statut": m.statut,
            })
        items.sort(key=lambda x: (-x["votes"], x["nom"]))
        return _cors(JsonResponse({"metiers": items, "seuil": MetierPropose.SEUIL}))

    # POST — proposer / rejoindre un métier
    from .throttle import check_rate_limit, rate_limited_response
    if check_rate_limit(request, "metier_propose", max_requests=10, window=300):
        return _cors(rate_limited_response())
    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return _cors(JsonResponse({"error": "invalid_json"}, status=400))
    nom = str(payload.get("nom", "")).strip()[:120]
    email = str(payload.get("email", "")).strip().lower()[:200]
    if len(nom) < 2:
        return _cors(JsonResponse({"error": "nom_trop_court"}, status=400))
    if "@" not in email or "." not in email:
        return _cors(JsonResponse({"error": "email_invalide"}, status=400))

    norm = _normalize_metier(nom)
    m, created = MetierPropose.objects.get_or_create(
        nom_normalise=norm, defaults={"nom": nom}
    )
    emails = list(m.emails or [])
    already = email in emails
    if not already:
        emails.append(email)
        m.emails = emails
        m.save(update_fields=["emails"])
        # Notifie l'admin quand le seuil est atteint.
        if m.votes == MetierPropose.SEUIL:
            try:
                Notification.objects.create(
                    title=f"Métier « {m.nom} » a atteint {MetierPropose.SEUIL} demandes : à ajouter ?"
                )
            except Exception:
                pass
    return _cors(JsonResponse({
        "ok": True,
        "created": created,
        "already": already,
        "metier": {"id": m.id, "nom": m.nom, "votes": m.votes,
                   "seuil": MetierPropose.SEUIL, "statut": m.statut},
    }, status=201 if created else 200))
