"""
Service metier BABIFIX SOS 24/7 (Depannage Express par Secteur).

Regles de securite et d'integrite :
  - T1 (Atomicite) : Premier artisan qui accepte via `select_for_update()` gagne
    exclusivement la mission SOS. Les autres recoivent un 409 + event WS `sos.closed`.
  - T2 (Calcul serveur) : `sos_fee_fcfa` (1500 FCFA jour / 2500 FCFA nuit & dimanche)
    est calcule cote serveur depuis `PlatformConfig` et l'heure UTC+0 (Abidjan).
  - T3 (Vie privee) : Tant que le devis ou la caution express n'est pas valide,
    le broadcast SOS ne revele que le quartier/ville et la distance (jamais la rue).
"""
from __future__ import annotations

import logging
import math
from datetime import datetime, timedelta, timezone as dt_timezone
from decimal import Decimal
from typing import Any

from django.db import transaction
from django.utils import timezone

logger = logging.getLogger("adminpanel.sos")


def _normalize_text(val: str) -> str:
    txt = (val or "").strip().lower()
    for a, b in (
        ("é", "e"), ("è", "e"), ("ê", "e"), ("ë", "e"),
        ("à", "a"), ("â", "a"), ("ô", "o"), ("î", "i"),
        ("ï", "i"), ("ù", "u"), ("û", "u"), ("ç", "c"),
    ):
        txt = txt.replace(a, b)
    return txt


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371.0
    p1 = math.radians(lat1)
    p2 = math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(max(0.0, 1.0 - a)))


def is_abidjan_night_or_sunday(
    now_dt: datetime | None = None,
    night_start_hour: int = 20,
    night_end_hour: int = 6,
) -> bool:
    """Abidjan est en UTC+0 toute l'annee. Renvoie True si dimanche ou 20h00-06h00."""
    ref = now_dt or timezone.now()
    if timezone.is_aware(ref):
        ref_utc = ref.astimezone(dt_timezone.utc)
    else:
        ref_utc = ref.replace(tzinfo=dt_timezone.utc)
    if ref_utc.weekday() == 6:  # Dimanche
        return True
    hour = ref_utc.hour
    return hour >= int(night_start_hour) or hour < int(night_end_hour)


def resolve_sos_category(category_id: int | None = None, title: str = ""):
    """Retourne la Category correspondante si trouvee."""
    from adminpanel.models import Category

    if category_id:
        cat = Category.objects.filter(pk=int(category_id)).first()
        if cat:
            return cat

    norm_title = _normalize_text(title)
    if not norm_title:
        return None

    # Priorite aux categories marquees supports_sos=True
    for cat in Category.objects.filter(supports_sos=True).order_by("id"):
        norm_cat = _normalize_text(cat.nom)
        if norm_cat and (norm_cat in norm_title or norm_title in norm_cat):
            return cat

    for cat in Category.objects.all().order_by("id"):
        norm_cat = _normalize_text(cat.nom)
        if norm_cat and (norm_cat in norm_title or norm_title in norm_cat):
            return cat
    return None


