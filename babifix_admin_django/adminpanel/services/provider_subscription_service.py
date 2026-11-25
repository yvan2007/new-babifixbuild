"""
Provider Subscription Service : Abonnements premium prestataire
Badge "Top", visibilite boostée, commission reduite
"""
import logging
from dataclasses import dataclass
from datetime import date
from typing import Optional

from django.contrib.auth.models import User
from django.db import transaction
from django.utils import timezone

from ..models import Provider, UserProfile

logger = logging.getLogger(__name__)


# ✅ Paliers premium : alignés sur le modèle économique BABIFIX (mémoire)
#   Standard : gratuit, commission de base, 3 devis actifs max
#   Silver   : 7 500 F/mois, −5 pts de commission, visibilité ×1.3, 15 devis, badge "Pro vérifié"
#   Gold     : 15 000 F/mois, −10 pts de commission, visibilité ×1.6, devis illimités, badge "Top"

# Palier gratuit par défaut (non souscrit)
STANDARD_TIER = {
    "id": "standard",
    "name": "Standard",
    "price": 0,
    "badge": "",
    "commission_reduction": 0,
    "visibility_boost": 1.0,
    "devis_quota": 5,
    "free": True,
}

# Paliers payants (souscriptibles)
PREMIUM_TIERS = {
    "silver": {
        "name": "Silver",
        "price": 7500,  # CFA/mois
        "badge": "Pro vérifié",
        "commission_reduction": 5,   # −5 points de commission
        "visibility_boost": 1.3,
        "devis_quota": 15,
    },
    "gold": {
        "name": "Gold",
        "price": 15000,
        "badge": "Top",
        "commission_reduction": 10,  # −10 points de commission
        "visibility_boost": 1.6,
        "devis_quota": None,         # illimité
    },
}


# Formule annuelle : on paie 10 mois, on en obtient 12 (≈ 2 mois offerts).
ANNUAL_PAID_MONTHS = 10
ANNUAL_MONTHS = 12
TRIAL_DAYS = 7


def annual_price(monthly_price: int) -> int:
    """Prix annuel (10 mois payés au lieu de 12)."""
    return int(monthly_price) * ANNUAL_PAID_MONTHS


def annual_savings_pct(monthly_price: int) -> int:
    """Pourcentage d'économie de la formule annuelle vs 12 mois pleins."""
    if not monthly_price:
        return 0
    full = monthly_price * ANNUAL_MONTHS
    saved = full - annual_price(monthly_price)
    return int(round(saved / full * 100))


def _get_live_tiers() -> tuple[dict, dict]:
    """Retourne les configurations paliers lues dynamiquement depuis PlatformConfig."""
    try:
        from .platform_config_service import get_dynamic_tier_configs
        return get_dynamic_tier_configs()
    except Exception:
        return STANDARD_TIER, PREMIUM_TIERS


def get_tier_config(tier: str) -> dict:
    """Configuration d'un palier quelconque (standard inclus), lue depuis la config active."""
    std, prem = _get_live_tiers()
    t = (tier or "").lower()
    if t in prem:
        return prem[t]
    return std


@dataclass
class SubscriptionResult:
    """Resultat d'une operation sur abonnement."""
    success: bool
    subscription: Optional["ProviderSubscription"] = None
    error: Optional[str] = None


@dataclass
class ProviderSubscription:
    """Abonnement premium prestataire."""
    provider: Provider
    tier: str  # silver, gold
    is_active: bool
    expires_at: Optional[date]
    badge: str
    visibility_multiplier: float
    devis_quota: Optional[int] = None


