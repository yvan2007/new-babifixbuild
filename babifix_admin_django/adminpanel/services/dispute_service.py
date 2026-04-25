"""
Dispute Service — Workflow de litige et mediation
Resolution: Ouvert → Mediation → Decision → Resolution
"""
import logging
from dataclasses import dataclass
from datetime import timedelta
from typing import Optional

from django.contrib.auth.models import User
from django.db import transaction
from django.utils import timezone

from ..models import Dispute, Reservation, Payment

logger = logging.getLogger(__name__)


@dataclass
class DisputeResult:
    """Resultat d'une operation sur litige."""
    success: bool
    dispute: Optional[Dispute] = None
    error: Optional[str] = None


class DisputeService:
    """Service pour la gestion des litiges."""
    
    MEDIATION_DAYS = 5  # Delai max pour mediation
    REFUND_PENALTY_CLIENT = 10  # % retnu au client si litige-resolve en sa faveur
    REFUND_PENALTY_PROVIDER = 5  # % retenu au provider
    
    @classmethod
    @transaction.atomic
    def create_dispute(
        cls,
        reservation: Reservation,
        user: User,
        motif: str,
        priorite: str = "Moyenne",
    ) -> DisputeResult:
        """Creer un litige pour une reservation.
        
        Args:
            reservation: Reservation concernee
            user: Utilisateur qui declare le litige
            motif: Raison du litige
            
        Returns:
            DisputeResult avec le litige cree
        """
        try:
            # Verifier si pas deja un litige ouvert
            existing = Dispute.objects.filter(
                reservation=reservation,
                decision=Dispute.Decision.OPEN,
            ).first()
            if existing:
                return DisputeResult(
                    success=False,
                    error="dispute_already_exists",
                )
            
            # Verifier que la reservation est terminee ou en cours
            if reservation.statut not in {
                Reservation.Statut.TERMINEE,
                Reservation.Statut.INTERVENTION_EN_COURS,
                "En attente client",
            }:
                return DisputeResult(
                    success=False,
                    error="invalid_reservation_status",
                )
            
            # Reference unique
            import secrets
            ref = f"DISP-{timezone.now().strftime('%Y%m%d')}-{secrets.token_hex(4)}"
            
            # Determiner le demandeur (client ou prestataire)
            is_client = reservation.client_id == user.id
            
            client_name = reservation.client.get_full_name() or reservation.client.username
            prest_name = reservation.provider.nom if reservation.provider else "N/A"
            
            dispute = Dispute.objects.create(
                reference=ref,
                motif=motif[:200],
                client=client_name,
                prestataire=prest_name,
                priorite=priorite,
                reservation=reservation,
            )
            
            # Mettre a jour la reservation
            reservation.statut = "Litige"
            reservation.save(update_fields=["statut"])
            
            logger.info(f"Dispute cree: {ref} pour reservation {reservation.reference}")
            
            return DisputeResult(
                success=True,
                dispute=dispute,
            )
            
        except Exception as e:
            logger.exception(f"Erreur creation dispute: {e}")
            return DisputeResult(
                success=False,
                error="creation_failed",
            )
    
    @classmethod
    def resolve_dispute(
        cls,
        dispute: Dispute,
        decision: str,
        admin_note: str = "",
    ) -> DisputeResult:
        """Resoudre un litige (action admin).
        
        Args:
            dispute: Litige a resoudre
            decision: Decision (Rembourser client, Liberer paiement, Partage partiel)
            admin_note: Note de l'admin
            
        Returns:
            DisputeResult
        """
        try:
            old_decision = dispute.decision
            dispute.decision = decision
            dispute.save(update_fields=["decision"])
            
            # Appliquer la decision
            if decision == Dispute.Decision.REFUND:
                # Rembourser client - liberer paiement
                cls._refund_client(dispute)
            elif decision == Dispute.Decision.RELEASE:
                # Liberer paiement au prestataire
                cls._release_to_provider(dispute)
            elif decision == Dispute.Decision.SPLIT:
                # Partager 50/50
                cls._split_payment(dispute)
            
            # Reprendre la reservation
            if dispute.reservation:
                if decision in {Dispute.Decision.REFUND}:
                    dispute.reservation.statut = "Annulee"
                else:
                    dispute.reservation.statut = dispute.reservation.statut
                dispute.reservation.save(update_fields=["statut"])
            
            logger.info(f"Dispute resolu: {dispute.reference} -> {decision}")
            
            return DisputeResult(
                success=True,
                dispute=dispute,
            )
            
        except Exception as e:
            logger.exception(f"Erreur resolution dispute: {e}")
            return DisputeResult(
                success=False,
                error="resolution_failed",
            )
    
    @classmethod
    def _refund_client(cls, dispute: Dispute) -> None:
        """Rembourser le client."""
        payment = Payment.objects.filter(reservation=dispute.reservation).first()
        if payment:
            payment.etat = Payment.State.COMPLETE  # Considere comme rembourse
            payment.save(update_fields=["etat"])
            logger.info(f"Client rembourse pour {dispute.reference}")
    
    @classmethod
    def _release_to_provider(cls, dispute: Dispute) -> None:
        """Liberer le paiement au prestataire."""
        payment = Payment.objects.filter(reservation=dispute.reservation).first()
        if payment:
            payment.etat = Payment.State.COMPLETE
            payment.valide_par_admin = True
            payment.save(update_fields=["etat", "valide_par_admin"])
            logger.info(f"Paiement libere pour {dispute.reference}")
    
    @classmethod
    def _split_payment(cls, dispute: Dispute) -> None:
        """Partager le paiement 50/50."""
        # Logique simplifiee - en prod, integrer avec wallet provider
        cls._release_to_provider(dispute)
    
    @classmethod
    def get_pending_disputes(cls, days: int = MEDIATION_DAYS) -> list:
        """Lister les litiges en attente de resolution.
        
        Args:
            days: Age max des litiges en cours
            
        Returns:
            Liste de disputes
        """
        threshold = timezone.now() - timedelta(days=days)
        return list(Dispute.objects.filter(
            decision=Dispute.Decision.OPEN,
            created_at__gte=threshold,
        ).order_by("-created_at"))
    
    @classmethod
    def auto_expire_disputes(cls) -> int:
        """Expirer automatiquement les litiges non resolves apres N jours.
        
        Returns:
            Nombre de litiges expires
        """
        threshold = timezone.now() - timedelta(days=cls.MEDIATION_DAYS)
        expired = Dispute.objects.filter(
            decision=Dispute.Decision.OPEN,
            created_at__lt=threshold,
        )
        count = expired.count()
        expired.update(decision=Dispute.Decision.REFUND)  # Default: rembours
        return count