def check_sos_eligibility(
    category_id: int | None = None,
    title: str = "",
    now_dt: datetime | None = None,
) -> dict[str, Any]:
    """Evalue l'eligibilite SOS 24/7 et calcule le tarif serveur garanti."""
    from adminpanel.models import PlatformConfig

    cfg = PlatformConfig.get_solo()
    day_fee = int(getattr(cfg, "sos_day_fee_fcfa", 1500) or 1500)
    night_fee = int(getattr(cfg, "sos_night_fee_fcfa", 2500) or 2500)
    radius_km = int(getattr(cfg, "sos_radius_km", 7) or 7)
    ttl_sec = int(getattr(cfg, "sos_ttl_seconds", 300) or 300)
    night_start = int(getattr(cfg, "sos_night_start_hour", 20) or 20)
    night_end = int(getattr(cfg, "sos_night_end_hour", 6) or 6)

    cat = resolve_sos_category(category_id=category_id, title=title)
    eligible = bool(cat and getattr(cat, "supports_sos", False))

    # Fallback mots-cles d'urgence critique si le titre mentionne explicitement un
    # depannage vital meme sans category_id explicite
    if not eligible and title:
        norm_t = _normalize_text(title)
        sos_tokens = ("plomb", "fuite", "electr", "panne", "serrur", "clim", "froid", "court-circuit")
        if any(tok in norm_t for tok in sos_tokens):
            if cat is None or getattr(cat, "supports_sos", False):
                eligible = True

    night = is_abidjan_night_or_sunday(
        now_dt=now_dt,
        night_start_hour=night_start,
        night_end_hour=night_end,
    )
    fee = night_fee if night else day_fee
    schedule_label = (
        f"Astreinte Nuit / Dimanche ({night_start:02d}h-{night_end:02d}h)"
        if night
        else f"Journee Express ({night_end:02d}h-{night_start:02d}h)"
    )

    return {
        "eligible": eligible,
        "category_id": cat.id if cat else None,
        "category_name": cat.nom if cat else "",
        "is_night": night,
        "schedule_label": schedule_label,
        "fee_fcfa": fee,
        "day_fee_fcfa": day_fee,
        "night_fee_fcfa": night_fee,
        "deductible": True,
        "radius_km": radius_km,
        "ttl_seconds": ttl_sec,
        "disclaimer": (
            f"Forfait deplacement express {fee:,} FCFA (100 % deductible du devis final). "
            "Le technicien etablit le devis ferme avant les travaux."
        ).replace(",", " "),
    }


def _provider_coords(provider) -> tuple[float | None, float | None]:
    lat = getattr(provider, "service_latitude", None) or getattr(provider, "latitude", None)
    lon = getattr(provider, "service_longitude", None) or getattr(provider, "longitude", None)
    if lat is not None and lon is not None:
        return float(lat), float(lon)
    return None, None


def find_sector_sos_providers(
    reservation,
    category=None,
    radius_km: int | None = None,
) -> list[tuple[Any, float | None]]:
    """
    Retourne TOUS les artisans approuves et disponibles du secteur (rayon km ou
    meme commune/ville), tries par proximite + palier + note.
    """
    from adminpanel.models import PlatformConfig, Provider

    cfg = PlatformConfig.get_solo()
    max_km = float(radius_km or getattr(cfg, "sos_radius_km", 7) or 7)

    qs = Provider.objects.filter(
        statut=Provider.Status.VALID,
        disponible=True,
        is_deleted=False,
    ).select_related("category", "user")

    cat = category or resolve_sos_category(title=getattr(reservation, "title", ""))
    if cat is not None:
        qs = qs.filter(category=cat)

    res_lat = getattr(reservation, "latitude", None)
    res_lon = getattr(reservation, "longitude", None)
    res_quartier = _normalize_text(getattr(reservation, "address_quartier", ""))
    res_ville = _normalize_text(getattr(reservation, "address_ville", ""))
    res_sector = _normalize_text(getattr(reservation, "sos_sector", ""))

    matches: list[tuple[Any, float | None]] = []
    now = timezone.now()

    for p in qs:
        p_lat, p_lon = _provider_coords(p)
        dist: float | None = None
        if (
            res_lat is not None
            and res_lon is not None
            and p_lat is not None
            and p_lon is not None
        ):
            dist = round(haversine_km(float(res_lat), float(res_lon), p_lat, p_lon), 2)
            if dist <= max_km:
                matches.append((p, dist))
                continue

        # Repli secteur textuel (commune / ville) si GPS manquant sur l'un des deux
        p_ville = _normalize_text(getattr(p, "ville", ""))
        p_zone = _normalize_text(getattr(p, "zone_intervention", ""))
        sector_hit = False
        if res_quartier and (res_quartier in p_ville or res_quartier in p_zone):
            sector_hit = True
        elif res_sector and (res_sector in p_ville or res_sector in p_zone):
            sector_hit = True
        elif res_ville and (res_ville in p_ville or p_ville in res_ville):
            if dist is None or dist <= max_km * 2:
                sector_hit = True
        if sector_hit:
            matches.append((p, dist))

    def _sort_key(item):
        prov, d = item
        tier = (getattr(prov, "premium_tier", "") or "").lower()
        until = getattr(prov, "premium_until", None)
        is_prem = bool(getattr(prov, "is_premium", False)) and (not until or until >= now)
        tier_rank = 2 if (is_prem and tier == "gold") else (1 if (is_prem and tier == "silver") else 0)
        dist_val = d if d is not None else 999.0
        rating = float(getattr(prov, "average_rating", 0) or 0)
        return (dist_val, -tier_rank, -rating)

    matches.sort(key=_sort_key)
    return matches


