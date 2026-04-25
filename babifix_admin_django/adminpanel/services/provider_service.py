"""
Provider Service - Logique metier pour les prestataires
"""
import logging
from dataclasses import dataclass
from typing import Optional

from django.db.models import Avg, Count, Q
from django.contrib.auth.models import User

from ..models import (
    Category,
    Provider,
    Reservation,
    UserProfile,
)

logger = logging.getLogger(__name__)


@dataclass
class ProviderResult:
    """Resultat d'une operation sur prestataire."""
    success: bool
    provider: Optional[Provider] = None
    error: Optional[str] = None
    data: dict = None
    
    def __post_init__(self):
        if self.data is None:
            self.data = {}


@dataclass
class ProviderSearchInput:
    """DTO pour recherche de prestataires."""
    category_id: Optional[int] = None
    query: str = ""
    lat: Optional[float] = None
    lon: Optional[float] = None
    radius_km: float = 50.0
    page: int = 1
    page_size: int = 20
    sort_by: str = "rating"  # rating, distance, price


class ProviderService:
    """Service pour la gestion des prestataires."""
    
    @staticmethod
    def search_providers(input_data: ProviderSearchInput) -> list:
        """Rechercher des prestataires avec filtres.
        
        Args:
            input_data: Critères de recherche
            
        Returns:
            Liste de prestataires
        """
        qs = Provider.objects.filter(
            statut=Provider.Status.VALID,
            disponible=True,
        )
        
        # Filtrer par categorie
        if input_data.category_id:
            qs = qs.filter(categories__id=input_data.category_id)
        
        # Recherche textuelle
        if input_data.query:
            qs = qs.filter(
                Q(nom__icontains=input_data.query) |
                Q(description__icontains=input_data.query)
            )
        
        # Trier
        if input_data.sort_by == "rating":
            qs = qs.order_by("-note_moyenne", "-nombre_notes")
        elif input_data.sort_by == "price":
            qs = order_by("tarif_horaire")
        else:
            qs = qs.order_by("-note_moyenne")
        
        # Pagination
        start = (input_data.page - 1) * input_data.page_size
        end = start + input_data.page_size
        
        return list(qs[start:end])
    
    @staticmethod
    def get_provider_detail(provider_id: int) -> ProviderResult:
        """Recuperer le detail d'un prestataire.
        
        Args:
            provider_id: ID du prestataire
            
        Returns:
            ProviderResult avec le prestataire
        """
        provider = Provider.objects.filter(
            id=provider_id,
            statut=Provider.Status.VALID,
        ).first()
        
        if not provider:
            return ProviderResult(
                success=False,
                error="provider_not_found",
            )
        
        # Compter les reservations terminees
        completed = Reservation.objects.filter(
            provider=provider,
            statut=Reservation.Statut.TERMINEE,
        ).count()
        
        return ProviderResult(
            success=True,
            provider=provider,
            data={
                "completed_missions": completed,
            },
        )
    
    @staticmethod
    def check_availability(
        provider: Provider,
        date_str: Optional[str] = None,
    ) -> tuple[bool, str]:
        """Verifier la disponibilite d'un prestataire.
        
        Args:
            provider: Prestataire a verifier
            date_str: Date optionnelle (YYYY-MM-DD)
            
        Returns:
            (disponible, raison)
        """
        if not provider.disponible:
            return False, "provider_disabled"
        
        if provider.statut != Provider.Status.VALID:
            return False, "provider_not_approved"
        
        return True, ""
    
    @staticmethod
    def get_provider_stats(provider: Provider) -> dict:
        """Recuperer les statistiques d'un prestataire.
        
        Args:
            provider: Prestataire
            
        Returns:
            Dict avec stats
        """
        # Missions terminees
        completed = Reservation.objects.filter(
            provider=provider,
            statut=Reservation.Statut.TERMINEE,
        ).count()
        
        # En cours
        in_progress = Reservation.objects.filter(
            provider=provider,
            statut__in=[
                Reservation.Statut.INTERVENTION_EN_COURS,
                Reservation.Statut.EN_COURS,
            ],
        ).count()
        
        # Note moyenne
        avg = Provider.objects.filter(id=provider.id).aggregate(
            avg=Avg("note_moyenne")
        )["avg"] or 0
        
        return {
            "completed_missions": completed,
            "in_progress": in_progress,
            "rating": float(avg),
            "total_reviews": provider.nombre_notes,
        }
    
    @staticmethod
    def list_categories() -> list:
        """Lister toutes les categories actives.
        
        Returns:
            Liste de categories
        """
        return list(Category.objects.filter(
            active=True
        ).order_by("name"))