from django.urls import path

from .geniuspay import (
    geniuspay_initiate,
    geniuspay_premium_initiate,
    geniuspay_status,
    geniuspay_webhook,
)
from . import views_calls as _calls_views
from .views_b2b import (
    api_pro_formules,
    api_pro_account,
    api_pro_sites,
    api_pro_declare_intervention,
    api_pro_invoice,
)
from .views_finance import (
    api_referral,
    api_premium_tiers,
    api_premium_subscribe,
    api_premium_calculator,
    api_admin_business_kpis,
    kpi_dashboard_page,
    api_client_fidelite,
    api_rating_voice_upload,
    api_admin_platform_revenue,
    api_admin_validate_withdrawal,
    api_client_devis_compare,
    api_urgence_preview,
)
from .views_extra import (
    api_reservation_paiement_acompte,
    api_reservation_paiement_solde,
    api_run_reminders,
)
from .views_extra import (
    api_admin_audit_log,
    api_admin_bulk_provider_action,
    api_admin_export_csv,
    api_client_disputes,
    api_client_favorites,
    api_client_fidelite,
    api_client_invoice_pdf,
    api_client_invoices_list,
    api_client_payments,
    api_health_check,
    api_prestataire_availability,
    api_prestataire_availability_crud,
    api_prestataire_contrat,
    api_prestataire_contrat_sign,
    api_prestataire_disputes,
    api_prestataire_invoice_pdf,
    api_prestataire_kyc_status,
    api_prestataire_kyc_submit,
    api_prestataire_payments_history,
    api_prestataire_ratings,
    api_prestataire_respond_dispute,
    api_prestataire_stats,
    api_prestataire_unavailability_crud,
    api_prestataire_wallet,
    api_prestataire_wallet_withdraw,
    api_prestataire_wallet_update_info,
)
from .views_v2 import (
    api_admin_push_broadcast,
    api_app_log_error,
    api_app_version,
    api_auth_delete_account,
    api_auth_forgot_password,
    api_auth_refresh_token,
    api_auth_reset_password,
    api_auth_verify_email,
    api_client_cancel_reservation,
    api_client_journal,
    api_client_open_dispute,
    api_client_reservation_detail,
    api_client_reservations_list,
    api_payment_quote,
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
    api_admin_financial_summary,
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
    api_client_pay_deposit,
    api_client_pay_remainder,
    api_client_create_reservation,
    api_client_declare_cash,
    api_client_demandes_list,
    api_client_home,
    api_client_actualites,
    api_client_actualite_detail,
    api_public_actualites,
    api_public_actualite_detail,
    api_client_confirm_prestation,
    api_client_message_delete,
    api_client_pay_post_prestation,
    api_client_prestataires,
    api_client_prestataire_detail,
    api_client_rate_reservation,
    api_client_refuse_devis,
    api_messages,
    api_messages_by_reservation,
    api_messages_send_by_reservation,
    api_messages_unread_total,
    api_prestataire_accept_demande,
    api_prestataire_confirm_cash,
    api_prestataire_conversations,
    api_prestataire_create_devis,
    api_client_saved_addresses,
    api_prestataire_decide_request,
    api_prestataire_location_update,
    api_prestataire_demarrer_intervention,
    api_prestataire_earnings,
    api_prestataire_me,
    api_prestataire_ratings,
    api_prestataire_refuse_demande,
    api_prestataire_register,
    api_prestataire_requests,
    api_prestataire_reservation_status,
    api_prestataire_terminer_intervention,
    api_prestataire_upload_photos,
    api_public_categories,
    api_public_metiers,
    api_public_payment_methods,
    api_public_providers,
    api_public_provider_availability,
    api_public_vitrine,
    api_reservation_devis,
    api_admin_reservation_move,
    api_admin_reservation_status,
    dashboard,
)

