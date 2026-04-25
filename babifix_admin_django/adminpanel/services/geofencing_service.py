"""
Geofencing Service — Notifications basees sur la position
"""
import logging
from dataclasses import dataclass
from typing import Optional

logger = logging.getLogger(__name__)


@dataclass
class GeoNotification:
    """Notification geofence."""
    title: str
    message: str
    type: str  # provider_arriving, nearby, etc.
    latitude: float
    longitude: float
    radius_km: float


class GeofencingService:
    """Service de notifications geofencing.
    
    ✅ F19: Notifications basees sur la position
    """
    
    # Rayons de notification (en km)
    RADIUS_NEARBY = 5.0   # Prestataire aproximite
    RADIUS_ARRIVING = 1.0  # Prestataire arrive
    
    @classmethod
    def check_nearby_providers(
        cls,
        client_lat: float,
        client_lon: float,
        category_id: int = None,
    ) -> list:
        """Trouve les prestataires a proximite.
        
        Args:
            client_lat: Latitude client
            client_lon: Longitude client
            category_id: Filtrer par categorie
            
        Returns:
            Liste de prestataires a proximity
        """
        from ..models import Provider
        from django.db.models import Q
        import math
        
        providers = Provider.objects.filter(
            statut=Provider.Status.VALID,
            disponible=True,
            is_deleted=False,
            latitude__isnull=False,
            longitude__isnull=False,
        )
        
        if category_id:
            providers = providers.filter(categories__id=category_id)
        
        nearby = []
        for p in providers:
            dist = cls._haversine_distance(
                client_lat, client_lon,
                p.latitude, p.longitude
            )
            
            if dist <= cls.RADIUS_NEARBY:
                nearby.append({
                    "provider_id": p.id,
                    "name": p.nom,
                    "distance_km": round(dist, 1),
                    "eta_minutes": int(dist / 0.4),  # ~25km/h average
                })
        
        # Trier par distance
        nearby.sort(key=lambda x: x["distance_km"])
        
        return nearby[:10]
    
    @classmethod
    def _haversine_distance(cls, lat1, lon1, lat2, lon2) -> float:
        """Calcule distance en km entre deux points."""
        import math
        R = 6371
        
        dlat = math.radians(lat2 - lat1)
        dlon = math.radians(lon2 - lon1)
        a = math.sin(dlat/2)**2 + math.cos(math.radians(lat1)) * \
            math.cos(math.radians(lat2)) * math.sin(dlon/2)**2
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
        
        return R * c
    
    @classmethod
    def notify_arrival(
        cls,
        provider,
        client,
        distance_km: float,
    ) -> None:
        """Notifie le client quand le prestataire arrive.
        
        Args:
            provider: Prestataire
            client: Client
            distance_km: Distance actuelle
        """
        from .notification_service import NotificationService
        
        message = f"{provider.nom} est a {distance_km:.1f}km de chez vous"
        
        NotificationService.create_notification(
            NotificationService.NotificationInput(
                user=client,
                title="Prestataire arrive",
                message=message,
                type="INFO",
                link=f"/tracking/{provider.id}",
            )
        )
    
    @classmethod
    def get_geo_alerts(cls, user_id: int) -> list:
        """Recupere les alertes geographiques pour un utilisateur.
        
        Args:
            user_id: ID utilisateur
            
        Returns:
            Liste d'alertes actives
        """
        # Placeholder - en prod, lire depuis Redis avec geofence keys
        return []