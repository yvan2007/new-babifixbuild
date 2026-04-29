"""
Referral Service — Système de parrainage BABIFIX
Client → Code promo → Filleul + Parrain = Crédits wallet

Bugs corrigés v2 :
  - self.CODE_LENGTH → cls.CODE_LENGTH dans generate_referral_code()
  - profile.recommended_by = parrain.user_id → parrain.user (ForeignKey)
  - Crédits wallet réels au lieu de simples compteurs
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
    success: bool
    referral_code: Optional[str] = None
    error: Optional[str] = None


class ReferralService:
    CREDIT_PARRAIN = Decimal_int = 2000   # FCFA crédité au parrain
    CREDIT_FILLEUL = 1000                 # FCFA crédité au filleul (1ère réservation)
    CODE_LENGTH = 8

    @classmethod
    def generate_referral_code(cls, user: User) -> str:
        """Génère un code de parrainage unique."""
        prefix = user.username[:3].upper()
        # ← CORRECTION: cls.CODE_LENGTH, pas self.CODE_LENGTH
        suffix = secrets.token_hex(4)[:cls.CODE_LENGTH - len(prefix)]
        code = f"{prefix}{suffix}".upper()
        # Garantir l'unicité
        while UserProfile.objects.filter(referral_code=code).exists():
            suffix = secrets.token_hex(4)[:cls.CODE_LENGTH - len(prefix)]
            code = f"{prefix}{suffix}".upper()
        return code

    @classmethod
    @transaction.atomic
    def create_referral_code(cls, user: User) -> ReferralResult:
        try:
            profile, _ = UserProfile.objects.get_or_create(user=user)
            if profile.referral_code:
                return ReferralResult(success=True, referral_code=profile.referral_code)
            profile.referral_code = cls.generate_referral_code(user)
            profile.save(update_fields=["referral_code"])
            return ReferralResult(success=True, referral_code=profile.referral_code)
        except Exception as e:
            logger.exception("Erreur création code referral: %s", e)
            return ReferralResult(success=False, error="creation_failed")

    @classmethod
    @transaction.atomic
    def apply_referral_code(cls, code: str, new_user: User) -> ReferralResult:
        """Applique un code de parrainage lors de l'inscription."""
        try:
            parrain_profile = UserProfile.objects.filter(
                referral_code=code.upper().strip()
            ).select_related("user").first()

            if not parrain_profile:
                return ReferralResult(success=False, error="invalid_code")

            # ← CORRECTION: parrain_profile.user est l'utilisateur parrain
            if parrain_profile.user_id == new_user.id:
                return ReferralResult(success=False, error="self_referral_not_allowed")

            # Vérifier que le filleul n'a pas déjà utilisé un code
            new_profile, _ = UserProfile.objects.get_or_create(user=new_user)
            if new_profile.referral_code_used:
                return ReferralResult(success=False, error="code_already_used")

            # ← CORRECTION: assigned FK correctement
            new_profile.recommended_by = parrain_profile.user
            new_profile.referral_code_used = code.upper().strip()
            new_profile.save(update_fields=["recommended_by", "referral_code_used"])

            # Créditer le parrain (compteur + wallet si Provider)
            parrain_profile.referral_credits_earned = (
                (parrain_profile.referral_credits_earned or 0) + cls.CREDIT_PARRAIN
            )
            parrain_profile.save(update_fields=["referral_credits_earned"])

            # Si le parrain est un prestataire → créditer son wallet
            try:
                from adminpanel.models import Provider, WalletTransaction
                parrain_provider = Provider.objects.filter(user=parrain_profile.user).first()
                if parrain_provider:
                    parrain_provider.solde_fcfa = (
                        (parrain_provider.solde_fcfa or 0) + cls.CREDIT_PARRAIN
                    )
                    parrain_provider.save(update_fields=["solde_fcfa"])
                    WalletTransaction.objects.create(
                        provider=parrain_provider,
                        tx_type="credit",
                        amount_fcfa=cls.CREDIT_PARRAIN,
                        reference=f"REFERRAL-{new_user.username}",
                        description=f"Bonus parrainage : {new_user.username} a rejoint BABIFIX avec votre code",
                        status="success",
                    )
            except Exception as exc:
                logger.warning("Erreur crédit wallet parrain: %s", exc)

            logger.info("Referral appliqué: filleul=%s parrain=%s", new_user.id, parrain_profile.user_id)
            return ReferralResult(success=True)

        except Exception as e:
            logger.exception("Erreur application referral: %s", e)
            return ReferralResult(success=False, error="application_failed")

    @classmethod
    @transaction.atomic
    def validate_first_booking_reward(cls, user: User) -> bool:
        """
        Crédite le bonus 1ère réservation du filleul (1000 FCFA dans wallet).
        Appelé automatiquement quand un paiement est confirmé.
        """
        try:
            profile = UserProfile.objects.select_related("recommended_by").filter(user=user).first()
            if not profile or profile.referral_bonus_applied:
                return False

            profile.referral_bonus_applied = True
            profile.save(update_fields=["referral_bonus_applied"])

            # Créditer le filleul si prestataire
            try:
                from adminpanel.models import Provider, WalletTransaction
                provider = Provider.objects.filter(user=user).first()
                if provider:
                    provider.solde_fcfa = (provider.solde_fcfa or 0) + cls.CREDIT_FILLEUL
                    provider.save(update_fields=["solde_fcfa"])
                    WalletTransaction.objects.create(
                        provider=provider,
                        tx_type="credit",
                        amount_fcfa=cls.CREDIT_FILLEUL,
                        reference="REFERRAL-BONUS",
                        description=f"Bonus filleul parrainage — 1ère réservation",
                        status="success",
                    )
            except Exception as exc:
                logger.warning("Erreur crédit wallet filleul: %s", exc)

            logger.info("Bonus 1ère réservation appliqué pour user=%s", user.id)
            return True

        except Exception:
            return False

    @classmethod
    def get_referral_stats(cls, user: User) -> dict:
        profile = UserProfile.objects.filter(user=user).first()
        if not profile:
            return {"code": None, "filleuls": 0, "credits_earned": 0}

        filleuls = UserProfile.objects.filter(recommended_by=user).count()
        return {
            "code": profile.referral_code or None,
            "filleuls": filleuls,
            "credits_earned": float(profile.referral_credits_earned or 0),
            "bonus_premiere_reservation": profile.referral_bonus_applied,
            "credit_parrain": cls.CREDIT_PARRAIN,
            "credit_filleul": cls.CREDIT_FILLEUL,
        }


# ── Commission variable par catégorie ────────────────────────────────────────
CATEGORY_COMMISSIONS = {
    "plomberie": 15,
    "menage": 20,
    "electricite": 15,
    "peinture": 18,
    "maconnerie": 18,
    "jardinage": 20,
    "default": 18,
}


def get_category_commission(category_slug: str) -> int:
    return CATEGORY_COMMISSIONS.get(category_slug.lower(), CATEGORY_COMMISSIONS["default"])


def calculate_agent_commission(
    base_amount: float,
    category_slug: str,
    provider_tier: str = "bronze",
) -> float:
    base_commission = get_category_commission(category_slug)
    premium_reduction = {"bronze": 0, "silver": 5, "gold": 10}.get(provider_tier, 0)
    effective_rate = max(5, base_commission - premium_reduction)
    return base_amount * (effective_rate / 100)