urlpatterns = [
    path("export/csv/<str:kind>/", export_dashboard_csv, name="admin-export-csv"),
    path("", dashboard, name="admin-dashboard"),
    path("api/public/vitrine/", api_public_vitrine, name="api-public-vitrine"),
    path("api/public/categories/", api_public_categories, name="api-public-categories"),
    path("api/public/metiers/", api_public_metiers, name="api-public-metiers"),
    path("api/public/providers/", api_public_providers, name="api-public-providers"),
    path(
        "api/public/providers/<int:provider_id>/availability/",
        api_public_provider_availability,
        name="api-public-provider-availability",
    ),
    path(
        "api/public/payment-methods/",
        api_public_payment_methods,
        name="api-public-payment-methods",
    ),
    path("api/auth/login", api_auth_login, name="api-auth-login"),
    path("api/auth/login/", api_auth_login, name="api-auth-login-slash"),
    path("api/auth/register", api_auth_register, name="api-auth-register"),
    path("api/auth/register/", api_auth_register, name="api-auth-register-slash"),
    path("api/auth/me", api_auth_me, name="api-auth-me"),
    path("api/auth/me/", api_auth_me, name="api-auth-me-slash"),
    path("api/auth/fcm-token", api_auth_fcm_token, name="api-auth-fcm-token"),
    path("api/auth/fcm-token/", api_auth_fcm_token, name="api-auth-fcm-token-slash"),
    path("api/auth/google", api_auth_google, name="api-auth-google"),
    path("api/auth/google/", api_auth_google, name="api-auth-google-slash"),
    path("api/auth/apple", api_auth_apple, name="api-auth-apple"),
    path("api/auth/apple/", api_auth_apple, name="api-auth-apple-slash"),
    path("api/client/home", api_client_home, name="api-client-home"),
    path("api/client/actualites", api_client_actualites, name="api-client-actualites"),
    # Variante publique (sans auth) — voir les actus de cible 'tous' depuis
    # l'écran d'accueil "À la une" même en mode visiteur.
    path("api/public/actualites", api_public_actualites, name="api-public-actualites"),
    path(
        "api/public/actualites/<int:pk>",
        api_public_actualite_detail,
        name="api-public-actualite-detail",
    ),
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
        "api/client/prestataires/<int:pk>/",
        api_client_prestataire_detail,
        name="api-client-prestataire-detail",
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
    path(
        "api/client/reservations/<str:reference>/pay-deposit",
        api_client_pay_deposit,
        name="api-client-pay-deposit",
    ),
    path(
        "api/client/reservations/<str:reference>/pay-remainder",
        api_client_pay_remainder,
        name="api-client-pay-remainder",
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
        "api/messages/send",
        api_messages_send_by_reservation,
        name="api-messages-send",
    ),
    path(
        "api/messages/<str:reservation_reference>",
        api_messages_by_reservation,
        name="api-messages-by-reservation",
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
        "api/prestataire/location/update",
        api_prestataire_location_update,
        name="api-prestataire-location-update",
    ),
    path(
        "api/client/addresses",
        api_client_saved_addresses,
        name="api-client-addresses",
    ),
    path(
        "api/client/addresses/<int:addr_id>",
        api_client_saved_addresses,
        name="api-client-address-detail",
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
        "api/prestataire/earnings/monthly/",
        api_prestataire_earnings,
        name="api-prestataire-earnings-monthly",
    ),
    path(
        "api/prestataire/ratings",
        api_prestataire_ratings,
        name="api-prestataire-ratings",
    ),
    path(
        "api/reservation/paiement-acompte/",
        api_reservation_paiement_acompte,
        name="api-reservation-paiement-acompte",
    ),
    path(
        "api/reservation/paiement-solde/",
        api_reservation_paiement_solde,
        name="api-reservation-paiement-solde",
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
        "api/prestataire/availability/slots/<int:id>/",
        api_prestataire_availability_crud,
        name="api-prestataire-availability-crud-delete",
    ),
    # Alias pour compatibilité Flutter (attendu par availability_screen.dart)
    path(
        "api/prestataire/availability/unavailability/",
        api_prestataire_unavailability_crud,
        name="api-prestataire-availability-unavailability-crud",
    ),
    path(
        "api/prestataire/availability/unavailability/<int:id>/",
        api_prestataire_unavailability_crud,
        name="api-prestataire-availability-unavailability-crud-delete",
    ),
    path(
        "api/prestataire/unavailability/",
        api_prestataire_unavailability_crud,
        name="api-prestataire-unavailability-crud",
    ),
    path("api/prestataire/stats/", api_prestataire_stats, name="api-prestataire-stats"),
    # ── GeniusPay Mobile Money (Wave, Orange, MTN, PawaPay) ─────────────────
    path(
        "api/paiements/geniuspay/initiate/", geniuspay_initiate, name="geniuspay-initiate"
    ),
    path(
        "api/paiements/geniuspay/status/<str:reference>/",
        geniuspay_status,
        name="geniuspay-status",
    ),
    path("api/paiements/geniuspay/webhook/", geniuspay_webhook, name="geniuspay-webhook"),
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
        "api/client/reservations/<str:reference>/journal",
        api_client_journal,
        name="api-client-reservation-journal",
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
    # ── Payment quote (accessible client + prestataire) ─────────────────────
    path(
        "api/reservations/<str:reference>/payment/quote",
        api_payment_quote,
        name="api-payment-quote",
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
    path("api/auth/refresh/", api_auth_refresh_token, name="api-auth-refresh-slash"),
    path(
        "api/admin/reservation/move",
        api_admin_reservation_move,
        name="api-admin-reservation-move",
    ),
    path(
        "api/admin/reservation/<int:id>/status",
        api_admin_reservation_status,
        name="api-admin-reservation-status",
    ),
    path(
        "api/auth/delete-account",
        api_auth_delete_account,
        name="api-auth-delete-account",
    ),
    path("api/health/", api_health_check, name="api-health-check"),
    # ── Reçus / Factures PDF ─────────────────────────────────────────────────
    path("api/client/invoices/", api_client_invoices_list, name="api-client-invoices-list"),
    path("api/client/invoices/<str:reference>/pdf/", api_client_invoice_pdf, name="api-client-invoice-pdf"),
    path("api/client/reservations/<str:reference>/receipt/pdf/", api_client_invoice_pdf, name="api-client-receipt-pdf-alias"),
    path("api/prestataire/invoices/<str:reference>/pdf/", api_prestataire_invoice_pdf, name="api-prestataire-invoice-pdf"),
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
    path(
        "api/prestataire/disputes/<str:dispute_ref>/respond/",
        api_prestataire_respond_dispute,
        name="api-prestataire-respond-dispute",
    ),
    path(
        "api/client/disputes/",
        api_client_disputes,
        name="api-client-disputes",
    ),
    path(
        "api/prestataire/payments/history/",
        api_prestataire_payments_history,
        name="api-prestataire-payments-history",
    ),
    # ── App mobile : version gate + remontée d'erreurs ─────────────────────────
    path("api/app/version", api_app_version, name="api-app-version"),
    path("api/app/version/", api_app_version, name="api-app-version-slash"),
    path("api/internal/run-reminders/", api_run_reminders, name="api-run-reminders"),
    path("api/app/log-error", api_app_log_error, name="api-app-log-error"),
    path("api/app/log-error/", api_app_log_error, name="api-app-log-error-slash"),
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
    path(
        "api/prestataire/requests/<str:reference>/photos",
        api_prestataire_upload_photos,
        name="api-prestataire-upload-photos",
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
    # ── Admin financier ────────────────────────────────────────────────────────
    path(
        "api/admin/financial-summary",
        api_admin_financial_summary,
        name="api-admin-financial-summary",
    ),
    # ── Wallet prestataire ─────────────────────────────────────────────────────
    path("api/prestataire/wallet/", api_prestataire_wallet, name="api-prestataire-wallet"),
    path("api/prestataire/wallet/withdraw/", api_prestataire_wallet_withdraw, name="api-prestataire-wallet-withdraw"),
    path("api/prestataire/wallet/info/", api_prestataire_wallet_update_info, name="api-prestataire-wallet-info"),
    # ── Contrat prestataire & Fidélité client ─────────────────────────────────
    path("api/prestataire/contrat/", api_prestataire_contrat, name="api-prestataire-contrat"),
    path("api/prestataire/contrat/sign/", api_prestataire_contrat_sign, name="api-prestataire-contrat-sign"),
    path("api/client/fidelite/", api_client_fidelite, name="api-client-fidelite"),

    # ── Parrainage ────────────────────────────────────────────────────────────
    path("api/auth/referral/", api_referral, name="api-referral"),

    # ── Premium prestataire ───────────────────────────────────────────────────
    path("api/prestataire/premium/tiers/", api_premium_tiers, name="api-premium-tiers"),
    path("api/prestataire/premium/subscribe/", api_premium_subscribe, name="api-premium-subscribe"),
    path("api/prestataire/premium/calculator/", api_premium_calculator, name="api-premium-calculator"),
    path("api/prestataire/premium/pay/", geniuspay_premium_initiate, name="api-premium-pay"),
    path("api/client/fidelite/", api_client_fidelite, name="api-client-fidelite"),
    path("api/admin/business-kpis/", api_admin_business_kpis, name="api-admin-business-kpis"),
    path("dashboard/kpis/", kpi_dashboard_page, name="kpi-dashboard"),
    # B2B — BABIFIX Pro
    path("api/pro/formules/", api_pro_formules, name="api-pro-formules"),
    path("api/pro/account/", api_pro_account, name="api-pro-account"),
    path("api/pro/sites/", api_pro_sites, name="api-pro-sites"),
    path("api/pro/interventions/", api_pro_declare_intervention, name="api-pro-interventions"),
    path("api/pro/invoice/", api_pro_invoice, name="api-pro-invoice"),

    # ── KYC prestataire ───────────────────────────────────────────────────────
    path("api/prestataire/kyc/status/", api_prestataire_kyc_status, name="api-prestataire-kyc-status"),
    path("api/prestataire/kyc/submit/", api_prestataire_kyc_submit, name="api-prestataire-kyc-submit"),

    # ── Voice note avis ───────────────────────────────────────────────────────
    path(
        "api/client/reservations/<str:reference>/rating-voice/",
        api_rating_voice_upload,
        name="api-rating-voice",
    ),

    # ── Analytics plateforme (admin) ──────────────────────────────────────────
    path("api/admin/platform-revenue/", api_admin_platform_revenue, name="api-platform-revenue"),
    path(
        "api/admin/wallet/withdrawals/<int:tx_id>/validate/",
        api_admin_validate_withdrawal,
        name="api-admin-validate-withdrawal",
    ),

    # ── Multi-devis comparaison ───────────────────────────────────────────────
    path(
        "api/client/reservations/<str:reference>/devis/compare/",
        api_client_devis_compare,
        name="api-client-devis-compare",
    ),

    # ── Urgence preview ───────────────────────────────────────────────────────
    path("api/client/reservations/urgence-preview/", api_urgence_preview, name="api-urgence-preview"),

    # ── Appels audio/vidéo LiveKit ────────────────────────────────────────────
    # Les routes /api/calls/* existaient en code (views_calls.py) mais
    # n'étaient PAS câblées dans urls.py — fix critique pour activer les
    # appels client ↔ prestataire dans l'app.
    path("api/livekit/token", _calls_views.api_livekit_token, name="api-livekit-token"),
    path("api/calls/initiate", _calls_views.api_call_initiate, name="api-call-initiate"),
    path("api/calls/<int:call_id>/answer", _calls_views.api_call_answer, name="api-call-answer"),
    path("api/calls/<int:call_id>/reject", _calls_views.api_call_reject, name="api-call-reject"),
    path("api/calls/<int:call_id>/end", _calls_views.api_call_end, name="api-call-end"),
    path("api/calls/<int:call_id>", _calls_views.api_call_detail, name="api-call-detail"),
    path("api/calls/history", _calls_views.api_call_history, name="api-call-history"),
]
