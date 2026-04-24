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
    "DEMANDE_ENVOYEE": {"DEVIS_EN_COURS", "Annulee"},
    "DEVIS_EN_COURS": {"DEVIS_ENVOYE", "Annulee"},
    "DEVIS_ENVOYE": {"DEVIS_ACCEPTE", "DEMANDE_ENVOYEE", "Annulee"},
    "DEVIS_ACCEPTE": {"INTERVENTION_EN_COURS", "Annulee"},
    "INTERVENTION_EN_COURS": {"En attente client", "Terminee", "Annulee"},
    "En attente client": {"Terminee", "Confirmee"},
    "Confirmee": {"En cours", "INTERVENTION_EN_COURS", "Annulee"},
    "En cours": {"En attente client", "Annulee"},
    "Terminee": {"Confirmee", "Annulee"},
}


def validate_reservation_transition(current_status, new_status):
    """Valide une transition de statut de réservation."""
    valid_next = RESERVATION_VALID_TRANSITIONS.get(current_status, set())
    if new_status not in valid_next:
        return False, list(valid_next)
    return True, []


RESERVATION_VALID_TRANSITIONS = {
    "En attente": {"Confirmee", "Annulee"},
    "DEMANDE_ENVOYEE": {"DEVIS_EN_COURS", "Annulee"},
    "DEVIS_EN_COURS": {"DEVIS_ENVOYE", "Annulee"},
    "DEVIS_ENVOYE": {"DEVIS_ACCEPTE", "DEMANDE_ENVOYEE", "Annulee"},
    "DEVIS_ACCEPTE": {"INTERVENTION_EN_COURS", "Annulee"},
    "INTERVENTION_EN_COURS": {"En attente client", "Terminee", "Annulee"},
    "En attente client": {"Terminee", "Confirmee"},
    "Confirmee": {"En cours", "INTERVENTION_EN_COURS", "Annulee"},
    "En cours": {"En attente client", "Annulee"},
    "Terminee": {"Confirmee", "Annulee"},
}

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
                Provider(
                    nom="Konan Jean",
                    specialite="Menage",
                    ville="Abidjan - Cocody",
                    tarif_horaire=5000,
                    statut="Valide",
                ),
                Provider(
                    nom="Kone Mariam",
                    specialite="Plomberie",
                    ville="Abidjan - Plateau",
                    tarif_horaire=8000,
                    statut="En attente",
                ),
                Provider(
                    nom="Fofana Ibrahim",
                    specialite="Electricite",
                    ville="Abidjan - Yopougon",
                    tarif_horaire=7500,
                    statut="Valide",
                ),
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
                    depense="2450€",
                ),
                Client(
                    nom="Claire Rousseau",
                    email="claire@email.com",
                    ville="Lyon",
                    reservations=18,
                    depense="1890€",
                ),
                Client(
                    nom="Thomas Blanc",
                    email="thomas@email.com",
                    ville="Marseille",
                    reservations=31,
                    depense="3200€",
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
                Category(nom="Menage", services=12, reservations=456, actif=True),
                Category(nom="Plomberie", services=8, reservations=234, actif=True),
                Category(nom="Peinture", services=5, reservations=78, actif=False),
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


def _safe_photo_url(url: str) -> str:
    """Retourne l'URL si c'est une URL HTTP/HTTPS ou une data URL base64 valide."""
    if not url:
        return ""
    s = url.strip()
    if s.startswith("http://") or s.startswith("https://"):
        return s
    if s.startswith("data:image"):
        return s
    return ""


def _services_from_db(request=None):
    """
    Prestataires validés uniquement — aucune donnée fictive.
    Prix = tarif_horaire (FCFA) saisi par le prestataire ; 0 si non défini.
    Note = moyenne réelle uniquement (sinon 0).
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
        if p.tarif_horaire is not None:
            try:
                base_price = int(round(float(p.tarif_horaire)))
            except (TypeError, ValueError):
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
                "image_url": _safe_photo_url(p.photo_portrait_url or ""),
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
    return {
        "id": int(m.id),
        "body": m.body or "",
        "image_url": img,
        "sender_id": int(m.sender_id),
        "created_at": m.created_at.isoformat(),
        "reply_to_id": int(m.reply_to_id) if m.reply_to_id else None,
        "lu": bool(getattr(m, "lu", False)),
        "deleted": bool(getattr(m, "deleted", False)),
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
    }
    return out


def _dashboard_forms_context(request, section):
    """Formulaires CRUD intégrés au dashboard (pas django-admin)."""
    ctx = {}
    if section == "prestataires":
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
        if eid and str(eid).isdigit():
            try:
                inst = Reservation.objects.get(pk=int(eid))
                ctx["reservation_form"] = ReservationForm(instance=inst)
                ctx["edit_reservation_id"] = inst.pk
            except Reservation.DoesNotExist:
                pass
    elif section == "kanban":
        # Kanban view - get all reservations grouped by status
        kanban_reservations = {}
        statuses = [
            "DEMANDE_ENVOYEE",
            "DEVIS_EN_COURS",
            "DEVIS_ENVOYE",
            "DEVIS_ACCEPTE",
            "INTERVENTION_EN_COURS",
            "En attente client",
            "Terminee",
        ]
        for s in statuses:
            kanban_reservations[s] = list(
                Reservation.objects.filter(statut=s)
                .select_related("client_user", "assigned_provider")
                .order_by("-created_at")[:20]
            )
        ctx["kanban_reservations"] = kanban_reservations
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
        if eid and str(eid).isdigit():
            try:
                inst = Notification.objects.get(pk=int(eid))
                ctx["notification_form"] = NotificationForm(instance=inst)
                ctx["edit_notification_id"] = inst.pk
            except Notification.DoesNotExist:
                ctx["notification_form"] = NotificationForm()
        else:
            ctx["notification_form"] = NotificationForm()
    elif section == "actualites":
        eid = request.GET.get("edit_actualite")
        if eid and str(eid).isdigit():
            try:
                inst = Actualite.objects.get(pk=int(eid))
                ctx["actualite_form"] = ActualiteForm(instance=inst)
                ctx["edit_actualite_id"] = inst.pk
            except Actualite.DoesNotExist:
                ctx["actualite_form"] = ActualiteForm()
        else:
            ctx["actualite_form"] = ActualiteForm()
    return ctx


def _dashboard_kpi_payload():
    """KPI pour le tableau de bord (réutilisé par la page complète et le fragment HTMX)."""
    conv_n = Conversation.objects.count()
    stats = [
        {
            "label": "Prestataires en attente",
            "value": Provider.objects.filter(statut="En attente").count(),
        },
        {
            "label": "Reservations actives",
            "value": Reservation.objects.filter(
                statut__in=["En attente", "Confirmee"]
            ).count(),
        },
        {
            "label": "Litiges ouverts",
            "value": Dispute.objects.filter(decision="En cours").count(),
        },
        {"label": "Transactions (FCFA) en base", "value": Payment.objects.count()},
        {"label": "Conversations actives (threads)", "value": conv_n},
    ]
    kpi = {
        "pending_providers": Provider.objects.filter(statut="En attente").count(),
        "active_reservations": Reservation.objects.filter(
            statut__in=["En attente", "Confirmee"]
        ).count(),
        "open_disputes": Dispute.objects.filter(decision="En cours").count(),
        "payments_count": Payment.objects.count(),
        "conversations": conv_n,
    }
    kpi_chart = {
        "labels": [
            "Prestataires en attente",
            "Réservations actives",
            "Litiges ouverts",
            "Paiements enregistrés",
            "Conversations actives",
        ],
        "data": [
            kpi["pending_providers"],
            kpi["active_reservations"],
            kpi["open_disputes"],
            kpi["payments_count"],
            kpi["conversations"],
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


def _filter_lists_for_section(section, search_q):
    """
    Filtre les listes selon la section courante et le paramètre GET q=.
    """
    q = (search_q or "").strip()
    providers = Provider.objects.filter(is_deleted=False).select_related(
        "user", "category"
    )
    reservations = Reservation.objects.all()
    litiges = Dispute.objects.all()
    # Synchroniser les clients réels depuis UserProfile (rattrapage des inscriptions passées)
    _sync_missing_clients()
    clients = Client.objects.all()
    paiements = Payment.objects.all()
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
    section = request.GET.get("section", "dashboard")
    allowed_sections = {
        "dashboard",
        "prestataires",
        "reservations",
        "litiges",
        "clients",
        "paiements",
        "categories",
        "notifications",
        "actualites",
        "parametres",
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
                    update_fields.append("refusal_reason")
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
                dispute.decision = decision
                dispute.save(update_fields=["decision"])
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
                obj.save()
                messages.success(request, "Actualité enregistrée.")
            else:
                messages.error(request, form.errors.as_text())
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

    if request.GET.get("partial") == "stats" and section == "dashboard":
        return render(
            request,
            "adminpanel/partials/dashboard_stats.html",
            {"stats": stats, "kpi_chart": kpi_chart},
        )

    _headings = {
        "dashboard": (
            "Tableau de bord",
            "Vue d'ensemble — montants en FCFA (Côte d'Ivoire). Les comptes clients/prestataires viennent des apps ; vous validez et pilotez.",
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
            "Vue drag & drop du pipeline de réservations — glissez pour changer le statut.",
        ),
        "litiges": ("Litiges", "Médiation et décisions enregistrées côté plateforme."),
        "clients": (
            "Clients",
            "Lecture / suivi des fiches issues de l'activité — pas de saisie manuelle des noms comme sur un guichet.",
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
            "Annonces publiques pour les apps client et prestataire — publication instantanée (WebSocket + push).",
        ),
        "parametres": (
            "Paramètres",
            "Commission, maintenance — impacte le comportement des apps connectées.",
        ),
    }
    page_heading, page_subtitle = _headings.get(section, _headings["dashboard"])

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
        "categories": categories,
        "notifications": notifications,
        "actualites": actualites,
        "params": settings_obj,
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
    services = _services_from_db(request)
    uid = request.api_user_id
    user = User.objects.filter(id=uid).first()
    client_name = (user.get_full_name() or user.username) if user else ""
    reservations = []

    def _push_reservation_row(item):
        has_rating = Rating.objects.filter(reservation=item).exists()
        can_rate = (
            item.statut == "Terminee" and item.client_user_id == uid and not has_rating
        )
        reservations.append(
            {
                "id": int(item.id),
                "reference": item.reference,
                "title": item.reference,
                "when_label": f"{item.statut} - {item.client}",
                "amount": item.montant,
                "status": item.statut,
                "payment_type": item.payment_type,
                "mobile_money_operator": item.mobile_money_operator or "",
                "cash_flow_status": item.cash_flow_status,
                "can_rate": can_rate,
                "rated": has_rating,
                "client_message": (item.client_message or "")[:500],
                "prestation_terminee_at": item.prestation_terminee_at.isoformat()
                if item.prestation_terminee_at
                else None,
                "client_confirme_prestation_at": item.client_confirme_prestation_at.isoformat()
                if item.client_confirme_prestation_at
                else None,
                "dispute_ouverte": bool(item.dispute_ouverte),
                "can_confirm_service": item.statut == "En attente client"
                and item.client_user_id == uid,
                "can_pay": item.statut == "Terminee"
                and bool(item.client_confirme_prestation_at)
                and not Payment.objects.filter(
                    reservation=item, etat=Payment.State.COMPLETE
                ).exists(),
                "can_view_devis": item.statut == "DEVIS_ENVOYE"
                and item.client_user_id == uid,
                "can_accept_devis": item.statut == "DEVIS_ENVOYE"
                and item.client_user_id == uid,
                "latitude": item.latitude,
                "longitude": item.longitude,
                "address_label": (item.address_label or "")[:500],
            }
        )

    for item in Reservation.objects.filter(
        Q(client_user_id=uid) | Q(client=client_name)
    ).distinct()[:8]:
        _push_reservation_row(item)
    news = [
        {"title": item.title, "subtitle": item.time}
        for item in Notification.objects.all()[:6]
    ]
    actualites = [
        _actualite_to_json(request, a, summary=True)
        for a in Actualite.objects.filter(publie=True).order_by("-date_publication")[
            :12
        ]
    ]
    payment_methods = [
        {"id": mid, "label": label, "logo_url": _static_absolute(request, path)}
        for mid, path, label in PAYMENT_METHOD_STATIC
    ]
    recent_providers = []
    for p in (
        Provider.objects.filter(statut=Provider.Status.VALID, is_deleted=False)
        .select_related("category", "user")
        .order_by("-user__date_joined")[:12]
    ):
        recent_providers.append(
            {
                "id": int(p.id),
                "nom": p.nom,
                "specialite": p.specialite,
                "ville": p.ville,
                "image_url": _safe_photo_url(p.photo_portrait_url or ""),
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
    rows = [
        _actualite_to_json(request, a, summary=True)
        for a in Actualite.objects.filter(publie=True).order_by("-date_publication")
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

    # Filtre géographique (latitude, longitude, rayon en km)
    lat = request.GET.get("lat")
    lon = request.GET.get("lon")
    radius = request.GET.get("radius", "10")  # défaut 10km

    if lat and lon:
        try:
            lat_f = float(lat)
            lon_f = float(lon)
            radius_km = float(radius)

            # Calcul approximatif avec bounding box
            # (pas PostGIS, mais suffisant pour un filtrage basique)
            lat_delta = radius_km / 111.0  # ~111km par degré
            lon_delta = radius_km / (111.0 * abs(math.cos(math.radians(lat_f))))

            qs = qs.filter(
                latitude__isnull=False,
                longitude__isnull=False,
                latitude__gte=lat_f - lat_delta,
                latitude__lte=lat_f + lat_delta,
                longitude__gte=lon_f - lon_delta,
                longitude__lte=lon_f + lon_delta,
            )
        except (ValueError, TypeError):
            pass

    # Tri
    sort_param = request.GET.get("sort", "rating")
    if sort_param == "tarif_asc":
        qs = qs.order_by("tarif_horaire")
    elif sort_param == "tarif_desc":
        qs = qs.order_by("-tarif_horaire")
    else:
        qs = qs.order_by("-average_rating", "-rating_count")

    items = []
    for p in qs:
        uid = p.user_id
        avg = (
            round(float(p.average_rating), 2)
            if (p.rating_count and p.average_rating)
            else None
        )
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
                "photo_portrait_url": _safe_photo_url(p.photo_portrait_url or ""),
                "image_url": _safe_photo_url(p.photo_portrait_url or ""),
            }
        )

    return JsonResponse({"providers": items, "count": len(items)})


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
    # Filtre géolocalisation avec rayon (Haversine)
    lat = request.GET.get("lat")
    lon = request.GET.get("lon")
    radius_km = request.GET.get("radius_km")
    if lat and lon and radius_km:
        try:
            client_lat = float(lat)
            client_lon = float(lon)
            max_radius = float(radius_km)
            # Get all providers with coordinates
            qs_with_coords = qs.filter(latitude__isnull=False, longitude__isnull=False)
            # Filter manually after fetching (since Django doesn't support Haversine natively)
            from django.db.models.functions import ACos, Cos, Sin, Radians

            # Simple bounding box pre-filter
            lat_float = float(lat)
            lon_float = float(lon)
            approx_deg = max_radius / 111.0  # 1 degree ≈ 111km
            qs = qs_with_coords.filter(
                latitude__gte=lat_float - approx_deg,
                latitude__lte=lat_float + approx_deg,
                longitude__gte=lon_float - approx_deg,
                longitude__lte=lon_float + approx_deg,
            )
        except ValueError:
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
    # Tri
    sort_param = request.GET.get("sort", "rating")
    if sort_param == "tarif_asc":
        qs = qs.order_by("tarif_horaire")
    elif sort_param == "tarif_desc":
        qs = qs.order_by("-tarif_horaire")
    else:
        qs = qs.order_by("-average_rating", "-rating_count")

    # Préparer le calcul de distance Haversine
    import math as _math

    client_lat_f = None
    client_lon_f = None
    max_radius_f = None
    if lat and lon and radius_km:
        try:
            client_lat_f = float(lat)
            client_lon_f = float(lon)
            max_radius_f = float(radius_km)
        except ValueError:
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

    items = []
    for p in qs:
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
                "photo_portrait_url": _safe_photo_url(p.photo_portrait_url or ""),
            }
        )
    return JsonResponse({"items": items, "total": len(items)})


@require_GET
@require_api_auth(["client", "admin"])
def api_client_conversations(request):
    uid = request.api_user_id
    convs = Conversation.objects.filter(client_id=uid).select_related(
        "prestataire", "reservation"
    )
    data = []
    for c in convs:
        last = c.messages.order_by("-created_at").first()
        preview = ""
        if last:
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
    """API client: get single provider detail."""
    try:
        p = Provider.objects.filter(pk=int(pk), statut="Valide").first()
    except ValueError:
        return JsonResponse({"error": "invalid_provider_id"}, status=400)
    if not p:
        return JsonResponse({"error": "provider_not_found"}, status=404)
    return JsonResponse(
        {
            "id": p.id,
            "nom": p.nom,
            "specialite": p.specialite,
            "ville": p.ville,
            "tarif_horaire": float(p.tarif_horaire) if p.tarif_horaire else None,
            "disponible": p.disponible,
            "rating_count": p.rating_count or 0,
            "average_rating": float(p.average_rating) if p.average_rating else 0.0,
            "bio": p.bio or "",
            "years_experience": p.years_experience or 0,
            "is_certified": p.is_certified,
            "latitude": p.latitude,
            "longitude": p.longitude,
            "photo_portrait_url": _safe_photo_url(p.photo_portrait_url or ""),
            "portfolio_photos": p.portfolio_photos or [],
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
        conv = Conversation.objects.create(
            client_id=res.client_user_id,
            prestataire_id=res.assigned_provider_id,
            reservation=res,
        )

    sender = User.objects.filter(pk=uid).first()
    message = Message.objects.create(
        conversation=conv,
        sender=sender,
        body=message_text,
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

    return JsonResponse(
        {
            "ok": True,
            "message_id": message.id,
        }
    )


@csrf_exempt
@require_http_methods(["GET"])
@require_api_auth(["client", "prestataire"])
def api_messages(request):
    prestataire_id = request.GET.get("prestataire_id")
    client_id = request.GET.get("client_id")
    reservation_id = request.GET.get("reservation_id")
    conv = None
    if conv_id:
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

    msg = Message(
        conversation=conv,
        sender_id=uid,
        body=body,
        reply_to_id=reply_to_id,
    )
    if image:
        msg.image = image
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

    # Vérifier les périodes d'indisponibilité du prestataire
    if prov:
        from datetime import date

        today = date.today()
        unavail = PrestataireUnavailability.objects.filter(
            provider=prov,
            date_debut__lte=today,
            date_fin__gte=today,
        ).exists()
        if unavail:
            return JsonResponse(
                {
                    "error": "provider_unavailable",
                    "message": "Ce prestataire est indisponible aujourd'hui.",
                },
                status=400,
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

    with transaction.atomic():
        existing_count = Reservation.objects.select_for_update().count() + 1
        while Reservation.objects.filter(
            reference=f"RES-{existing_count:03d}"
        ).exists():
            existing_count += 1
        reference = f"RES-{existing_count:03d}"

    # Générer clé d'idempotence pour éviter double paiement
    idem_key = str(uuid.uuid4())

    res_obj = Reservation.objects.create(
        reference=reference,
        title=title or "Demande de service",
        client=client_label,
        prestataire=prest_label,
        montant=amount_numeric,
        statut=initial_status,
        latitude=lat_f,
        longitude=lon_f,
        address_label=address_label,
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
        disponibilites_client=str(payload.get("disponibilites_client", "") or "")[:255],
        is_urgent=bool(payload.get("is_urgent", False)),
        idempotency_key=idem_key,
        appel_masque=True,  # Activer masquage par défaut
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
    return JsonResponse({"ok": True, "reference": reference}, status=201)


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
    photo_portrait_url = str(payload.get("photo_portrait_url", "") or "").strip()[:500]
    # Support base64 (data:image/...;base64,...)
    if not photo_portrait_url:
        photo_portrait_b64 = payload.get("photo_portrait_b64") or ""
        if isinstance(photo_portrait_b64, str) and photo_portrait_b64.startswith(
            "data:"
        ):
            photo_portrait_url = photo_portrait_b64[:500]
    cni_url = str(
        payload.get("cni_url", "") or payload.get("kyc_document_url", "") or ""
    ).strip()[:500]
    cni_recto_url = str(payload.get("cni_recto_url", "") or "").strip()[:500]
    cni_verso_url = str(payload.get("cni_verso_url", "") or "").strip()[:500]
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
            category=cat_obj,
        )

    Notification.objects.create(title=f"Nouveau prestataire en attente: {provider.nom}")
    return JsonResponse(
        {
            "ok": True,
            "provider_id": int(provider.id),
            "status": provider.statut,
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

    data = []
    for item in queryset[:20]:
        prov_obj = item.assigned_provider
        ravg = (
            round(float(prov_obj.average_rating), 1)
            if prov_obj and prov_obj.rating_count
            else 4.7
        )
        data.append(
            {
                "reference": item.reference,
                "client": item.client,
                "service": item.title or "Intervention domiciliaire",
                "date": item.location_captured_at.strftime("%d %b %Y")
                if item.location_captured_at
                else "—",
                "hour": item.location_captured_at.strftime("%H:%M")
                if item.location_captured_at
                else "—",
                "address": item.address_label or "—",
                "description": (
                    item.client_message
                    or item.description_probleme
                    or f"Detail de la demande {item.reference}"
                )[:500],
                "client_message": item.description_probleme or "",
                "disponibilites_client": item.disponibilites_client or "",
                "is_urgent": item.is_urgent,
                "amount": float(item.montant) if item.montant else 0,
                "status": item.statut,
                "payment_type": item.payment_type,
                "mobile_money_operator": item.mobile_money_operator or "",
                "cash_flow_status": item.cash_flow_status,
                "rating": ravg,
                "prix_propose": float(item.prix_propose) if item.prix_propose else None,
                "bookingId": item.id,
            }
        )
    return JsonResponse({"items": data})


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
    reservation.save(update_fields=["statut", "motif_refus_demande"])
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

    return JsonResponse(
        {
            "available": True,
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


@require_GET
@require_api_auth(["prestataire", "admin"])
def api_prestataire_earnings(request):
    _bootstrap_data()
    period = request.GET.get("period", "month")
    prov = _prestataire_provider_for_user(request.api_user_id)
    name = prov.nom if prov else ""
    payments = (
        Payment.objects.filter(prestataire=name) if name else Payment.objects.none()
    )

    total = 0.0
    for pay in payments:
        raw = pay.montant.replace("€", "").replace("FCFA", "").strip()
        try:
            total += float(raw)
        except ValueError:
            pass

    transactions = []
    for x in payments[:20]:
        transactions.append(
            {
                "client": x.client,
                "service": "Prestation",
                "gross": x.montant,
                "commission": x.commission,
                "net": x.montant,
                "status": x.etat,
            }
        )

    pc = payments.count()
    month_total = int(total) if total else 0
    summary = {
        "day": {"total": month_total, "count": pc},
        "week": {"total": month_total, "count": pc},
        "month": {"total": month_total, "count": pc},
    }
    data = summary.get(period, summary["month"])
    return JsonResponse({"summary": data, "transactions": transactions})


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
    payments = Payment.objects.filter(prestataire=prov.nom)
    pay_sum = 0.0
    for pay in payments:
        raw = pay.montant.replace("€", "").replace("FCFA", "").strip()
        try:
            pay_sum += float(raw)
        except ValueError:
            pass
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
                    prov.photo_portrait_url or prov.cni_url or ""
                ),
                "bio": prov.bio,
                "average_rating": float(prov.average_rating or 0),
                "rating_count": int(prov.rating_count or 0),
                "tarif_horaire": float(prov.tarif_horaire)
                if prov.tarif_horaire is not None
                else None,
                "disponible": prov.disponible,
                "category_nom": (cat.nom if cat else "") or "",
                "category_id": int(cat.id) if cat else None,
                "category_icone_url": (cat.icone_url or "").strip() if cat else "",
                "years_experience": int(prov.years_experience or 0),
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
                "nb_paiements": payments.count(),
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

    # Chercher par email d'abord, puis par username
    user = None
    if email:
        try:
            user = User.objects.get(email__iexact=email)
        except User.DoesNotExist:
            pass
    if not user and username:
        try:
            user = User.objects.get(username__iexact=username)
        except User.DoesNotExist:
            pass

    if not user:
        return JsonResponse({"error": "invalid_credentials"}, status=401)
    if not user.check_password(password):
        return JsonResponse({"error": "invalid_credentials"}, status=401)
    profile = UserProfile.objects.filter(user=user, active=True).first()
    if not profile:
        return JsonResponse({"error": "user_role_not_found"}, status=403)
    token = create_token(user.id, profile.role)
    refresh = create_refresh_token(user.id, profile.role)
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

    user = User.objects.create_user(
        username=username,
        password=password,
        email=email if email else None,
    )
    email_token = _secrets.token_urlsafe(32)
    profile = UserProfile.objects.create(
        user=user,
        role=role,
        active=True,
        phone_e164=phone_e164,
        country_code=country_code,
        email_verify_token=email_token,
    )
    # Envoi email de vérification si email fourni
    if user.email:
        from .views_v2 import _send_verification_email

        _send_verification_email(user.email, email_token)

    # Email de bienvenue
    try:
        from .views_extra import email_welcome

        email_welcome(user, role)
        print(f"[OK] Email bienvenue appele pour {user.email}")
    except Exception as e:
        print(f"[ERROR] Erreur email_welcome: {e}")

    # Synchroniser le Client dans la table admin dès l'inscription
    if role == UserProfile.Role.CLIENT:
        try:
            client_email = user.email or username
            Client.objects.create(
                nom=username,
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


@require_GET
@require_api_auth()
def api_auth_me(request):
    user = User.objects.filter(id=request.api_user_id).first()
    if not user:
        return JsonResponse({"error": "user_not_found"}, status=404)
    profile = UserProfile.objects.filter(user=user).first()
    return JsonResponse(
        {
            "id": int(user.id),
            "username": user.username,
            "role": request.api_role,
            "phone_e164": profile.phone_e164 if profile else "",
            "country_code": profile.country_code if profile else "CI",
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
    DeviceToken.objects.update_or_create(
        token=token,
        defaults={"user_id": uid, "platform": platform},
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
    convs = Conversation.objects.filter(prestataire_id=uid).select_related(
        "client", "reservation"
    )
    data = []
    for c in convs:
        last = c.messages.order_by("-created_at").first()
        preview = ""
        if last:
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
    if res.statut != "Terminee":
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
    if res.statut != "Terminee":
        return JsonResponse({"error": "reservation_not_completed"}, status=400)
    if res.cash_client_declared_at:
        return JsonResponse({"error": "already_declared"}, status=400)
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
    if not res.cash_client_declared_at:
        return JsonResponse({"error": "client_not_declared"}, status=400)
    if res.cash_prestataire_confirmed_at:
        return JsonResponse({"error": "already_confirmed"}, status=400)
    res.cash_prestataire_confirmed_at = timezone.now()
    res.cash_flow_status = Reservation.CashFlowStatus.PENDING_ADMIN
    res.save(update_fields=["cash_prestataire_confirmed_at", "cash_flow_status"])
    Notification.objects.create(
        title=f"Paiement especes a valider (admin): {reference}"
    )
    return JsonResponse({"ok": True, "cash_flow_status": res.cash_flow_status})


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
        res.cash_admin_validated_at = timezone.now()
        res.cash_flow_status = Reservation.CashFlowStatus.VALIDATED
        res.save(update_fields=["cash_admin_validated_at", "cash_flow_status"])
        ref_pay = f"PAY-CASH-{res.reference}"
        if not Payment.objects.filter(reference=ref_pay).exists():
            Payment.objects.create(
                reference=ref_pay,
                client=res.client,
                prestataire=res.prestataire,
                montant=res.montant,
                commission="0",
                etat=Payment.State.COMPLETE,
                reservation=res,
                type_paiement=Payment.TypePaiement.ESPECES,
                valide_par_admin=True,
            )
        Notification.objects.create(title=f"Paiement especes valide admin: {reference}")
        return JsonResponse({"ok": True, "cash_flow_status": res.cash_flow_status})
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
    """Catégories pour vitrine / apps (UML Categorie)."""
    _bootstrap_data()
    rows = []
    cats = (
        Category.objects.filter(actif=True)
        .annotate(
            providers_count=Count(
                "providers",
                filter=Q(
                    providers__statut=Provider.Status.VALID, providers__is_approved=True
                ),
            )
        )
        .order_by("ordre_affichage", "nom")
    )
    for c in cats:
        rows.append(
            {
                "id": int(c.id),
                "nom": c.nom,
                "description": c.description,
                "icone_slug": (c.icone_slug or "").strip(),
                "icone_url": _category_icon_url(request, c)
                or (c.icone_url or "").strip(),
                "ordre_affichage": c.ordre_affichage,
                "providers_count": c.providers_count,
            }
        )
    return JsonResponse(
        {
            "categories": rows,
            "icon_library": [{"slug": s, "label": lb} for s, lb in CATEGORY_ICON_SLUGS],
        }
    )


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
    if res.statut != "En attente client":
        return JsonResponse(
            {"error": "invalid_state", "detail": "Statut attendu: En attente client"},
            status=400,
        )
    if res.dispute_ouverte:
        return JsonResponse({"error": "dispute_open"}, status=400)
    res.statut = "Terminee"
    res.client_confirme_prestation_at = timezone.now()
    res.save(update_fields=["statut", "client_confirme_prestation_at"])
    _schedule(
        [res.prestataire_user_id],
        "BABIFIX — Client a confirmé",
        f"Réservation {res.reference} — vous pouvez demander le paiement.",
        {"type": "client.confirmed", "reference": res.reference},
    )
    return JsonResponse({"ok": True, "status": res.statut})


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
    # Vérifier idempotence - éviter double paiement
    idem_key = payload.get("idempotency_key")
    if idem_key and res.idempotency_key != idem_key:
        return JsonResponse({"error": "already_paid"}, status=400)
    if _payment_complete_exists(res):
        return JsonResponse({"error": "already_paid"}, status=400)
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
    res.payment_client_note = note
    if mid == "ESPECES":
        res.payment_type = Reservation.PaymentType.ESPECES
        res.mobile_money_operator = ""
        tp = Payment.TypePaiement.ESPECES
    else:
        res.payment_type = Reservation.PaymentType.MOBILE_MONEY
        op_map = {
            "ORANGE_MONEY": Reservation.MobileMoneyOperator.ORANGE_MONEY,
            "MTN_MOMO": Reservation.MobileMoneyOperator.MTN_MOMO,
            "WAVE": Reservation.MobileMoneyOperator.WAVE,
            "MOOV": Reservation.MobileMoneyOperator.MOOV,
        }
        res.mobile_money_operator = op_map.get(mid, "")
        tp = Payment.TypePaiement.MOBILE_MONEY
    ref_pay = f"PAY-{res.reference}-{int(timezone.now().timestamp())}"
    commission = res.montant * Decimal("0.18") if res.montant else Decimal("0")
    Payment.objects.create(
        reference=ref_pay,
        client=res.client,
        prestataire=res.prestataire,
        montant=res.montant,
        commission=str(commission),  # 18% commission
        etat=Payment.State.COMPLETE,
        reservation=res,
        type_paiement=tp,
        valide_par_admin=False,
    )
    res.save(
        update_fields=["payment_type", "mobile_money_operator", "payment_client_note"]
    )
    _schedule(
        [res.prestataire_user_id],
        "BABIFIX — Paiement enregistré",
        f"{res.reference} — {mid}",
        {"type": "payment.recorded", "reference": res.reference},
    )
    return JsonResponse({"ok": True, "payment_reference": ref_pay})


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
    res.save(update_fields=["statut"])

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

    # STATUT STRICT: Interdire Terminée sans paiement confirméen
    if _payment_complete_exists(res):
        pass  # OK - paiement fait
    else:
        # Espèces déclarées mais pas encore validées - permettre avec avertissement
        if (
            res.payment_type == Reservation.PaymentType.ESPECES
            and res.cash_flow_status
            in {
                Reservation.CashFlowStatus.NA,
                Reservation.CashFlowStatus.PENDING_PRESTATAIRE,
            }
        ):
            pass  # OK - espèces en cours de validation
        else:
            return JsonResponse(
                {
                    "error": "payment_required",
                    "message": "Paiement non confirmé. Impossible de terminer sans paiement.",
                },
                status=400,
            )

    # Validation transition de statut
    is_valid, allowed = validate_reservation_transition(res.statut, "Terminee")
    if not is_valid:
        return JsonResponse(
            {"error": "invalid_transition", "current": res.statut, "allowed": allowed},
            status=400,
        )

    res.statut = "Terminee"
    res.prestation_terminee_at = timezone.now()
    res.save(update_fields=["statut", "prestation_terminee_at"])

    _schedule(
        [res.client_user_id] if res.client_user_id else [],
        "Travaux terminés",
        f"{provider.nom} a terminé l'intervention. Veuillez confirmer la réception.",
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

    target_status = Reservation.Status.CONFIRMED
    is_valid, allowed = validate_reservation_transition(res.statut, target_status)
    if not is_valid:
        return JsonResponse(
            {"error": "invalid_transition", "current": res.statut, "allowed": allowed},
            status=400,
        )

    res.client_confirme_prestation_at = timezone.now()
    res.statut = target_status
    res.save(update_fields=["client_confirme_prestation_at", "statut"])

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
    validite_jours = int(payload.get("validite_jours", 7))
    note_prestataire = str(payload.get("note_prestataire", "")).strip()[:1000]
    lignes_data = payload.get("lignes", [])

    if not diagnostic:
        return JsonResponse({"error": "diagnostic_required"}, status=400)

    existing_devis = Devis.objects.filter(
        reservation=res, statut__in=[Devis.Statut.ENVOYE, Devis.Statut.ACCEPTE]
    ).first()
    if existing_devis:
        return JsonResponse({"error": "devis_already_exists"}, status=400)

    from datetime import date, time
    from decimal import Decimal

    parsed_date = None
    if date_proposee:
        try:
            parsed_date = date.fromisoformat(date_proposee)
        except (ValueError, TypeError):
            pass

    parsed_heure_debut = None
    if heure_debut:
        try:
            parsed_heure_debut = time.fromisoformat(heure_debut)
        except (ValueError, TypeError):
            pass

    parsed_heure_fin = None
    if heure_fin:
        try:
            parsed_heure_fin = time.fromisoformat(heure_fin)
        except (ValueError, TypeError):
            pass

    category = provider.category
    commission_rate = 18
    if category and hasattr(category, "commission"):
        commission_rate = category.commission.commission_rate

    # Validation transition de statut
    is_valid, allowed = validate_reservation_transition(res.statut, "DEVIS_ENVOYE")
    if not is_valid:
        return JsonResponse(
            {"error": "invalid_transition", "current": res.statut, "allowed": allowed},
            status=400,
        )

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
        commission_rate=commission_rate,
    )

    sous_total = Decimal("0")
    for ligne_data in lignes_data:
        type_ligne = str(ligne_data.get("type_ligne", "AUTRE")).strip().upper()
        description = str(ligne_data.get("description", "")).strip()[:255]
        quantite = int(ligne_data.get("quantite", 1))
        prix_unitaire = Decimal(str(ligne_data.get("prix_unitaire", 0)))

        ligne = LigneDevis.objects.create(
            devis=devis,
            type_ligne=type_ligne,
            description=description,
            quantite=quantite,
            prix_unitaire=prix_unitaire,
        )
        sous_total += ligne.total

    devis.sous_total = sous_total
    devis.commission_montant = sous_total * Decimal(commission_rate) / 100
    devis.total_ttc = sous_total + devis.commission_montant
    devis.statut = Devis.Statut.ENVOYE
    devis.save()

    res.statut = Reservation.Status.DEVIS_ENVOYE
    res.save(update_fields=["statut"])

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
                "statut": devis.statut,
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
                "note_prestataire": devis.note_prestataire,
                "validite_jours": devis.validite_jours,
                "statut": devis.statut,
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

    devis = Devis.objects.filter(reservation=res, statut=Devis.Statut.ENVOYE).first()
    if not devis:
        return JsonResponse({"error": "devis_not_found"}, status=404)

    # Validation transition de statut
    is_valid, allowed = validate_reservation_transition(res.statut, "DEVIS_ACCEPTE")
    if not is_valid:
        return JsonResponse(
            {"error": "invalid_transition", "current": res.statut, "allowed": allowed},
            status=400,
        )

    devis.statut = Devis.Statut.ACCEPTE
    devis.save()

    res.statut = Reservation.Status.DEVIS_ACCEPTE
    res.montant = devis.total_ttc
    res.save(update_fields=["statut", "montant"])

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
