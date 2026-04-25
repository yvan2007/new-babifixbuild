"""
Analytics Service — Tracking et analytics pour BABIFIX
Integration Mixpanel/PostHog pour mesurer les KPIs
"""
import logging
from dataclasses import dataclass, field
from typing import Any, Optional
from datetime import datetime, timedelta

from django.contrib.auth.models import User
from django.db.models import Count, Sum, Avg

logger = logging.getLogger(__name__)


# ✅ M5: Configuration analytics
ANALYTICS_PROVIDER = "mixpanel"  # ou "posthog", "none"


@dataclass
class AnalyticsEvent:
    """Un evenement analytique."""
    event: str
    user_id: Optional[int]
    properties: dict = field(default_factory=dict)
    timestamp: datetime = None
    
    def __post_init__(self):
        if self.timestamp is None:
            self.timestamp = datetime.utcnow()


class AnalyticsService:
    """Service d'analytics pour BabyFix.
    
    Utilise un provider externe (Mixpanel/PostHog) si configure,
    sinon utilise les donnees Django en interne.
    """
    
    @classmethod
    def track(cls, event: str, user_id: Optional[int] = None, **properties) -> None:
        """
        Track un evenement.
        
        Args:
            event: Nom de l'evenement
            user_id: ID utilisateur (optionnel)
            **properties: Proprietes additionnelles
        """
        # En local d'abord
        cls._track_local(event, user_id, properties)
        
        # Puis vers provider externe si configure
        if ANALYTICS_PROVIDER != "none":
            cls._track_external(event, user_id, properties)
    
    @classmethod
    def _track_local(cls, event: str, user_id: Optional[int], props: dict) -> None:
        """Stocke localement (fallback)."""
        # En production, ecrire dans un model ou Redis
        logger.debug(f"[Analytics] {event} by user={user_id}: {props}")
    
    @classmethod
    def _track_external(cls, event: str, user_id: Optional[int], props: dict) -> None:
        """Envoie vers Mixpanel/PostHog."""
        if ANALYTICS_PROVIDER == "mixpanel":
            cls._track_mixpanel(event, user_id, props)
        elif ANALYTICS_PROVIDER == "posthog":
            cls._track_posthog(event, user_id, props)
    
    @classmethod
    def _track_mixpanel(cls, event: str, user_id: Optional[int], props: dict) -> None:
        """Envoie vers Mixpanel."""
        try:
            from mixpanel import Mixpanel
            mp = Mixpanel("YOUR_TOKEN")
            mp.track(user_id or "anonymous", event, props)
        except Exception as e:
            logger.warning(f"Mixpanel error: {e}")
    
    @classmethod
    def _track_posthog(cls, event: str, user_id: Optional[int], props: dict) -> None:
        """Envoie vers PostHog."""
        try:
            # from posthog import PostHog
            # ph = PostHog("YOUR_KEY", host="https://app.posthog.com")
            # ph.capture(user_id or "anonymous", event, properties=props)
            pass
        except Exception as e:
            logger.warning(f"PostHog error: {e}")
    
    # ---------------------------------------------------------------------------
    # Evenements courants
    # ---------------------------------------------------------------------------
    
    @classmethod
    def track_registration(cls, user_id: int, role: str) -> None:
        """Track inscription utilisateur."""
        cls.track("user.registered", user_id, role=role)
    
    @classmethod
    def track_reservation_created(cls, user_id: int, reference: str) -> None:
        """Track creation reservation."""
        cls.track("reservation.created", user_id, reference=reference)
    
    @classmethod
    def track_devis_accepted(cls, provider_id: int, reference: str) -> None:
        """Track acceptation devis."""
        cls.track("devis.accepted", provider_id, reference=reference)
    
    @classmethod
    def track_payment(cls, user_id: int, amount: float, method: str) -> None:
        """Track paiement."""
        cls.track("payment.completed", user_id, amount=amount, method=method)
    
    @classmethod
    def track_login(cls, user_id: int) -> None:
        """Track connexion."""
        cls.track("user.login", user_id)
    
    @classmethod
    def track_search(cls, user_id: int, query: str, results_count: int) -> None:
        """Track recherche prestataire."""
        cls.track("provider.searched", user_id, query=query, results=results_count)
    
    # ---------------------------------------------------------------------------
    # KPIs calcules localement (sans provider externe)
    # ---------------------------------------------------------------------------
    
    @classmethod
    def get_dashboard_stats(cls, days: int = 30) -> dict:
        """KPIs dashboard (30 derniers jours par defaut).
        
        Returns:
            Dict avec: reservations_total, reservations_active, payments_total,
                   providers_active, users_new, conversion_rate
        """
        from ..models import Reservation, Payment, Provider, UserProfile
        from django.utils import timezone
        
        threshold = timezone.now() - timedelta(days=days)
        
        # Reservations
        total = Reservation.objects.filter(created_at__gte=threshold).count()
        active = Reservation.objects.exclude(
            statut__in=["Annulee", "Terminee"]
        ).count()
        
        # Paiements
        payments = Payment.objects.filter(
            paid_at__gte=threshold,
            etat=Payment.State.COMPLETE,
        ).aggregate(total=Sum("amount"))["total"] or 0
        
        # Providers
        providers = Provider.objects.filter(
            statut=Provider.Status.VALID,
            is_deleted=False,
        ).count()
        
        # Nouveaux utilisateurs
        new_users = UserProfile.objects.filter(
            created_at__gte=threshold,
        ).count()
        
        # Taux conversion (reservations terminees / reservations creees)
        completed = Reservation.objects.filter(
            created_at__gte=threshold,
            statut="Terminee",
        ).count()
        conversion = (completed / total * 100) if total > 0 else 0
        
        return {
            "period_days": days,
            "reservations_total": total,
            "reservations_active": active,
            "payments_total": float(payments),
            "providers_active": providers,
            "users_new": new_users,
            "conversion_rate_pct": round(conversion, 1),
        }
    
    @classmethod
    def get_revenue_by_day(cls, days: int = 30) -> list[dict]:
        """Revenus journaliers.
        
        Returns:
            Liste de {date, revenue}
        """
        from ..models import Payment
        from django.utils import timezone
        
        threshold = timezone.now() - timedelta(days=days)
        
        payments = Payment.objects.filter(
            paid_at__gte=threshold,
            etat=Payment.State.COMPLETE,
        ).values("paid_at__date").annotate(
            revenue=Sum("amount")
        ).order_by("paid_at__date")
        
        return [
            {
                "date": str(p["paid_at__date"]),
                "revenue": float(p["revenue"] or 0),
            }
            for p in payments
        ]
    
    @classmethod
    def get_top_categories(cls, limit: int = 10) -> list[dict]:
        """Categories les plus demandees.
        
        Returns:
            Liste de {category, count}
        """
        from ..models import Reservation, Category
        
        top = Reservation.objects.values(
            "category__name"
        ).annotate(
            count=Count("id")
        ).order_by("-count")[:limit]
        
        return [
            {
                "category": p["category__name"] or "Inconnu",
                "count": p["count"],
            }
            for p in top
        ]