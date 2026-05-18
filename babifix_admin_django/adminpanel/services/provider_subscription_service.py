"""
Provider Subscription Service — Abonnements premium prestataire
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


# Configuration des abonnements premium prestataire BABIFIX.
# Chaque avantage listé dans `features` est RÉELLEMENT appliqué côté
# backend — pas de promesse marketing non tenue.
#
# Branchements :
# - commission_reduction → wallet_service._get_effective_commission_rate
# - visibility_boost     → geo_matching_service.rank_providers (score × boost)
# - max_active_devis     → views.api_prestataire_create_devis (quota check)
#
# Le tier "standard" est implicite (tout prestataire non-premium) : il
# n'est PAS dans PREMIUM_TIERS mais est exposé côté API via
# STANDARD_TIER_DESCRIPTOR pour pouvoir l'afficher dans le tableau
# comparatif Flutter.

PREMIUM_TIERS = {
    "silver": {
        "name": "Argent",
        "price": 7500,             # CFA / mois
        "price_annual": 72000,     # CFA / an  (−20 % = 7 500 × 12 × 0.8)
        "badge": "silver",
        "commission_reduction": 5,
        "visibility_boost": 1.30,
        "max_active_devis": 15,
        "popular": True,           # badge "Le plus populaire" côté UI
        "trial_days": 7,           # essai gratuit première souscription
        "features": [
            "Badge Argent sur votre profil",
            "Vu par 3 clients sur 10 en plus (visibilité +30 %)",
            "−5 points de commission sur chaque chantier",
            "Jusqu'à 15 devis actifs en parallèle",
            "Essai gratuit 7 jours à la 1ʳᵉ souscription",
            "Économisez 20 % avec l'abonnement annuel",
        ],
    },
    "gold": {
        "name": "Or",
        "price": 15000,            # CFA / mois
        "price_annual": 144000,    # CFA / an  (−20 %)
        "badge": "gold",
        "commission_reduction": 10,
        "visibility_boost": 1.60,
        "max_active_devis": -1,    # illimité
        "popular": False,
        "trial_days": 7,
        "features": [
            "Badge Or sur votre profil (visibilité maximale)",
            "Vu en premier par 6 clients sur 10 (visibilité +60 %)",
            "−10 points de commission sur chaque chantier",
            "Devis actifs illimités",
            "Essai gratuit 7 jours à la 1ʳᵉ souscription",
            "Économisez 20 % avec l'abonnement annuel",
        ],
    },
}


# Tier gratuit affiché en première colonne du tableau comparatif.
STANDARD_TIER_DESCRIPTOR = {
    "id": "standard",
    "name": "Standard",
    "price": 0,
    "price_annual": 0,
    "badge": "standard",
    "commission_reduction": 0,
    "visibility_boost_pct": 0,
    "max_active_devis": 3,
    "popular": False,
    "trial_days": 0,
    "features": [
        "Compte vérifié (KYC validé)",
        "Apparaître dans les résultats de recherche",
        "Jusqu'à 3 devis actifs en parallèle",
        "Commission standard sur les chantiers",
    ],
}


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
    tier: str  # bronze, silver, gold
    is_active: bool
    expires_at: Optional[date]
    badge: str
    visibility_multiplier: float


class ProviderSubscriptionService:
    """Service pour les abonnements premium prestataire."""
    
    @classmethod
    @transaction.atomic
    def subscribe(
        cls,
        provider: Provider,
        tier: str,
        billing_period: str = "monthly",   # "monthly" | "annual" | "trial"
    ) -> SubscriptionResult:
        """Souscrire à un abonnement premium.

        billing_period :
        - "monthly" → 30 jours, prix `price`
        - "annual"  → 365 jours, prix `price_annual` (−20 %)
        - "trial"   → 7 jours, gratuit, autorisé une seule fois par presta
        """
        tier_config = PREMIUM_TIERS.get(tier.lower())
        if not tier_config:
            return SubscriptionResult(
                success=False,
                error="invalid_tier",
            )

        if billing_period == "trial":
            if provider.has_used_premium_trial:
                return SubscriptionResult(
                    success=False,
                    error="trial_already_used",
                )
            duration_days = tier_config.get("trial_days", 7)
            is_annual = False
        elif billing_period == "annual":
            duration_days = 365
            is_annual = True
        else:
            duration_days = 30
            is_annual = False

        try:
            update_fields = [
                "is_premium",
                "premium_tier",
                "premium_since",
                "premium_until",
                "is_premium_annual",
            ]
            provider.is_premium = True
            provider.premium_tier = tier.lower()
            provider.premium_since = timezone.now()
            provider.premium_until = timezone.now() + timezone.timedelta(days=duration_days)
            provider.is_premium_annual = is_annual

            if billing_period == "trial":
                provider.has_used_premium_trial = True
                update_fields.append("has_used_premium_trial")

            provider.save(update_fields=update_fields)

            logger.info(
                f"Provider {provider.id} subscribed to {tier} ({billing_period}) until {provider.premium_until}"
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
            # Expire - desactiver
            provider.is_premium = False
            provider.save(update_fields=["is_premium"])
            return None
        
        tier = provider.premium_tier or "bronze"
        config = PREMIUM_TIERS.get(tier, PREMIUM_TIERS["bronze"])
        
        return ProviderSubscription(
            provider=provider,
            tier=tier,
            is_active=provider.is_premium,
            expires_at=provider.premium_until,
            badge=config["badge"],
            visibility_multiplier=config["visibility_boost"],
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
        expired.update(is_premium=False)
        
        if count:
            logger.info(f"Deactivated {count} expired premium subscriptions")
        
        return count
    
    @classmethod
    def calculate_effective_commission(
        cls,
        provider: Provider,
        base_commission: float = 18.0,
    ) -> float:
        """
        Calculer la commission effective avec reduction premium.
        
        Args:
            provider: Prestataire
            base_commission: Commission de base (18%)
            
        Returns:
            Commission effective
        """
        sub = cls.get_subscription(provider)
        if not sub:
            return base_commission
        
        config = PREMIUM_TIERS.get(sub.tier, {})
        reduction = config.get("commission_reduction", 0)
        
        return max(0, base_commission - reduction)
    
    @classmethod
    def get_available_tiers(cls, provider: Optional[Provider] = None) -> list[dict]:
        """Lister tous les tiers, gratuit + payants, pour le tableau comparatif.

        Si `provider` est fourni, on inclut `trial_available` (True ssi le
        prestataire n'a jamais consommé son essai gratuit 7 jours).
        """
        trial_available = (
            not bool(getattr(provider, "has_used_premium_trial", False))
            if provider is not None else True
        )

        tiers: list[dict] = [dict(STANDARD_TIER_DESCRIPTOR)]
        for tier_id, config in PREMIUM_TIERS.items():
            price_monthly = config["price"]
            price_annual = config.get("price_annual", price_monthly * 12)
            tiers.append({
                "id": tier_id,
                "name": config["name"],
                "price": price_monthly,
                "price_annual": price_annual,
                "annual_savings_pct": int(
                    100 - (price_annual / (price_monthly * 12) * 100)
                ) if price_monthly else 0,
                "badge": config["badge"],
                "commission_reduction": config["commission_reduction"],
                "visibility_boost_pct": int((config["visibility_boost"] - 1) * 100),
                "max_active_devis": config.get("max_active_devis", 3),
                "popular": config.get("popular", False),
                "trial_days": config.get("trial_days", 0),
                "trial_available": trial_available and config.get("trial_days", 0) > 0,
                "features": config.get("features", []),
            })
        return tiers