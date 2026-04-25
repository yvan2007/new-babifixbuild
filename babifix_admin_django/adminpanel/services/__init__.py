# Services layer BABIFIX
#
# Separe la logique metier des views pour:
# - Meilleure testabilite (unittest/pytest)
# - Reutilisation entre endpoints
# - Separation of concerns
#
# Usage:
#   from adminpanel.services import ReservationService
#   result = ReservationService.create_reservation(...)

from .reservation_service import ReservationService
from .payment_service import PaymentService
from .provider_service import ProviderService
from .notification_service import NotificationService
from .matching_service import MatchingService, MatchingCriteria
from .dispute_service import DisputeService
from .media_upload_service import MediaUploadService
from .provider_subscription_service import ProviderSubscriptionService
from .analytics_service import AnalyticsService
from .invoice_service import InvoiceService
from .calendar_service import CalendarService
from .referral_service import ReferralService, get_category_commission, calculate_agent_commission
from .extra_services import ZEGOCLOUDService, GPSTrackingService, OfflineModeService
from .extra_service2 import PIIFilter, StructuredLogger, FullTextSearch, KYCService, SLAService
from .seo_service import SEOService
from .geofencing_service import GeofencingService

__all__ = [
    "ReservationService",
    "PaymentService",
    "ProviderService",
    "NotificationService",
    "MatchingService",
    "MatchingCriteria",
    "DisputeService",
    "MediaUploadService",
    "ProviderSubscriptionService",
    "AnalyticsService",
    "InvoiceService",
    "CalendarService",
    "ReferralService",
    "get_category_commission",
    "calculate_agent_commission",
    "ZEGOCLOUDService",
    "GPSTrackingService",
    "OfflineModeService",
    "PIIFilter",
    "StructuredLogger",
    "FullTextSearch",
    "KYCService",
    "SLAService",
    "SEOService",
    "GeofencingService",
]