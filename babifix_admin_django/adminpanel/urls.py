from django.urls import path

from .cinetpay import cinetpay_initiate, cinetpay_status, cinetpay_webhook
from .views_extra import (
    api_admin_audit_log,
    api_admin_bulk_provider_action,
    api_admin_export_csv,
    api_client_favorites,
    api_client_payments,
    api_health_check,
    api_prestataire_availability,
    api_prestataire_availability_crud,
    api_prestataire_disputes,
    api_prestataire_stats,
    api_prestataire_unavailability_crud,
)
from .views_v2 import (
    api_admin_push_broadcast,
    api_auth_forgot_password,
    api_auth_refresh_token,
    api_auth_reset_password,
    api_auth_verify_email,
    api_client_cancel_reservation,
    api_client_open_dispute,
    api_client_reservation_detail,
    api_client_reservations_list,
    api_prestataire_portfolio,
    api_prestataire_portfolio_delete,
    api_prestataire_profile_update,
    api_prestataire_rate_client,
    api_provider_portfolio_public,
    api_user_notifications,
    api_user_notifications_mark_read,
)
from .views import (
    export_dashboard_csv,
    api_admin_validate_cash,
    api_auth_apple,
    api_auth_fcm_token,
    api_auth_google,
    api_auth_login,
    api_auth_me,
    api_auth_register,
    api_client_accept_devis,
    api_client_annuler_demande,
    api_client_check_provider_availability,
    api_client_confirmer_travaux,
    api_client_conversations,
    api_client_create_reservation,
    api_client_declare_cash,
    api_client_demandes_list,
    api_client_home,
    api_client_actualites,
    api_client_actualite_detail,
    api_client_confirm_prestation,
    api_client_message_delete,
    api_client_pay_post_prestation,
    api_client_prestataires,
    api_client_rate_reservation,
    api_client_refuse_devis,
    api_messages,
    api_messages_unread_total,
    api_prestataire_accept_demande,
    api_prestataire_confirm_cash,
    api_prestataire_conversations,
    api_prestataire_create_devis,
    api_prestataire_decide_request,
    api_prestataire_demarrer_intervention,
    api_prestataire_earnings,
    api_prestataire_me,
    api_prestataire_ratings,
    api_prestataire_refuse_demande,
    api_prestataire_register,
    api_prestataire_requests,
    api_prestataire_reservation_status,
    api_prestataire_terminer_intervention,
    api_public_categories,
    api_public_payment_methods,
    api_public_providers,
    api_public_vitrine,
    api_reservation_devis,
    dashboard,
)

