"""
Notification Service - Logique metier pour les notifications
"""
import logging
from dataclasses import dataclass
from typing import Optional

from django.contrib.auth.models import User
from django.db.models import QuerySet

from ..models import Notification, UserProfile

logger = logging.getLogger(__name__)


@dataclass
class NotificationInput:
    """DTO pour creation de notification."""
    user: User
    title: str
    message: str
    type: str = "INFO"  # INFO, WARNING, ERROR, SUCCESS
    link: str = ""


@dataclass
class NotificationResult:
    """Resultat d'une operation de notification."""
    success: bool
    notification: Optional[Notification] = None
    error: Optional[str] = None


class NotificationService:
    """Service pour la gestion des notifications."""
    
    @staticmethod
    def create_notification(input_data: NotificationInput) -> NotificationResult:
        """Creer une notification.
        
        Args:
            input_data: Donnees de la notification
            
        Returns:
            NotificationResult avec la notification creee
        """
        try:
            notification = Notification.objects.create(
                user=input_data.user,
                title=input_data.title[:200],
                message=input_data.message[:1000],
                type=input_data.type,
                link=input_data.link[:500],
                is_read=False,
            )
            
            return NotificationResult(
                success=True,
                notification=notification,
            )
            
        except Exception as e:
            logger.exception(f"Erreur creation notification: {e}")
            return NotificationResult(
                success=False,
                error="creation_failed",
            )
    
    @staticmethod
    def get_user_notifications(
        user: User,
        unread_only: bool = False,
        page: int = 1,
        page_size: int = 20,
    ) -> QuerySet:
        """Recuperer les notifications d'un utilisateur.
        
        Args:
            user: Utilisateur
            unread_only: Ne recupérer que les non lus
            page: Numero de page
            page_size: Taille de page
            
        Returns:
            QuerySet de notifications
        """
        qs = Notification.objects.filter(user=user).order_by("-created_at")
        
        if unread_only:
            qs = qs.filter(is_read=False)
        
        start = (page - 1) * page_size
        end = start + page_size
        
        return qs[start:end]
    
    @staticmethod
    def mark_as_read(notification: Notification) -> bool:
        """Marquer une notification comme lue.
        
        Args:
            notification: Notification a mettre a jour
            
        Returns:
            True si succes
        """
        notification.is_read = True
        notification.save(update_fields=["is_read"])
        return True
    
    @staticmethod
    def mark_all_as_read(user: User) -> int:
        """Marquer toutes les notifications comme lues.
        
        Args:
            user: Utilisateur
            
        Returns:
            Nombre de notifications mises a jour
        """
        return Notification.objects.filter(
            user=user,
            is_read=False,
        ).update(is_read=True)
    
    @staticmethod
    def get_unread_count(user: User) -> int:
        """Compter les notifications non lues.
        
        Args:
            user: Utilisateur
            
        Returns:
            Nombre de notifications non lues
        """
        return Notification.objects.filter(
            user=user,
            is_read=False,
        ).count()
    
    @staticmethod
    def notify_reservation_created(reservation, user: User) -> NotificationResult:
        """Notifier creation de reservation.
        
        Args:
            reservation: Reservation creee
            user: Utilisateur a notifier
            
        Returns:
            NotificationResult
        """
        return NotificationService.create_notification(
            NotificationInput(
                user=user,
                title="Reservation créée",
                message=f"Votre demande #{reservation.reference} a été créée.",
                type="INFO",
                link=f"/reservations/{reservation.reference}/",
            )
        )
    
    @staticmethod
    def notify_reservation_status_changed(
        reservation,
        old_status: str,
        new_status: str,
    ) -> NotificationResult:
        """Notifier changement de statut de reservation.
        
        Args:
            reservation: Reservation modifiee
            old_status: Ancien statut
            new_status: Nouveau statut
            
        Returns:
            NotificationResult
        """
        user = reservation.client
        
        titles = {
            "Confirmee": "Reservation confirmée",
            "Terminee": "Intervention terminée",
            "Annulee": "Reservation annulée",
        }
        
        title = titles.get(new_status, f"Statut mis a jour: {new_status}")
        
        return NotificationService.create_notification(
            NotificationInput(
                user=user,
                title=title,
                message=f"Votre reservation #{reservation.reference} est maintenant: {new_status}",
                type="INFO",
                link=f"/reservations/{reservation.reference}/",
            )
        )
    
    @staticmethod
    def notify_payment_received(
        payment,
        provider_user: User,
    ) -> NotificationResult:
        """Notifier paiement recu par prestataire.
        
        Args:
            payment: Paiement effectuE
            provider_user: Prestataire a notifier
            
        Returns:
            NotificationResult
        """
        return NotificationService.create_notification(
            NotificationInput(
                user=provider_user,
                title="Paiement recu",
                message=f"Vous avez recu {payment.amount} CFA pour {payment.reservation.reference}",
                type="SUCCESS",
                link=f"/payments/{payment.id}/",
            )
        )