def dispatch_sos_radar(reservation, category=None) -> list[int]:
    """
    Diffuse l'alerte SOS en temps reel (WebSocket + FCM Push + Notification DB)
    a tous les artisans du secteur. Retourne les user_ids notifies.
    """
    from adminpanel.models import Notification
    from adminpanel.push_dispatch import _schedule
    from adminpanel.realtime import broadcast_prestataire_user

    matches = find_sector_sos_providers(reservation, category=category)
    sector_label = (
        ", ".join(
            x for x in [
                (reservation.address_quartier or "").strip(),
                (reservation.address_ville or "").strip(),
            ] if x
        )
        or (reservation.sos_sector or "").strip()
        or "Votre secteur"
    )
    expires_iso = reservation.sos_expires_at.isoformat() if reservation.sos_expires_at else ""
    fee_int = int(Decimal(str(reservation.sos_fee_fcfa or 0)))

    user_ids: list[int] = []
    for prov, dist in matches:
        uid = getattr(prov, "user_id", None)
        if not uid:
            continue
        user_ids.append(uid)
        payload = {
            "type": "sos.alert",
            "reference": reservation.reference,
            "title": reservation.title,
            "sector": sector_label,
            "distance_km": dist,
            "sos_fee_fcfa": fee_int,
            "sos_is_night": bool(reservation.sos_is_night),
            "description": (reservation.description_probleme or reservation.client_message or "")[:240],
            "expires_at": expires_iso,
        }
        try:
            broadcast_prestataire_user(uid, "sos.alert", payload)
        except Exception:
            logger.warning("WS sos.alert failed for uid=%s", uid, exc_info=True)
        try:
            Notification.objects.create(
                user_id=uid,
                title=f"SOS 24/7 {reservation.reference} : {reservation.title}",
                body=f"Secteur {sector_label} · Forfait express {fee_int} FCFA deductible.",
                notif_type="sos_alert",
                reference=reservation.reference,
            )
        except Exception:
            pass

    if user_ids:
        dist_txt = f"Secteur {sector_label}"
        try:
            _schedule(
                user_ids,
                f"URGENCE SOS : {reservation.title}",
                f"{dist_txt} · Forfait deplacement {fee_int} FCFA. Premier arrive, premier servi.",
                {
                    "type": "sos.alert",
                    "reference": reservation.reference,
                    "sector": sector_label,
                    "sos_fee_fcfa": str(fee_int),
                },
            )
        except Exception:
            logger.warning("Push sos.alert failed", exc_info=True)

    return user_ids