urlpatterns = [
    path("export/csv/<str:kind>/", export_dashboard_csv, name="admin-export-csv"),
    path("", dashboard, name="admin-dashboard"),
    path("api/public/vitrine/", api_public_vitrine, name="api-public-vitrine"),
    path("api/public/categories/", api_public_categories, name="api-public-categories"),
    path("api/public/providers/", api_public_providers, name="api-public-providers"),
    path(
        "api/public/payment-methods/",
        api_public_payment_methods,
        name="api-public-payment-methods",
    ),
    path("api/auth/login/", api_auth_login, name="api-auth-login"),
    path("api/auth/register", api_auth_register, name="api-auth-register"),
    path("api/auth/me", api_auth_me, name="api-auth-me"),
    path("api/auth/fcm-token", api_auth_fcm_token, name="api-auth-fcm-token"),
    path("api/auth/google", api_auth_google, name="api-auth-google"),
    path("api/auth/apple", api_auth_apple, name="api-auth-apple"),
    path("api/client/home", api_client_home, name="api-client-home"),
    path("api/client/actualites", api_client_actualites, name="api-client-actualites"),
    path(
        "api/client/actualites/<int:pk>",
        api_client_actualite_detail,
        name="api-client-actualite-detail",
    ),
    path(
        "api/client/prestataires",
        api_client_prestataires,
        name="api-client-prestataires",
    ),
    path(
        "api/client/conversations",
        api_client_conversations,
        name="api-client-conversations",
    ),
    path(
        "api/client/reservations",
        api_client_create_reservation,
        name="api-client-reservations-create",
    ),
    path(
        "api/client/reservations/<str:reference>/rating",
        api_client_rate_reservation,
        name="api-client-reservation-rating",
    ),
    path(
        "api/client/reservations/<str:reference>/cash-declare",
        api_client_declare_cash,
        name="api-client-cash-declare",
    ),
    path(
        "api/client/reservations/<str:reference>/confirm-prestation",
        api_client_confirm_prestation,
        name="api-client-confirm-prestation",
    ),
    path(
        "api/client/reservations/<str:reference>/pay-post-prestation",
        api_client_pay_post_prestation,
        name="api-client-pay-post-prestation",
    ),
    path("api/messages", api_messages, name="api-messages"),
    path(
        "api/messages/<int:message_id>/delete",
        api_client_message_delete,
        name="api-message-delete",
    ),
    path(
        "api/messages/unread-total",
        api_messages_unread_total,
        name="api-messages-unread-total",
    ),
    path(
        "api/prestataire/register",
        api_prestataire_register,
        name="api-prestataire-register",
    ),
    path(
        "api/prestataire/requests",
        api_prestataire_requests,
        name="api-prestataire-requests",
    ),
    path(
        "api/prestataire/requests/<str:reference>/decision",
        api_prestataire_decide_request,
        name="api-prestataire-decision",
    ),
    path(
        "api/prestataire/requests/<str:reference>/status",
        api_prestataire_reservation_status,
        name="api-prestataire-reservation-status",
    ),
    path(
        "api/prestataire/requests/<str:reference>/cash-confirm",
        api_prestataire_confirm_cash,
        name="api-prestataire-cash-confirm",
    ),
    path(
        "api/admin/reservations/<str:reference>/cash-validate",
        api_admin_validate_cash,
        name="api-admin-cash-validate",
    ),
    path(
        "api/prestataire/earnings",
        api_prestataire_earnings,
        name="api-prestataire-earnings",
    ),
    path(
        "api/prestataire/ratings",
        api_prestataire_ratings,
        name="api-prestataire-ratings",
    ),
    path("api/prestataire/me", api_prestataire_me, name="api-prestataire-me"),
    path(
        "api/prestataire/conversations",
        api_prestataire_conversations,
        name="api-prestataire-conversations",
    ),
    # ── Disponibilité prestataire ────────────────────────────────────────────
    path(
        "api/prestataire/availability/",
        api_prestataire_availability,
        name="api-prestataire-availability",
    ),
    path(
        "api/prestataire/availability/slots/",
        api_prestataire_availability_crud,
        name="api-prestataire-availability-crud",
    ),
    path(
        "api/prestataire/unavailability/",
        api_prestataire_unavailability_crud,
        name="api-prestataire-unavailability-crud",
    ),
    path("api/prestataire/stats/", api_prestataire_stats, name="api-prestataire-stats"),
    # ── CinetPay Mobile Money ────────────────────────────────────────────────
    path(
        "api/paiements/cinetpay/initiate/", cinetpay_initiate, name="cinetpay-initiate"
    ),
    path(
        "api/paiements/cinetpay/status/<str:transaction_id>/",
        cinetpay_status,
        name="cinetpay-status",
    ),
    path("api/paiements/cinetpay/webhook/", cinetpay_webhook, name="cinetpay-webhook"),
    # ── Admin — Actions bulk, audit log, export CSV ──────────────────────────
    path(
        "api/admin/prestataires/bulk-action/",
        api_admin_bulk_provider_action,
        name="admin-bulk-action",
    ),
    path("api/admin/audit-log/", api_admin_audit_log, name="admin-audit-log"),
    path("api/admin/export/<str:kind>/", api_admin_export_csv, name="admin-export-csv"),
    # ── v2 — Historique réservations client ──────────────────────────────────
    path(
        "api/client/reservations/list",
        api_client_reservations_list,
        name="api-client-reservations-list",
    ),
    path(
        "api/client/reservations/<str:reference>/detail",
        api_client_reservation_detail,
        name="api-client-reservation-detail",
    ),
    path(
        "api/client/reservations/<str:reference>/cancel",
        api_client_cancel_reservation,
        name="api-client-reservation-cancel",
    ),
    path(
        "api/client/reservations/<str:reference>/dispute",
        api_client_open_dispute,
        name="api-client-reservation-dispute",
    ),
    # ── v2 — Auth : reset mot de passe + refresh token + vérif email ─────────
    path(
        "api/auth/forgot-password",
        api_auth_forgot_password,
        name="api-auth-forgot-password",
    ),
    path(
        "api/auth/reset-password",
        api_auth_reset_password,
        name="api-auth-reset-password",
    ),
    path("api/auth/refresh", api_auth_refresh_token, name="api-auth-refresh"),
    path("api/health/", api_health_check, name="api-health-check"),
    path(
        "api/auth/verify-email/<str:token>",
        api_auth_verify_email,
        name="api-auth-verify-email",
    ),
    # ── v2 — Profil + Portfolio prestataire ──────────────────────────────────
    path(
        "api/prestataire/profile",
        api_prestataire_profile_update,
        name="api-prestataire-profile-update",
    ),
    path(
        "api/prestataire/portfolio",
        api_prestataire_portfolio,
        name="api-prestataire-portfolio",
    ),
    path(
        "api/prestataire/portfolio/<int:idx>",
        api_prestataire_portfolio_delete,
        name="api-prestataire-portfolio-delete",
    ),
    path(
        "api/prestataire/reservations/<str:reference>/rate-client",
        api_prestataire_rate_client,
        name="api-prestataire-rate-client",
    ),
    # ── v2 — Notifications persistantes ──────────────────────────────────────
    path("api/notifications", api_user_notifications, name="api-user-notifications"),
    path(
        "api/notifications/mark-read",
        api_user_notifications_mark_read,
        name="api-user-notifications-mark-read",
    ),
    # ── v2 — Portfolio public prestataire ────────────────────────────────────
    path(
        "api/client/prestataires/<int:provider_id>/portfolio",
        api_provider_portfolio_public,
        name="api-provider-portfolio-public",
    ),
    # ── v2 — Admin push broadcast ────────────────────────────────────────────
    path(
        "api/admin/push-broadcast",
        api_admin_push_broadcast,
        name="api-admin-push-broadcast",
    ),
    # ── Favoris, Paiements, Litiges ───────────────────────────────────────────
    path("api/client/favorites/", api_client_favorites, name="api-client-favorites"),
    path("api/client/payments/", api_client_payments, name="api-client-payments"),
    path(
        "api/prestataire/disputes/",
        api_prestataire_disputes,
        name="api-prestataire-disputes",
    ),
    # ── Devis ─────────────────────────────────────────────────────────────────
    path(
        "api/prestataire/requests/<str:reference>/devis",
        api_prestataire_create_devis,
        name="api-prestataire-create-devis",
    ),
    path(
        "api/client/reservations/<str:reference>/devis",
        api_reservation_devis,
        name="api-reservation-devis",
    ),
    path(
        "api/client/reservations/<str:reference>/devis/accept",
        api_client_accept_devis,
        name="api-client-accept-devis",
    ),
    path(
        "api/client/reservations/<str:reference>/devis/refuse",
        api_client_refuse_devis,
        name="api-client-refuse-devis",
    ),
    # ── Demandes et intervention ───────────────────────────────────────────────
    # Prestataire
    path(
        "api/prestataire/requests/<str:reference>/accept",
        api_prestataire_accept_demande,
        name="api-prestataire-accept-demande",
    ),
    path(
        "api/prestataire/requests/<str:reference>/refuse",
        api_prestataire_refuse_demande,
        name="api-prestataire-refuse-demande",
    ),
    path(
        "api/prestataire/requests/<str:reference>/demarrer",
        api_prestataire_demarrer_intervention,
        name="api-prestataire-demarrer-intervention",
    ),
    path(
        "api/prestataire/requests/<str:reference>/terminer",
        api_prestataire_terminer_intervention,
        name="api-prestataire-terminer-intervention",
    ),
    # Client
    path(
        "api/client/demandes/",
        api_client_demandes_list,
        name="api-client-demandes-list",
    ),
    path(
        "api/client/demandes/<str:reference>/confirmer-travaux",
        api_client_confirmer_travaux,
        name="api-client-confirmer-travaux",
    ),
    path(
        "api/client/demandes/<str:reference>/annuler",
        api_client_annuler_demande,
        name="api-client-annuler-demande",
    ),
    # ── Disponibilité ─────────────────────────────────────────────────────────
    path(
        "api/client/check-provider-availability",
        api_client_check_provider_availability,
        name="api-client-check-provider-availability",
    ),
]
