"""
Provider Service - Logique metier pour les prestataires
"""
import logging
from dataclasses import dataclass
from typing import Optional

from django.db.models import Avg, Count, Q, Case, When, Value, IntegerField
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
    def search_providers(input_data: ProviderSearchInput) -> dict:
        """Rechercher des prestataires avec filtres."""
        qs = Provider.objects.filter(
            statut=Provider.Status.VALID,
            disponible=True,
        )

        if input_data.category_id:
            qs = qs.filter(category_id=input_data.category_id)

        if input_data.query:
            qs = qs.filter(
                Q(nom__icontains=input_data.query) |
                Q(bio__icontains=input_data.query) |
                Q(specialite__icontains=input_data.query)
            )

        # Rang premium : Gold (2) > Silver (1) > Standard (0) : mise en avant des abonnes
        qs = qs.annotate(
            premium_rank=Case(
                When(is_premium=True, premium_tier="gold", then=Value(2)),
                When(is_premium=True, premium_tier="silver", then=Value(1)),
                default=Value(0),
                output_field=IntegerField(),
            )
        )

        if input_data.sort_by == "price":
            qs = qs.order_by("-premium_rank", "tarif_horaire")
        else:
            qs = qs.order_by("-premium_rank", "-average_rating", "-rating_count")

        total = qs.count()
        start = (input_data.page - 1) * input_data.page_size
        end = start + input_data.page_size
        providers = list(qs[start:end])

        return {
            "providers": providers,
            "total": total,
            "page": input_data.page,
            "page_size": input_data.page_size,
            "has_next": end < total,
        }

    @staticmethod
    def get_provider_detail(provider_id: int) -> ProviderResult:
        """Recuperer le detail d'un prestataire."""
        provider = Provider.objects.filter(
            id=provider_id,
            statut=Provider.Status.VALID,
        ).first()

        if not provider:
            return ProviderResult(
                success=False,
                error="provider_not_found",
            )

        completed = Reservation.objects.filter(
            assigned_provider=provider,
            statut=Reservation.Status.DONE,
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
        """Verifier la disponibilite d'un prestataire."""
        if not provider.disponible:
            return False, "provider_disabled"

        if provider.statut != Provider.Status.VALID:
            return False, "provider_not_approved"

        return True, ""

    @staticmethod
    def get_provider_stats(provider: Provider) -> dict:
        """Recuperer les statistiques d'un prestataire."""
        completed = Reservation.objects.filter(
            assigned_provider=provider,
            statut=Reservation.Status.DONE,
        ).count()

        in_progress = Reservation.objects.filter(
            assigned_provider=provider,
            statut__in=[
                Reservation.Status.INTERVENTION_EN_COURS,
                Reservation.Status.IN_PROGRESS,
            ],
        ).count()

        pending_requests = Reservation.objects.filter(
            assigned_provider=provider,
            statut__in=[
                Reservation.Status.DEMANDE_ENVOYEE,
                Reservation.Status.PENDING,
            ],
        ).count()

        avg = Provider.objects.filter(id=provider.id).aggregate(
            avg=Avg("average_rating")
        )["avg"] or 0

        return {
            "completed_missions": completed,
            "in_progress": in_progress,
            "pending_requests": pending_requests,
            "rating": float(avg),
            "total_reviews": provider.rating_count,
        }

    @staticmethod
    def list_categories() -> list:
        """Lister toutes les categories actives."""
        return list(Category.objects.filter(
            actif=True,
            is_deleted=False,
        ).order_by("ordre_affichage", "nom"))
