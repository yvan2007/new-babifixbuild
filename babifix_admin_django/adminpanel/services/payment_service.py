"""
Payment Service - Logique metier pour les paiements
"""
import logging
from dataclasses import dataclass
from typing import Optional

from django.contrib.auth.models import User
from django.db import transaction
from django.db.models import Sum
from django.utils import timezone

from ..models import (
    Payment,
    Provider,
    Reservation,
)

logger = logging.getLogger(__name__)


@dataclass
class PaymentInput:
    """DTO pour un paiement."""
    method_id: str  # ESPECES, MOBILE_MONEY, CARTE
    reference: str
    amount: float
    message: str = ""


@dataclass
class PaymentResult:
    """Resultat d'une operation de paiement."""
    success: bool
    payment: Optional[Payment] = None
    error: Optional[str] = None


class PaymentService:
    """Service pour la gestion des paiements."""
    
    @staticmethod
    @transaction.atomic
    def create_post_payment(
        reservation: Reservation,
        user: User,
        input_data: PaymentInput,
    ) -> PaymentResult:
        """Enregistrer un paiement apres intervention.
        
        Args:
            reservation: Reservation liee
            user: Client effectuant le paiement
            input_data: Donnees du paiement
            
        Returns:
            PaymentResult avec succes/erreur
        """
        try:
            # Verifications
            if reservation.client_id != user.id:
                return PaymentResult(
                    success=False,
                    error="not_owner",
                )
            
            if reservation.statut != Reservation.Statut.TERMINEE:
                return PaymentResult(
                    success=False,
                    error="reservation_not_completed",
                )
            
            # Verifier qu'il n'y a pas deja un paiement
            existing = Payment.objects.filter(reservation=reservation).first()
            if existing:
                return PaymentResult(
                    success=False,
                    error="payment_already_exists",
                )
            
            # Mapper le type de paiement
            method = input_data.method_id
            if not method:
                method = "ESPECES"
            
            payment = Payment.objects.create(
                reservation=reservation,
                client=user,
                provider=reservation.provider,
                amount=input_data.amount,
                payment_method_id=method,
                payment_method=method,
                message=input_data.message[:500],
                statut=Payment.Statut.VALIDE,
                paid_at=timezone.now(),
            )
            
            logger.info(
                f"Paiement cree: {payment.id} for reservation {reservation.reference} "
                f"by user={user.id}"
            )
            
            return PaymentResult(
                success=True,
                payment=payment,
            )
            
        except Exception as e:
            logger.exception(f"Erreur paiement: {e}")
            return PaymentResult(
                success=False,
                error="payment_failed",
            )
    
    @staticmethod
    def get_provider_earnings(
        provider: Provider,
        date_from: Optional[timezone.datetime] = None,
        date_to: Optional[timezone.datetime] = None,
    ) -> dict:
        """Calculer les revenus d'un prestataire.
        
        Args:
            provider: Prestataire
            date_from: Date debut (optionnel)
            date_to: Date fin (optionnel)
            
        Returns:
            Dict avec total, par methode, par mois
        """
        qs = Payment.objects.filter(
            provider=provider,
            statut=Payment.Statut.VALIDE,
        )
        
        if date_from:
            qs = qs.filter(paid_at__gte=date_from)
        if date_to:
            qs = qs.filter(paid_at__lte=date_to)
        
        total = qs.aggregate(total=models.Sum("amount"))["total"] or 0
        
        # Par methode de paiement
        by_method = {}
        for method, label in Payment.METHODS:
            method_total = qs.filter(
                payment_method=method
            ).aggregate(t=models.Sum("amount"))["t"] or 0
            if method_total:
                by_method[method] = float(method_total)
        
        # Par mois (derniers 6 mois)
        by_month = {}
        # Note: en production, utiliser TruncMonth de Django
        for payment in qs.order_by("-paid_at")[:50]:
            month = payment.paid_at.strftime("%Y-%m")
            if month not in by_month:
                by_month[month] = 0
            by_month[month] += float(payment.amount)
        
        return {
            "total": float(total),
            "by_method": by_method,
            "by_month": by_month,
        }
    
    @staticmethod
    def get_client_payments(user: User, page: int = 1, page_size: int = 20) -> list:
        """Recuperer les paiements d'un client.
        
        Args:
            user: Utilisateur client
            page: Numero de page
            page_size: Taille de page
            
        Returns:
            Liste de paiements
        """
        start = (page - 1) * page_size
        end = start + page_size
        
        return list(Payment.objects.filter(
            client=user
        ).order_by("-paid_at")[start:end])
    
    @staticmethod
    def validate_payment_method(method_id: str) -> bool:
        """Valider un type de paiement.
        
        Args:
            method_id: ID du type de paiement
            
        Returns:
            True si valide
        """
        valid_methods = {"ESPECES", "MOBILE_MONEY", "CARTE", "ORANGE_MONEY", "MTN_MONEY"}
        return method_id.upper() in valid_methods or method_id in valid_methods