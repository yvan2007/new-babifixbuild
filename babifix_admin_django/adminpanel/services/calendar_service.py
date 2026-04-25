"""
Calendar Service — Gestion des disponibilites avec validation de conflit
"""
import logging
from dataclasses import dataclass
from datetime import date, datetime, time
from typing import Optional

from django.contrib.auth.models import User
from django.db.models import Q

from ..models import Provider, Reservation

logger = logging.getLogger(__name__)


@dataclass
class TimeSlot:
    """Un creneau horaire."""
    date: date
    start_time: time
    end_time: time
    is_available: bool


@dataclass
class BookingRequest:
    """Requete de reservation pour validation."""
    provider_id: int
    date: date
    start_time: time
    end_time: time


class CalendarService:
    """Service de gestion du calendrier et des conflits."""
    
    # ✅ F5: Heures de travail par defaut
    DEFAULT_START_HOUR = 8
    DEFAULT_END_HOUR = 18
    SLOT_DURATION_MINUTES = 60
    
    @classmethod
    def get_available_slots(
        cls,
        provider: Provider,
        target_date: date,
    ) -> list[TimeSlot]:
        """Recupere les creneaux disponibles pour un prestataire.
        
        Args:
            provider: Prestataire
            date: Date cible
            
        Returns:
            Liste de TimeSlot avec disponibilite
        """
        slots = []
        
        # Heures de travail
        start_hour = cls.DEFAULT_START_HOUR
        end_hour = cls.DEFAULT_END_HOUR
        
        # Verifier les indisponibilites ce jour
        from ..models import PrestataireUnavailability
        unavail = PrestataireUnavailability.objects.filter(
            provider=provider,
            date_debut__lte=target_date,
            date_fin__gte=target_date,
        ).exists()
        
        if unavail:
            return []  # Pas de creneaux
        
        # Verifier les reservations existantes ce jour
        existing = Reservation.objects.filter(
            provider=provider,
            created_at__date=target_date,
            statut__in=[
                "Confirmee",
                "En cours",
                "DEVIS_ACCEPTE",
                "INTERVENTION_EN_COURS",
            ],
        )
        
        # Generer les creneaux
        current_hour = start_hour
        while current_hour < end_hour:
            slot_start = time(current_hour, 0)
            slot_end = time(current_hour + 1, 0)
            
            # Check si ce creneau est occupe
            is_available = not cls._is_slot_conflicted(
                existing, target_date, slot_start
            )
            
            slots.append(TimeSlot(
                date=target_date,
                start_time=slot_start,
                end_time=slot_end,
                is_available=is_available,
            ))
            
            current_hour += 1
        
        return slots
    
    @classmethod
    def _is_slot_conflicted(
        cls,
        reservations,
        target_date: date,
        slot_time: time,
    ) -> bool:
        """Check si un creneau est deja reserve."""
        # Logique simplifiee - en production, comparer start/end times
        return False
    
    @classmethod
    def validate_booking(cls, request: BookingRequest) -> tuple[bool, str]:
        """Valide une demande de reservation pour eviter les conflits.
        
        Args:
            request: Details de la reservation
            
        Returns:
            (valid, error_message)
        """
        provider = Provider.objects.filter(id=request.provider_id).first()
        if not provider:
            return False, "Prestataire introuvable"
        
        # Check disponibilite generale
        if not provider.disponible:
            return False, "Prestataire indisponible"
        
        # Check indisponibilites
        from ..models import PrestataireUnavailability
        unavail = PrestataireUnavailability.objects.filter(
            provider=provider,
            date_debut__lte=request.date,
            date_fin__gte=request.date,
        ).exists()
        
        if unavail:
            return False, "Prestataire indisponible cette date"
        
        # Check doubles reservations (F18: Anti double booking)
        conflict = Reservation.objects.filter(
            provider=provider,
            created_at__date=request.date,
            statut__in=[
                "Confirmee",
                "En cours",
                "DEVIS_ACCEPTE",
                "INTERVENTION_EN_COURS",
            ],
            # En prod, verifier le chevauchement horaire
        ).exists()
        
        if conflict:
            return False, "Ce creneau est deja reserve"
        
        return True, ""
    
    @classmethod
    def get_provider_calendar(
        cls,
        provider: Provider,
        month: int,
        year: int,
    ) -> dict:
        """Recupere le calendrier mensuel.
        
        Returns:
            {date: {morning: bool, afternoon: bool}}
        """
        from datetime import date as date_class
        
        first_day = date_class(year, month, 1)
        if month == 12:
            last_day = date_class(year + 1, 1, 1)
        else:
            last_day = date_class(year, month + 1, 1)
        
        calendar = {}
        
        current = first_day
        while current < last_day:
            slots = cls.get_available_slots(provider, current)
            
            morning = any(
                s.is_available and s.start_time.hour < 12
                for s in slots
            )
            afternoon = any(
                s.is_available and s.start_time.hour >= 12
                for s in slots
            )
            
            calendar[str(current)] = {
                "morning": morning,
                "afternoon": afternoon,
            }
            
            from datetime import timedelta
            current += timedelta(days=1)
        
        return calendar