"""
Fidelite Service — Programme de fidélité client BABIFIX.

Le client cumule des points à chaque prestation terminée, puis peut les
convertir en crédit de réduction utilisable sur une prochaine réservation.

Règles :
  • 1 point par tranche de 1 000 FCFA dépensée sur une prestation terminée.
  • Conversion : à partir de 100 points, 1 point = 10 FCFA de réduction.
"""
import logging
from decimal import Decimal

from django.db import transaction

logger = logging.getLogger(__name__)

POINTS_PAR_1000_FCFA = 1      # 1 point / 1 000 F dépensés
POINT_VALUE_FCFA = 10         # 1 point = 10 F à la conversion
CONVERT_MIN_POINTS = 100      # palier minimum de conversion


class FideliteService:

    @classmethod
    @transaction.atomic
    def award_for_reservation(cls, reservation) -> int:
        """Attribue des points au client pour une prestation terminée.

        Idempotent : on ne crédite qu'une fois par réservation (flag stocké).
        Retourne le nombre de points attribués (0 si rien).
        """
        from ..models import UserProfile

        user_id = getattr(reservation, "client_user_id", None)
        if not user_id:
            return 0
        montant = reservation.montant or Decimal("0")
        if montant <= 0:
            return 0

        points = int(montant // 1000) * POINTS_PAR_1000_FCFA
        if points <= 0:
            return 0

        profile = UserProfile.objects.filter(user_id=user_id).select_for_update().first()
        if not profile:
            return 0

        # Idempotence : on marque la réservation pour éviter un double crédit
        if getattr(reservation, "fidelite_awarded", False):
            return 0
        try:
            reservation.fidelite_awarded = True
            reservation.save(update_fields=["fidelite_awarded"])
        except Exception:
            # champ absent → on continue quand même (best effort)
            pass

        profile.points_fidelite = (profile.points_fidelite or 0) + points
        profile.save(update_fields=["points_fidelite"])
        logger.info("Fidélité: +%d points au client %s (résa %s)", points, user_id, reservation.reference)
        return points

    @classmethod
    @transaction.atomic
    def convert_points(cls, user, points: int) -> dict:
        """Convertit des points en crédit de réduction (FCFA)."""
        from ..models import UserProfile

        profile = UserProfile.objects.filter(user=user).select_for_update().first()
        if not profile:
            return {"error": "profile_not_found"}

        points = int(points or 0)
        if points < CONVERT_MIN_POINTS:
            return {"error": "min_points", "detail": f"Minimum {CONVERT_MIN_POINTS} points pour convertir."}
        if points > (profile.points_fidelite or 0):
            return {"error": "insufficient_points", "detail": "Vous n'avez pas assez de points."}

        credit = Decimal(str(points * POINT_VALUE_FCFA))
        profile.points_fidelite -= points
        profile.fidelite_credit_fcfa = (profile.fidelite_credit_fcfa or Decimal("0")) + credit
        profile.save(update_fields=["points_fidelite", "fidelite_credit_fcfa"])
        return {
            "ok": True,
            "points_convertis": points,
            "credit_ajoute_fcfa": float(credit),
            "credit_total_fcfa": float(profile.fidelite_credit_fcfa),
            "points_restants": profile.points_fidelite,
        }

    @classmethod
    def summary(cls, user) -> dict:
        from ..models import UserProfile

        profile = UserProfile.objects.filter(user=user).first()
        pts = (profile.points_fidelite or 0) if profile else 0
        credit = float(profile.fidelite_credit_fcfa or 0) if profile else 0.0
        return {
            "points": pts,
            "valeur_point_fcfa": POINT_VALUE_FCFA,
            "equivalent_fcfa": pts * POINT_VALUE_FCFA,
            "seuil_conversion": CONVERT_MIN_POINTS,
            "convertible": pts >= CONVERT_MIN_POINTS,
            "credit_disponible_fcfa": credit,
            "regle": "1 point par 1 000 F dépensés ; 100 points = 1 000 F de réduction.",
        }
