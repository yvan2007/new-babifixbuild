"""
Reservation Service - Logique metier pour les reservations
"""
import logging
from dataclasses import dataclass
from datetime import date
from typing import Optional

from django.contrib.auth.models import User
from django.db import transaction
from django.db.models import QuerySet
from django.utils import timezone

from ..models import (
    Categorie,
    Devis,
    Notification,
    Provider,
    Reservation,
    ReservationStatusHistory,
)

logger = logging.getLogger(__name__)


@dataclass
class CreateReservationInput:
    """DTO pour creation de reservation."""
    title: str
    category_id: int
    client_message: str = ""
    address_label: str = ""
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    provider_id: Optional[int] = None
    payment_type: str = "ESPECES"
    prix_propose: Optional[float] = None
    photo_attachments: list = None
    
    def __post_init__(self):
        if self.photo_attachments is None:
            self.photo_attachments = []


@dataclass
class ReservationResult:
    """Resultat d'une operation sur reservation."""
    success: bool
    reservation: Optional[Reservation] = None
    error: Optional[str] = None
    data: dict = None
    
    def __post_init__(self):
        if self.data is None:
            self.data = {}


class ReservationService:
    """Service pour la gestion des reservations."""
    
    TRANSITIONS = {
        "En attente": {"Confirmee", "Annulee"},
        "DEMANDE_ENVOYEE": {"DEVIS_EN_COURS", "Annulee"},
        "DEVIS_EN_COURS": {"DEVIS_ENVOYE", "Annulee"},
        "DEVIS_ENVOYE": {"DEVIS_ACCEPTE", "DEMANDE_ENVOYEE", "Annulee"},
        "DEVIS_ACCEPTE": {"INTERVENTION_EN_COURS", "Annulee"},
        "INTERVENTION_EN_COURS": {"En attente client", "Terminee", "Annulee"},
        "En attente client": {"Terminee", "Confirmee"},
        "Confirmee": {"En cours", "INTERVENTION_EN_COURS", "Annulee"},
        "En cours": {"En attente client", "Annulee"},
        "Terminee": {"Confirmee", "Annulee"},
    }
    
    @staticmethod
    @transaction.atomic
    def create_reservation(
        user: User,
        input_data: CreateReservationInput,
    ) -> ReservationResult:
        """Creer une nouvelle reservation.
        
        Args:
            user: Utilisateur client
            input_data: Donnees de la reservation
            
        Returns:
            ReservationResult avec la reservation cree ou erreur
        """
        try:
            # Validation de base
            if not input_data.title or not input_data.title.strip():
                return ReservationResult(
                    success=False,
                    error="title_required",
                )
            
            # Verifier la categorie
            category = Categorie.objects.filter(id=input_data.category_id).first()
            if not category:
                return ReservationResult(
                    success=False,
                    error="invalid_category",
                )
            
            # Verifier le prestataire si specifie
            provider = None
            if input_data.provider_id:
                provider = Provider.objects.filter(
                    id=input_data.provider_id,
                    statut=Provider.Status.VALID,
                ).first()
                if not provider:
                    return ReservationResult(
                        success=False,
                        error="provider_not_found",
                    )
                
                # Verifier disponibilite
                if not provider.disponible:
                    return ReservationResult(
                        success=False,
                        error="provider_unavailable",
                    )
                
                # Verifier periode d'indisponibilite
                from ..models import PrestataireUnavailability
                today = date.today()
                unavail = PrestataireUnavailability.objects.filter(
                    provider=provider,
                    date_debut__lte=today,
                    date_fin__gte=today,
                ).exists()
                if unavail:
                    return ReservationResult(
                        success=False,
                        error="provider_unavailable_today",
                    )
            
            # Generer reference
            ref_prefix = f"RES-{timezone.now().strftime('%Y%m%d')}"
            last_today = Reservation.objects.filter(
                reference__startswith=ref_prefix
            ).order_by("-reference").first()
            
            seq = 1
            if last_today:
                try:
                    seq = int(last_today.reference.split("-")[-1]) + 1
                except (ValueError, IndexError):
                    seq = 1
            
            reference = f"{ref_prefix}-{seq:04d}"
            
            # Mapper payment type
            payment_type_map = {
                "MOBILE_MONEY": Reservation.PaymentType.MOBILE_MONEY,
                "CARTE": Reservation.PaymentType.CARTE,
                "AUTRE": Reservation.PaymentType.AUTRE,
            }
            ptype = payment_type_map.get(
                input_data.payment_type.upper(),
                Reservation.PaymentType.ESPECES,
            )
            
            # Creer la reservation
            reservation = Reservation.objects.create(
                reference=reference,
                client=user,
                provider=provider,
                category=category,
                title=input_data.title.strip(),
                description=input_data.client_message[:2000],
                address_label=input_data.address_label[:500],
                latitude=input_data.latitude,
                longitude=input_data.longitude,
                payment_type=ptype,
                prix_propose=input_data.prix_propose,
                photo_attachments=input_data.photo_attachments[:6],
                statut=Reservation.Statut.EN_ATTENTE,
            )
            
            # Sauvegarder l'historique
            ReservationStatusHistory.objects.create(
                reservation=reservation,
                old_status="",
                new_status=Reservation.Statut.EN_ATTENTE,
                changed_by=user,
            )
            
            logger.info(f"Reservation creee: {reference} par user={user.id}")
            
            return ReservationResult(
                success=True,
                reservation=reservation,
                data={"reference": reference},
            )
            
        except Exception as e:
            logger.exception(f"Erreur creation reservation: {e}")
            return ReservationResult(
                success=False,
                error="creation_failed",
            )
    
    @staticmethod
    def get_client_reservations(
        user: User,
        status: Optional[str] = None,
        page: int = 1,
        page_size: int = 20,
    ) -> QuerySet:
        """Recuperer les reservations d'un client.
        
        Args:
            user: Utilisateur client
            status: Filtrer par statut (optionnel)
            page: Numero de page
            page_size: Taille de page
            
        Returns:
            QuerySet de reservations
        """
        qs = Reservation.objects.filter(client=user).order_by("-created_at")
        
        if status:
            qs = qs.filter(statut=status)
        
        start = (page - 1) * page_size
        end = start + page_size
        
        return qs[start:end]
    
    @staticmethod
    def transition_status(
        reservation: Reservation,
        new_status: str,
        user: User,
        reason: str = "",
    ) -> ReservationResult:
        """Changer le statut d'une reservation avec validation.
        
        Args:
            reservation: Reservation a modifier
            new_status: Nouveau statut cible
            user: Utilisateur effectuant le changement
            reason: Raison optionnelle
            
        Returns:
            ReservationResult avec succes/erreur
        """
        current = reservation.statut
        
        # Verifier la transition autorisee
        allowed = ReservationService.TRANSITIONS.get(current, set())
        if new_status not in allowed and new_status != "Annulee":
            return ReservationResult(
                success=False,
                error=f"invalid_transition_{current}_to_{new_status}",
            )
        
        # Appliquer le changement
        old_status = reservation.statut
        reservation.statut = new_status
        reservation.save(update_fields=["statut", "updated_at"])
        
        # Historiser
        ReservationStatusHistory.objects.create(
            reservation=reservation,
            old_status=old_status,
            new_status=new_status,
            changed_by=user,
            comment=reason[:500],
        )
        
        logger.info(
            f"Reservation {reservation.reference}: {old_status} -> {new_status} "
            f"par user={user.id}"
        )
        
        return ReservationResult(
            success=True,
            reservation=reservation,
            data={"old_status": old_status, "new_status": new_status},
        )
    
    @staticmethod
    def can_cancel(client: User, reservation: Reservation) -> tuple[bool, str]:
        """Verifier si un client peut annuler une reservation.
        
        Args:
            client: Utilisateur client
            reservation: Reservation a annuler
            
        Returns:
            (peut_annuler, raison)
        """
        if reservation.client_id != client.id:
            return False, "not_owner"
        
        # Annulation possible si pas terminee
        if reservation.statut in {
            Reservation.Statut.TERMINEE,
            "Annulee",
        }:
            return False, "already_finalized"
        
        return True, ""