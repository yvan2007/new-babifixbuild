"""Dispute Service — utilitaires de litige (médiation).

NOTE : le cycle de vie réel des litiges est géré ailleurs :
- ouverture : api_client_open_dispute / api_prestataire_respond_dispute (views)
- décision admin + mouvements d'argent : EscrowService.resolve_dispute
  (RELEASE / REFUND / SPLIT) via l'action `litige_decision` du dashboard.

Ce module ne conserve que les helpers réellement utilisés (expiration auto +
liste des litiges en attente). Les anciennes méthodes create_dispute /
resolve_dispute, désynchronisées du modèle, ont été retirées (code mort).
"""
import logging
from datetime import timedelta

from django.utils import timezone

from ..models import Dispute

logger = logging.getLogger(__name__)


class DisputeService:
    """Helpers de médiation des litiges."""

    MEDIATION_DAYS = 5  # Délai max de médiation avant clôture par défaut.

    @classmethod
    def get_pending_disputes(cls, days: int = MEDIATION_DAYS) -> list:
        """Litiges encore ouverts dans la fenêtre de médiation."""
        threshold = timezone.now() - timedelta(days=days)
        return list(
            Dispute.objects.filter(
                decision=Dispute.Decision.OPEN,
                created_at__gte=threshold,
            ).order_by("-created_at")
        )

    @classmethod
    def auto_expire_disputes(cls) -> int:
        """Marque « à rembourser » les litiges ouverts depuis plus de N jours
        sans décision admin (politique : bénéfice du doute au client).

        Le versement du prestataire reste GELÉ tant que `dispute_ouverte` est
        vrai ; l'admin finalise via la décision (EscrowService.resolve_dispute),
        ce qui débloque et déclenche le remboursement client automatique.
        """
        threshold = timezone.now() - timedelta(days=cls.MEDIATION_DAYS)
        expired = Dispute.objects.filter(
            decision=Dispute.Decision.OPEN,
            created_at__lt=threshold,
        )
        count = expired.count()
        expired.update(decision=Dispute.Decision.REFUND)
        if count:
            logger.info("auto_expire_disputes : %s litige(s) expiré(s) → REFUND", count)
        return count
