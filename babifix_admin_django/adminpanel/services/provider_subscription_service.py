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


# ✅ M2: Configuration des abonnements premium
PREMIUM_TIERS = {
    "bronze": {
        "name": "Bronze",
        "price": 5000,  # CFA/mois
        "badge": "bronze",
        "commission_reduction": 0,  # Pas de reduction
        "visibility_boost": 1.1,  # 10% plus visible
    },
    "silver": {
        "name": "Argent",
        "price": 10000,
        "badge": "silver",
        "commission_reduction": 5,  # 5% moins de commission
        "visibility_boost": 1.25,
    },
    "gold": {
        "name": "Or",
        "price": 20000,
        "badge": "gold",
        "commission_reduction": 10,
        "visibility_boost": 1.5,
    },
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
        duration_days: int = 30,
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
        tier_config = PREMIUM_TIERS.get(tier.lower())
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
            provider.save(update_fields=[
                "is_premium",
                "premium_tier",
                "premium_since",
                "premium_until",
            ])
            
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
    def get_available_tiers(cls) -> list[dict]:
        """Lister les tiers disponibles."""
        return [
            {
                "id": tier_id,
                "name": config["name"],
                "price": config["price"],
                "badge": config["badge"],
                "features": [
                    f"Badge {config['name']}",
                    f"+{int((config['visibility_boost'] - 1) * 100)}% visibilite",
                    f"-{config['commission_reduction']}% commission" if config['commission_reduction'] else "Commission standard",
                ],
            }
            for tier_id, config in PREMIUM_TIERS.items()
        ]