class ProviderSubscriptionService:
    """Service pour les abonnements premium prestataire."""
    
    @classmethod
    @transaction.atomic
    def subscribe(
        cls,
        provider: Provider,
        tier: str,
        duration_days: int = 30,
        is_annual: bool = False,
        is_trial: bool = False,
    ) -> SubscriptionResult:
        """
        Souscrire a un abonnement premium.
        
        Args:
            provider: Prestataire
            tier: bronze/silver/gold
            duration_days: Duree en jours
            
        Returns:
            SubscriptionResult
        """
        std_cfg, prem_tiers = _get_live_tiers()
        tier_config = prem_tiers.get(tier.lower())
        if not tier_config:
            return SubscriptionResult(
                success=False,
                error="invalid_tier",
            )
        
        try:
            # Mettre a jour le provider
            provider.is_premium = True
            provider.premium_tier = tier.lower()
            provider.premium_since = timezone.now()
            provider.premium_until = timezone.now() + timezone.timedelta(days=duration_days)
            provider.is_premium_annual = bool(is_annual)
            update_fields = [
                "is_premium",
                "premium_tier",
                "premium_since",
                "premium_until",
                "is_premium_annual",
            ]
            if is_trial:
                provider.premium_trial_used = True
                update_fields.append("premium_trial_used")
            provider.save(update_fields=update_fields)
            
            logger.info(
                f"Provider {provider.id} subscribed to {tier} until {provider.premium_until}"
            )
            
            return SubscriptionResult(
                success=True,
                subscription=ProviderSubscription(
                    provider=provider,
                    tier=tier,
                    is_active=True,
                    expires_at=provider.premium_until,
                    badge=tier_config["badge"],
                    visibility_multiplier=tier_config["visibility_boost"],
                    devis_quota=tier_config.get("devis_quota"),
                ),
            )
            
        except Exception as e:
            logger.exception(f"Subscription error: {e}")
            return SubscriptionResult(
                success=False,
                error="subscription_failed",
            )
    
    @classmethod
    def get_subscription(cls, provider: Provider) -> Optional[ProviderSubscription]:
        """Recuperer l'abonnement actif."""
        if not provider.is_premium:
            return None
        
        # Verifier expiration
        if provider.premium_until and provider.premium_until < timezone.now():
            # Expire - desactiver et reinitialiser le palier sur Standard
            provider.is_premium = False
            provider.premium_tier = "standard"
            provider.save(update_fields=["is_premium", "premium_tier"])
            return None
        
        tier = provider.premium_tier or ""
        _, prem_tiers = _get_live_tiers()
        if tier not in prem_tiers:
            return None
        config = prem_tiers[tier]

        return ProviderSubscription(
            provider=provider,
            tier=tier,
            is_active=provider.is_premium,
            expires_at=provider.premium_until,
            badge=config["badge"],
            visibility_multiplier=config["visibility_boost"],
            devis_quota=config.get("devis_quota"),
        )
    
    @classmethod
    def check_and_update_expired(cls) -> int:
        """Desactiver les abonnements expires.
        
        Returns:
            Nombre d'abonnements desactives
        """
        now = timezone.now()
        expired = Provider.objects.filter(
            is_premium=True,
            premium_until__lt=now,
        )
        count = expired.count()
        expired.update(is_premium=False, premium_tier="standard")
        
        if count:
            logger.info(f"Deactivated {count} expired premium subscriptions")
        
        return count
    
    # ------------------------------------------------------------------
    # Commission : barème dégressif par volume + réduction premium
    # ------------------------------------------------------------------
    DEGRESSIVE_SCALE = [
        (26, 6),   # 26+ missions/mois → −6 points (≈ 12 %)
        (11, 3),   # 11-25 missions/mois → −3 points (≈ 15 %)
        (0, 0),    # 0-10 missions/mois → taux de base (18 %)
    ]

    @classmethod
    def monthly_completed_missions(cls, provider: Provider) -> int:
        """Nombre de missions terminées par le prestataire sur les 30 derniers jours."""
        try:
            from ..models import Reservation
            since = timezone.now() - timezone.timedelta(days=30)
            return Reservation.objects.filter(
                assigned_provider=provider,
                statut=Reservation.Status.DONE,
                prestation_terminee_at__gte=since,
            ).count()
        except Exception:
            return 0

    @classmethod
    def base_commission_rate(cls, provider: Provider) -> float:
        """Taux de commission de base (%) : categorie ou PlatformConfig moins remise degressive."""
        top = 18.0
        floor = 5.0
        try:
            from .platform_config_service import get_runtime_configs
            _, cfg = get_runtime_configs()
            top = float(getattr(cfg, "base_commission_pct", 18) or 18)
            floor = float(getattr(cfg, "commission_floor_pct", 5) or 5)
        except Exception:
            pass
        if getattr(provider, "category_id", None):
            try:
                from ..models import CategoryCommission
                cc = CategoryCommission.objects.filter(
                    category_id=provider.category_id, actif=True
                ).first()
                if cc:
                    top = float(cc.commission_rate)
            except Exception:
                pass
        n = cls.monthly_completed_missions(provider)
        discount = next(d for threshold, d in cls.DEGRESSIVE_SCALE if n >= threshold)
        return max(floor, top - discount)

    @classmethod
    def calculate_effective_commission(
        cls,
        provider: Provider,
        base_commission: Optional[float] = None,
    ) -> float:
        """
        Commission effective (%) = base degressive (volume) - reduction premium.
        """
        _, prem_tiers = _get_live_tiers()
        floor = 5.0
        try:
            from .platform_config_service import get_runtime_configs
            _, cfg = get_runtime_configs()
            floor = float(getattr(cfg, "commission_floor_pct", 5) or 5)
        except Exception:
            pass
        base = base_commission if base_commission is not None else cls.base_commission_rate(provider)
        sub = cls.get_subscription(provider)
        reduction = 0
        if sub:
            reduction = prem_tiers.get(sub.tier, {}).get("commission_reduction", 0)
        return max(floor, base - reduction)

    @classmethod
    def visibility_multiplier(cls, provider: Provider) -> float:
        """Multiplicateur de visibilite pour le matching (1.0 si standard)."""
        sub = cls.get_subscription(provider)
        return sub.visibility_multiplier if sub else 1.0

    @classmethod
    def devis_quota(cls, provider: Provider) -> Optional[int]:
        """Quota de devis actifs autorises (None = illimite)."""
        std_cfg, prem_tiers = _get_live_tiers()
        sub = cls.get_subscription(provider)
        if sub:
            return prem_tiers.get(sub.tier, {}).get("devis_quota")
        return std_cfg["devis_quota"]

    @classmethod
    def badge(cls, provider: Provider) -> str:
        """Badge premium ('' si standard)."""
        sub = cls.get_subscription(provider)
        return sub.badge if sub else ""

    @classmethod
    def get_available_tiers(cls) -> list[dict]:
        """Lister tous les paliers (Standard inclus) pour l'écran d'abonnement."""
        std_cfg, prem_tiers = _get_live_tiers()

        def features(config):
            quota = config.get("devis_quota")
            quota_label = "Devis illimites" if quota is None else f"{quota} devis actifs"
            boost = int((config["visibility_boost"] - 1) * 100)
            feats = [
                f"-{config['commission_reduction']} pts de commission"
                if config["commission_reduction"] else "Commission de base",
                f"+{boost}% de visibilite" if boost else "Visibilite normale",
                quota_label,
            ]
            if config.get("badge"):
                feats.append(f"Badge « {config['badge']} »")
            return feats

        def numeric_fields(config):
            quota = config.get("devis_quota")
            return {
                "commission_reduction": config["commission_reduction"],
                "commission_effective_pct": config.get("commission_effective_pct"),
                "visibility_boost_pct": int((config["visibility_boost"] - 1) * 100),
                "max_active_devis": -1 if quota is None else quota,
            }

        tiers = [{
            "id": std_cfg["id"],
            "name": std_cfg["name"],
            "price": std_cfg["price"],
            "price_annual": 0,
            "annual_savings_pct": 0,
            "badge": std_cfg["badge"],
            "free": True,
            "trial_available": False,
            "features": features(std_cfg),
            **numeric_fields(std_cfg),
        }]
        tiers += [{
            "id": tier_id,
            "name": config["name"],
            "price": config["price"],
            "price_annual": annual_price(config["price"]),
            "annual_savings_pct": annual_savings_pct(config["price"]),
            "badge": config["badge"],
            "free": False,
            "trial_available": True,
            "features": features(config),
            **numeric_fields(config),
        } for tier_id, config in prem_tiers.items()]
        return tiers

    # ------------------------------------------------------------------
    # Calculateur de rentabilité premium (affiché dans l'app)
    # ------------------------------------------------------------------
    DEFAULT_BASKET = 25000  # panier moyen par défaut si aucun historique

    @classmethod
    def gmv_last_30d(cls, provider: Provider) -> float:
        """Volume de transactions (FCFA) sur les missions terminées des 30 derniers jours."""
        try:
            from django.db.models import Sum
            from ..models import Reservation
            since = timezone.now() - timezone.timedelta(days=30)
            agg = Reservation.objects.filter(
                assigned_provider=provider,
                statut=Reservation.Status.DONE,
                prestation_terminee_at__gte=since,
            ).aggregate(s=Sum("montant"))
            return float(agg["s"] or 0)
        except Exception:
            return 0.0

    @classmethod
    def _fmt(cls, n) -> str:
        """Formatage FCFA avec séparateur d'espace (style ivoirien)."""
        return f"{int(round(n)):,}".replace(",", " ")

    @classmethod
    def profitability(cls, provider: Provider) -> dict:
        """
        Calcule, à partir de l'activité réelle des 30 derniers jours, l'intérêt
        économique de chaque palier payant pour ce prestataire.

        Logique :
            economie  = GMV_30j × (réduction de commission en points / 100)
            gain_net  = economie − prix de l'abonnement
            seuil_gmv = prix / (réduction / 100)
        """
        missions = cls.monthly_completed_missions(provider)
        gmv = cls.gmv_last_30d(provider)
        basket = (gmv / missions) if missions else cls.DEFAULT_BASKET
        base = cls.base_commission_rate(provider)
        current = cls.calculate_effective_commission(provider)
        sub = cls.get_subscription(provider)
        current_tier = sub.tier if sub else "standard"

        options = []
        best = None
        _, prem_tiers = _get_live_tiers()
        for tier_id, cfg in prem_tiers.items():
            red = cfg["commission_reduction"]
            price = cfg["price"]
            economie = gmv * red / 100.0
            gain_net = economie - price
            seuil_gmv = (price / (red / 100.0)) if red else None
            seuil_missions = int(-(-seuil_gmv // basket)) if (seuil_gmv and basket) else None  # arrondi sup.
            opt = {
                "tier": tier_id,
                "name": cfg["name"],
                "price": price,
                "reduction": red,
                "economie": round(economie),
                "gain_net": round(gain_net),
                "seuil_gmv": round(seuil_gmv) if seuil_gmv else None,
                "seuil_missions": seuil_missions,
                "rentable": gain_net > 0,
            }
            options.append(opt)
            if opt["rentable"] and (best is None or gain_net > best["gain_net"]):
                best = opt

        recommended = best["tier"] if best else "standard"
        if best:
            message = (
                f"Ce mois-ci : {missions} mission(s) ({cls._fmt(gmv)} F). "
                f"Avec {best['name']}, tu aurais gardé +{cls._fmt(best['gain_net'])} F."
            )
        else:
            silver = next((o for o in options if o["tier"] == "silver"), None)
            seuil_m = silver["seuil_missions"] if silver else None
            if seuil_m:
                message = (
                    f"À ton volume actuel ({missions} mission(s)), le palier gratuit reste "
                    f"le plus avantageux. Silver devient rentable dès {seuil_m} missions/mois."
                )
            else:
                message = "À ton volume actuel, le palier gratuit reste le plus avantageux."

        return {
            "missions_30j": missions,
            "gmv_30j": round(gmv),
            "panier_moyen": round(basket),
            "base_commission": base,
            "current_commission": current,
            "current_tier": current_tier,
            "options": options,
            "recommended": recommended,
            "message": message,
        }