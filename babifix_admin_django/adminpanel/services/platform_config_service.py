"""
Source unique de verite pour la configuration dynamique BABIFIX.

Synchronise SystemSetting + PlatformConfig vers :
  1. Le moteur financier backend (ProviderSubscriptionService, WalletService, Devis/Escrow)
  2. L'API publique GET /api/public/config/ (et /api/config/)
  3. Le temps reel WebSocket (config.updated + settings.updated) vers les apps Flutter et le cockpit
  4. Le site Vitrine Django
"""
from __future__ import annotations

from typing import Any


def get_runtime_configs() -> tuple[Any, Any]:
    """Retourne (SystemSetting, PlatformConfig) sans lever d'erreur."""
    from adminpanel.models import PlatformConfig, SystemSetting

    sys_obj, _ = SystemSetting.objects.get_or_create(pk=1)
    cfg = PlatformConfig.get_solo()
    return sys_obj, cfg


def parse_enabled_operators(csv_value: str) -> list[str]:
    valid = ("wave", "orange", "mtn", "moov")
    raw = [p.strip().lower() for p in (csv_value or "").split(",") if p.strip()]
    picked = [op for op in raw if op in valid]
    return picked or list(valid)


def get_dynamic_tier_configs() -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    """Construit les dictionnaires standard + silver + gold depuis PlatformConfig."""
    try:
        cfg = get_runtime_configs()[1]
        base = int(getattr(cfg, "base_commission_pct", 18) or 18)
        floor = int(getattr(cfg, "commission_floor_pct", 5) or 5)
        silver_red = int(getattr(cfg, "silver_commission_reduction", 5) or 0)
        gold_red = int(getattr(cfg, "gold_commission_reduction", 10) or 0)
        silver_price = int(getattr(cfg, "silver_price_fcfa", 7500) or 0)
        gold_price = int(getattr(cfg, "gold_price_fcfa", 15000) or 0)
        std_quota = int(getattr(cfg, "standard_max_devis", 5) or 5)
        sil_quota = int(getattr(cfg, "silver_max_devis", 15) or 15)
        sil_boost = int(getattr(cfg, "silver_visibility_boost_pct", 30) or 0)
        gold_boost = int(getattr(cfg, "gold_visibility_boost_pct", 60) or 0)
    except Exception:
        base, floor = 18, 5
        silver_red, gold_red = 5, 10
        silver_price, gold_price = 7500, 15000
        std_quota, sil_quota = 5, 15
        sil_boost, gold_boost = 30, 60

    std_rate = max(floor, base)
    sil_rate = max(floor, base - silver_red)
    gold_rate = max(floor, base - gold_red)

    standard = {
        "id": "standard",
        "name": "Standard",
        "price": 0,
        "badge": "",
        "commission_reduction": 0,
        "commission_effective_pct": std_rate,
        "visibility_boost": 1.0,
        "visibility_boost_pct": 0,
        "devis_quota": std_quota,
        "free": True,
    }
    premium = {
        "silver": {
            "id": "silver",
            "name": "Silver",
            "price": silver_price,
            "badge": "Pro verifie",
            "commission_reduction": silver_red,
            "commission_effective_pct": sil_rate,
            "visibility_boost": round(1.0 + sil_boost / 100.0, 2),
            "visibility_boost_pct": sil_boost,
            "devis_quota": sil_quota,
        },
        "gold": {
            "id": "gold",
            "name": "Gold",
            "price": gold_price,
            "badge": "Top",
            "commission_reduction": gold_red,
            "commission_effective_pct": gold_rate,
            "visibility_boost": round(1.0 + gold_boost / 100.0, 2),
            "visibility_boost_pct": gold_boost,
            "devis_quota": None,
        },
    }
    return standard, premium


