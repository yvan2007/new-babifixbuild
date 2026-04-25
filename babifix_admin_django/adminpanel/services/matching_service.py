"""
Matching Service — Algorithme de scoring pour suggestion de prestataires
Criteres: proximity + rating + availability + specialty + price
"""
import logging
from dataclasses import dataclass
from typing import Optional

from django.db.models import Avg, Count
from django.contrib.auth.models import User

from ..models import Provider, Reservation, Category

logger = logging.getLogger(__name__)


@dataclass
class MatchingCriteria:
    """Criteria pour la recherche de prestataire."""
    category_id: int
    lat: Optional[float] = None
    lon: Optional[float] = None
    radius_km: float = 50.0
    price_max: Optional[float] = None
    required_skills: list = None
    
    def __post_init__(self):
        if self.required_skills is None:
            self.required_skills = []


@dataclass
class ProviderScore:
    """Score calcule pour un prestataire."""
    provider: Provider
    score: float
    distance_km: Optional[float]
    reasons: list  # Liste des raisons du score


def _haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calcule distance en km entre deux points (formule haversine)."""
    import math
    R = 6371  # Rayon Terre en km
    
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    
    a = math.sin(delta_phi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    
    return R * c


class MatchingService:
    """Service de matching intelligent des prestataires."""
    
    #ponderations des criteres (peuvent etre ajustees)
    WEIGHT_PROXIMITY = 0.35
    WEIGHT_RATING = 0.30
    WEIGHT_AVAILABILITY = 0.20
    WEIGHT_PRICE = 0.15
    
    @classmethod
    def recommend_providers(
        cls,
        criteria: MatchingCriteria,
        limit: int = 10,
    ) -> list[ProviderScore]:
        """
        Recommande les meilleurs prestataires pour une demande.
        
        Args:
            criteria: Criteres de recherche
            limit: Nombre de resultats
            
        Returns:
            Liste de ProviderScore tries par score decroissant
        """
        # Etape 1: Recuperer les prestataires valides pour cette categorie
        qs = Provider.objects.filter(
            statut=Provider.Status.VALID,
            disponible=True,
            categories__id=criteria.category_id,
        ).distinct()
        
        # Si pas de lat/lon, juste noter
        if criteria.lat is None or criteria.lon is None:
            results = []
            for p in qs[:limit * 2]:
                score = cls._calculate_rating_score(p)
                results.append(ProviderScore(
                    provider=p,
                    score=score,
                    distance_km=None,
                    reasons=["Note elevee"] if score > 4.0 else [],
                ))
            results.sort(key=lambda x: x.score, reverse=True)
            return results[:limit]
        
        # Etape 2: Calculer les scores
        scored = []
        for p in qs:
            # Distance
            dist = None
            if p.latitude and p.longitude:
                dist = _haversine_distance(
                    criteria.lat, criteria.lon,
                    p.latitude, p.longitude
                )
                if dist > criteria.radius_km:
                    continue  # Trop loin
            
            # Scores partiels
            score_prox = cls._calculate_proximity_score(dist, criteria.radius_km)
            score_rating = cls._calculate_rating_score(p)
            score_avail = cls._calculate_availability_score(p)
            score_price = cls._calculate_price_score(p, criteria.price_max)
            
            # Score total pondere
            total = (
                score_prox * cls.WEIGHT_PROXIMITY +
                score_rating * cls.WEIGHT_RATING +
                score_avail * cls.WEIGHT_AVAILABILITY +
                score_price * cls.WEIGHT_PRICE
            )
            
            # Reasons
            reasons = []
            if dist is not None and dist < 10:
                reasons.append(f"Proche ({int(dist)}km)")
            if p.note_moyenne >= 4.5:
                reasons.append(f"Bien note ({p.note_moyenne:.1f})")
            if p.disponible:
                reasons.append("Disponible")
            if criteria.price_max and p.tarif_horaire and p.tarif_horaire <= criteria.price_max:
                reasons.append("Tarif correct")
            
            scored.append(ProviderScore(
                provider=p,
                score=total,
                distance_km=dist,
                reasons=reasons,
            ))
        
        # Trier par score
        scored.sort(key=lambda x: x.score, reverse=True)
        
        return scored[:limit]
    
    @classmethod
    def _calculate_proximity_score(cls, distance_km: Optional[float], radius_km: float) -> float:
        """Score deproximite: 1 si tres proche, 0 si tres loin."""
        if distance_km is None:
            return 0.5  # Neutre si pas de position
        if distance_km <= 2:
            return 1.0
        if distance_km <= 5:
            return 0.8
        if distance_km <= 10:
            return 0.6
        if distance_km <= radius_km / 2:
            return 0.4
        return max(0, 1 - (distance_km / radius_km))
    
    @classmethod
    def _calculate_rating_score(cls, provider: Provider) -> float:
        """Score based on rating: note 5 = 1.0, note 0 = 0.0."""
        note = provider.note_moyenne or 0
        if note >= 4.5:
            return 1.0
        elif note >= 4.0:
            return 0.8
        elif note >= 3.5:
            return 0.6
        elif note >= 3.0:
            return 0.4
        elif note >= 2.0:
            return 0.2
        return 0.1
    
    @classmethod
    def _calculate_availability_score(cls, provider: Provider) -> float:
        """Score based on availability."""
        # Verifier les disponibilites enregistrees
        from ..models import PrestataireDispo
        from datetime import date as date_module
        today = date_module.today()
        
        dispatches = PrestataireDispo.objects.filter(
            provider=provider,
            date_debut__lte=today,
            date_fin__gte=today,
            estDisponible=True,
        ).exists()
        
        if dispatches:
            return 1.0
        
        # Sinon score base sur le flag disponible
        return 1.0 if provider.disponible else 0.0
    
    @classmethod
    def _calculate_price_score(cls, provider: Provider, price_max: Optional[float]) -> float:
        """Score based on price (less cher =plus haut)."""
        if price_max is None:
            return 0.5  # Neutre
        
        tarif = provider.tarif_horaire
        if tarif is None or tarif <= 0:
            return 0.5
        
        if tarif <= price_max * 0.7:
            return 1.0
        elif tarif <= price_max:
            return 0.7
        elif tarif <= price_max * 1.3:
            return 0.4
        return 0.1
    
    @classmethod
    def get_top_provider(
        cls,
        category_id: int,
        lat: float,
        lon: float,
    ) -> Optional[Provider]:
        """Get le meilleur prestataire pour une categorie et position."""
        criteria = MatchingCriteria(
            category_id=category_id,
            lat=lat,
            lon=lon,
            radius_km=30.0,
        )
        results = cls.recommend_providers(criteria, limit=1)
        return results[0].provider if results else None