def claim_sos_mission(provider, reference: str) -> tuple[bool, dict[str, Any], int]:
    """
    Attribution atomique (Premier arrive, premier servi) d'une mission SOS.
    Utilise `select_for_update()` pour eliminer toute condition de course.
    """
    from adminpanel.models import Conversation, Notification, Provider, Reservation
    from adminpanel.push_dispatch import _schedule
    from adminpanel.realtime import broadcast_client_user, broadcast_prestataire_user

    if not provider or provider.statut != Provider.Status.VALID or getattr(provider, "is_deleted", False):
        return False, {"error": "provider_not_valid", "detail": "Compte artisan non valide."}, 403

    now = timezone.now()
    client_uid: int | None = None
    res_title = ""
    fee_int = 0
    sector_matches: list[tuple[Any, float | None]] = []

    with transaction.atomic():
        res = Reservation.objects.select_for_update().filter(reference=reference).first()
        if not res:
            return False, {"error": "not_found", "detail": "Mission introuvable."}, 404
        if not res.sos_mode:
            return False, {"error": "not_sos_mission", "detail": "Cette demande n'est pas en mode SOS."}, 400
        if res.statut in (
            Reservation.Status.CANCELLED,
            Reservation.Status.DONE,
        ):
            return False, {"error": "sos_closed", "detail": "Cette demande SOS est deja cloturee."}, 409

        if res.assigned_provider_id is not None:
            if res.assigned_provider_id == provider.id:
                return True, {
                    "ok": True,
                    "already_claimed_by_you": True,
                    "reference": res.reference,
                    "status": res.statut,
                }, 200
            return False, {
                "error": "sos_already_claimed",
                "detail": "Trop tard : un autre artisan du secteur vient de prendre cette mission SOS.",
            }, 409

        if res.sos_expires_at and now > res.sos_expires_at:
            return False, {
                "error": "sos_expired",
                "detail": "Le delai du radar SOS est expire.",
            }, 410

        res.assigned_provider = provider
        res.prestataire = provider.nom
        res.prestataire_user_id = provider.user_id
        res.sos_claimed_at = now
        res.statut = Reservation.Status.DEVIS_EN_COURS
        # T3 : on conserve address_is_approximate=True jusqu'au paiement caution/devis accepte.
        res.save(update_fields=[
            "assigned_provider",
            "prestataire",
            "prestataire_user_id",
            "sos_claimed_at",
            "statut",
        ])

        if res.client_user_id and provider.user_id:
            Conversation.objects.get_or_create(
                reservation=res,
                defaults={
                    "client_id": res.client_user_id,
                    "prestataire_id": provider.user_id,
                },
            )
        client_uid = res.client_user_id
        res_title = res.title
        fee_int = int(Decimal(str(res.sos_fee_fcfa or 0)))

    # Notifications post-commit hors verrou SQL
    if client_uid:
        try:
            broadcast_client_user(
                client_uid,
                "sos.claimed",
                {
                    "type": "sos.claimed",
                    "reference": reference,
                    "provider_id": provider.id,
                    "provider_name": provider.nom,
                    "sos_fee_fcfa": fee_int,
                },
            )
        except Exception:
            pass
        try:
            Notification.objects.create(
                user_id=client_uid,
                title=f"Artisan SOS trouve : {provider.nom}",
                body=f"{provider.nom} a pris votre demande {reference} ({res_title}).",
                notif_type="sos_claimed",
                reference=reference,
            )
        except Exception:
            pass
        try:
            _schedule(
                [client_uid],
                "Artisan SOS trouve",
                f"{provider.nom} prend en charge votre urgence {reference}.",
                {"type": "sos.claimed", "reference": reference, "provider_name": provider.nom},
            )
        except Exception:
            pass

    # Fermer l'alerte radar sur les ecrans des autres artisans du secteur
    try:
        sector_matches = find_sector_sos_providers(res)
        for other_p, _ in sector_matches:
            if other_p.id != provider.id and other_p.user_id:
                broadcast_prestataire_user(
                    other_p.user_id,
                    "sos.closed",
                    {"type": "sos.closed", "reference": reference},
                )
    except Exception:
        pass

    return True, {
        "ok": True,
        "reference": reference,
        "status": Reservation.Status.DEVIS_EN_COURS,
        "provider_name": provider.nom,
        "sos_fee_fcfa": fee_int,
    }, 200