def build_public_platform_config() -> dict[str, Any]:
    """Payload JSON unifie consomme par Client Flutter, Prestataire Flutter et Vitrine."""
    sys_obj, cfg = get_runtime_configs()
    standard, premium = get_dynamic_tier_configs()
    operators = parse_enabled_operators(cfg.enabled_operators_csv)
    base_pct = int(cfg.base_commission_pct or 18)

    from adminpanel.models import Reservation, SiteContent

    email_item = SiteContent.objects.filter(key="contact_admin_email").first()
    support_email = (email_item.value if email_item and email_item.value else "contact@babifix.ci").strip()

    maint_item = SiteContent.objects.filter(key="maintenance_schedule").first()
    m_cfg = maint_item.json_value if (maint_item and isinstance(maint_item.json_value, dict)) else {}
    active_missions_cnt = Reservation.objects.exclude(
        statut__in=["Terminee", "DONE", "Annulee", "CANCELLED", "Refusee", "REJECTED"]
    ).count()

    from adminpanel.livekit_service import livekit_is_configured
    from adminpanel.services.audio_transcription_service import stt_provider_name
    from adminpanel.services.whatsapp_service import whatsapp_cloud_configured

    return {
        "commission_base_pct": base_pct,
        "commission_floor_pct": int(cfg.commission_floor_pct or 5),
        "tiers": {
            "standard": {
                "name": standard["name"],
                "price_fcfa": 0,
                "commission_pct": standard["commission_effective_pct"],
                "commission_reduction": 0,
                "max_devis": standard["devis_quota"],
                "visibility_boost_pct": 0,
            },
            "silver": {
                "name": premium["silver"]["name"],
                "price_fcfa": premium["silver"]["price"],
                "commission_pct": premium["silver"]["commission_effective_pct"],
                "commission_reduction": premium["silver"]["commission_reduction"],
                "max_devis": premium["silver"]["devis_quota"],
                "visibility_boost_pct": premium["silver"]["visibility_boost_pct"],
            },
            "gold": {
                "name": premium["gold"]["name"],
                "price_fcfa": premium["gold"]["price"],
                "commission_pct": premium["gold"]["commission_effective_pct"],
                "commission_reduction": premium["gold"]["commission_reduction"],
                "max_devis": -1,
                "visibility_boost_pct": premium["gold"]["visibility_boost_pct"],
            },
        },
        "escrow": {
            "frais_mise_en_relation_fcfa": int(cfg.frais_mise_en_relation_fcfa),
            "urgency_surcharge_pct": int(cfg.urgency_surcharge_pct),
            "auto_confirm_hours": int(cfg.escrow_auto_confirm_hours),
        },
        "wallet": {
            "min_withdrawal_fcfa": int(cfg.min_withdrawal_fcfa),
            "daily_withdrawal_cap_fcfa": int(cfg.daily_withdrawal_cap_fcfa),
        },
        "payment_modes": {
            "label": (sys_obj.mode_paiement or "").strip(),
            "allow_cash": bool(cfg.allow_cash_payments),
            "allow_mobile_money": bool(cfg.allow_mobile_money_payments),
            "operators": operators,
        },
        "apps": {
            "maintenance": bool(sys_obj.maintenance),
            "maintenance_scheduled_at": str(m_cfg.get("scheduled_at") or "").strip(),
            "maintenance_end_at": str(m_cfg.get("estimated_end_at") or "").strip(),
            "maintenance_message": str(m_cfg.get("message") or "").strip(),
            "maintenance_allow_active": bool(m_cfg.get("allow_active_missions", True)),
            "active_missions_count": active_missions_cnt,
            "auto_validation": bool(sys_obj.auto_validation),
            "require_kyc_for_visibility": bool(cfg.require_kyc_for_visibility),
            "require_supervisor_interview": bool(cfg.require_supervisor_interview),
            "fiabilite_gating_actif": bool(cfg.fiabilite_gating_actif),
            "fiabilite_seuil": int(cfg.fiabilite_seuil),
            "matching_radius_km": int(cfg.matching_radius_km),
            "calls_enabled": bool(livekit_is_configured()),
            "audio_transcription_enabled": bool(stt_provider_name()),
            "whatsapp_cloud_enabled": bool(whatsapp_cloud_configured()),
        },
        "radar": {
            "visite_sans_devis_jours": int(cfg.radar_visite_sans_devis_jours),
            "auto_suspension_actif": bool(cfg.auto_suspension_actif),
            "suspension_score_seuil": int(cfg.suspension_score_seuil),
            "suspension_visites_suspectes": int(cfg.suspension_visites_suspectes),
        },
        "support": {
            "phone": (cfg.support_phone or "").strip(),
            "whatsapp": (cfg.support_whatsapp or "").strip(),
            "email": support_email,
        },
        "updated_at": cfg.updated_at.isoformat() if cfg.updated_at else "",
    }


def broadcast_platform_config() -> dict[str, Any]:
    """Diffuse la configuration mise a jour a tous les clients WebSocket (admin + apps)."""
    payload = build_public_platform_config()
    try:
        from adminpanel import realtime

        realtime.broadcast_admin_event("settings.updated", payload)
        realtime.broadcast_client_event("config.updated", payload)
    except Exception:
        pass
    return payload
