"""
Referral Service — Systeme de parrainage
Client -> Code promo -> Filleul + Parrain = Credits
"""
import logging
import secrets
from dataclasses import dataclass
from typing import Optional

from django.contrib.auth.models import User
from django.db import transaction
from django.utils import timezone

from ..models import UserProfile

logger = logging.getLogger(__name__)


@dataclass
class ReferralResult:
    """Resultat d'une operation de parrainage."""
    success: bool
    referral_code: Optional[str] = None
    error: Optional[str] = None


class ReferralService:
    """Service de parrainage avec credits mutuels."""
    
    # ✅ F10: Configuration parrainage
    CREDIT_PARRAIN = 2000  # CFA credite au parrain
    CREDIT_FILLEUL = 1000  # CFA credite au filleul (sur premiere reservation)
    CODE_LENGTH = 8
    
    @classmethod
    def generate_referral_code(cls, user: User) -> str:
        """Genere un code de parrainage unique."""
        prefix = user.username[:3].upper()
        suffix = secrets.token_hex(4)[:self.CODE_LENGTH - 3]
        return f"{prefix}{suffix}"
    
    @classmethod
    @transaction.atomic
    def create_referral_code(cls, user: User) -> ReferralResult:
        """Cree un code de parrainage pour un utilisateur."""
        try:
            profile, _ = UserProfile.objects.get_or_create(user=user)
            
            #Verifier si pas deja un code
            if profile.referral_code:
                return ReferralResult(
                    success=True,
                    referral_code=profile.referral_code,
                )
            
            #Generer et sauvegarder
            profile.referral_code = cls.generate_referral_code(user)
            profile.save(update_fields=["referral_code"])
            
            return ReferralResult(
                success=True,
                referral_code=profile.referral_code,
            )
            
        except Exception as e:
            logger.exception(f"Erreur creation code referral: {e}")
            return ReferralResult(success=False, error="creation_failed")
    
    @classmethod
    @transaction.atomic
    def apply_referral_code(
        cls,
        code: str,
        new_user: User,
    ) -> ReferralResult:
        """Applique un code de parrainage lors de l'inscription.
        
        Args:
            code: Code du parrain
            new_user: Nouvel utilisateur (filleul)
            
        Returns:
            ReferralResult
        """
        try:
            #Chercher le parrain
            parrains = UserProfile.objects.filter(referral_code=code.upper())
            if not parrains.exists():
                return ReferralResult(success=False, error="invalid_code")
            
            parrain = parrains.first()
            
            #Pas de parrainage de soi-meme
            if parrain.user_id == new_user.id:
                return ReferralResult(success=False, error="self_referral_not_allowed")
            
            #Creer le lien (champ推荐)
            profile, _ = UserProfile.objects.get_or_create(user=new_user)
            profile.recommended_by = parrain.user_id
            profile.referral_code_used = code.upper()
            profile.save(update_fields=["recommended_by", "referral_code_used"])
            
            #Crediter le parrain (en production, ajouter au wallet)
            parrain.referral_credits_earned = (parrain.referral_credits_earned or 0) + cls.CREDIT_PARRAIN
            parrain.save(update_fields=["referral_credits_earned"])
            
            logger.info(f"Referral applique: {new_user.id} parrain={parrains.user_id}")
            
            return ReferralResult(success=True)
            
        except Exception as e:
            logger.exception(f"Erreur application referral: {e}")
            return ReferralResult(success=False, error="application_failed")
    
    @classmethod
    def validate_first_booking_reward(cls, user: User) -> bool:
        """Verifie et credite le bonus premiere reservation du filleul."""
        try:
            profile = UserProfile.objects.filter(user=user).first()
            if not profile or profile.referral_bonus_applied:
                return False
            
            #Crediter le bonus (1000 CFA)
            profile.referral_bonus_applied = True
            profile.save(update_fields=["referral_bonus_applied"])
            
            logger.info(f"Bonus premiere reservation applique pour user={user.id}")
            return True
            
        except Exception:
            return False
    
    @classmethod
    def get_referral_stats(cls, user: User) -> dict:
        """Recupere les statistiques de parrainage."""
        profile = UserProfile.objects.filter(user=user).first()
        if not profile:
            return {"code": None, "parrains": 0, "credits": 0}
        
        #Compter les filleuls
        filleuls = UserProfile.objects.filter(recommended_by=user.id).count()
        
        return {
            "code": profile.referral_code,
            "parrains": filleuls,
            "credits_earned": profile.referral_credits_earned or 0,
        }


# ✅ M3: Commission variable selon categorie
CATEGORY_COMMISSIONS = {
    #Plomberie - service courant, marge elevee
    "plomberie": 15,
    #Menage - tres concurrentiel
    "menage": 20,
    #Electricite - специалист
    "electricite": 15,
    #Peinture - materiaux chers
    "peinture": 18,
    #Maconnerie
    "maconnerie": 18,
    #Jardinage
    "jardinage": 20,
    #Default
    "default": 18,
}


def get_category_commission(category_slug: str) -> float:
    """Recupere la commission pour une categorie.
    
    Args:
        category_slug: Slug de la categorie
        
    Returns:
        Commission en pourcentage
    """
    return CATEGORY_COMMISSIONS.get(category_slug.lower(), CATEGORY_COMMISSIONS["default"])


def calculate_agent_commission(
    base_amount: float,
    category_slug: str,
    provider_tier: str = "bronze",
) -> float:
    """Calcule la commission avec ajustements.
    
    Args:
        base_amount: Montant de base
        category_slug: Categorie du service
        provider_tier: Tier premium (bronze/silver/gold)
        
    Returns:
        Montant de commission
    """
    base_commission = get_category_commission(category_slug)
    
    #Reduction premium
    premium_reduction = {
        "bronze": 0,
        "silver": 5,
        "gold": 10,
    }.get(provider_tier, 0)
    
    effective_rate = max(5, base_commission - premium_reduction)
    
    return base_amount * (effective_rate / 100)