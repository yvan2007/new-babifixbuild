"""
Interface django-admin : CRUD complet sur tous les modèles BABIFIX.
Le dashboard HTML (`/`) renvoie ici pour ajouter / modifier / supprimer en détail.
"""

from django.contrib import admin
from django.contrib.admin.sites import NotRegistered
from django.contrib.auth.admin import UserAdmin as DjangoUserAdmin
from django.contrib.auth.models import User

from .models import (
    Abonnement,
    Category,
    Client,
    Conversation,
    DeviceToken,
    Dispute,
    Message,
    Notification,
    Payment,
    PlatformRevenue,
    ProAccount,
    ProInvoice,
    ProSite,
    Provider,
    Rating,
    Reservation,
    SiteContent,
    SystemSetting,
    UserProfile,
    WalletTransaction,
)


@admin.register(Provider)
class ProviderAdmin(admin.ModelAdmin):
    list_display = (
        "nom",
        "specialite",
        "ville",
        "statut",
        "tarif_horaire",
        "average_rating",
        "disponible",
        "is_certified",
    )
    list_filter = ("statut", "disponible", "ville", "is_certified", "category")
    search_fields = (
        "nom",
        "specialite",
        "ville",
        "bio",
        "photo_portrait_url",
        "cni_url",
    )
    raw_id_fields = ("user",)
    actions = [
        "approve_providers",
        "refuse_providers",
        "toggle_availability",
        "certify_providers",
    ]

    def approve_providers(self, request, queryset):
        updated = queryset.update(statut=Provider.Status.VALID)
        self.message_user(request, f"{updated} prestataire(s) validé(s).")

    approve_providers.short_description = "Valider les prestataires sélectionnés"

    def refuse_providers(self, request, queryset):
        updated = queryset.update(statut=Provider.Status.REFUSED)
        self.message_user(request, f"{updated} prestataire(s) refusé(s).")

    refuse_providers.short_description = "Refuser les prestataires sélectionnés"

    def toggle_availability(self, request, queryset):
        for provider in queryset:
            provider.disponible = not provider.disponible
            provider.save(update_fields=["disponible"])
        self.message_user(request, "Disponibilité basculée.")

    toggle_availability.short_description = "Basculer la disponibilité"

    def certify_providers(self, request, queryset):
        from django.utils import timezone
        from django.db import transaction

        with transaction.atomic():
            for provider in queryset:
                provider.is_certified = True
                provider.certified_at = timezone.now()
                provider.save(update_fields=["is_certified", "certified_at"])
        self.message_user(request, f"{queryset.count()} prestataire(s) certifié(s).")

    certify_providers.short_description = "Certifier les prestataires sélectionnés"


@admin.register(Client)
class ClientAdmin(admin.ModelAdmin):
    list_display = ("nom", "email", "ville", "reservations", "depense")
    search_fields = ("nom", "email", "ville")


@admin.register(Reservation)
class ReservationAdmin(admin.ModelAdmin):
    list_display = (
        "reference",
        "title",
        "client",
        "prestataire",
        "montant",
        "statut",
        "payment_type",
        "mobile_money_operator",
        "cash_flow_status",
        "solde_valide",
        "funds_released_at",
        "cancellation_reason",
    )
    list_filter = (
        "statut",
        "payment_type",
        "mobile_money_operator",
        "cash_flow_status",
        "solde_valide",
    )
    search_fields = (
        "reference",
        "client",
        "prestataire",
        "title",
        "address_label",
        "cancellation_reason",
    )
    raw_id_fields = ("client_user", "prestataire_user", "assigned_provider")


@admin.register(Dispute)
class DisputeAdmin(admin.ModelAdmin):
    list_display = (
        "reference",
        "motif",
        "client",
        "prestataire",
        "priorite",
        "decision",
    )
    list_filter = ("priorite", "decision")
    search_fields = ("reference", "motif", "client", "prestataire")


@admin.register(Payment)
class PaymentAdmin(admin.ModelAdmin):
    list_display = (
        "reference",
        "client",
        "prestataire",
        "montant",
        "commission",
        "etat",
        "type_paiement",
        "valide_par_admin",
    )
    list_filter = ("etat", "type_paiement", "valide_par_admin")
    search_fields = ("reference", "client", "prestataire", "reference_externe")
    raw_id_fields = ("reservation",)


@admin.register(Category)
class CategoryAdmin(admin.ModelAdmin):
    list_display = (
        "nom",
        "icone_slug",
        "ordre_affichage",
        "services",
        "reservations",
        "actif",
    )
    list_filter = ("actif",)
    search_fields = ("nom", "description")
    ordering = ("ordre_affichage", "nom")


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ("title", "time", "created_at")
    search_fields = ("title",)


@admin.register(DeviceToken)
class DeviceTokenAdmin(admin.ModelAdmin):
    list_display = ("user", "platform", "token_short", "updated_at")
    list_filter = ("platform",)
    search_fields = ("user__username", "token")
    raw_id_fields = ("user",)

    @admin.display(description="Token (extrait)")
    def token_short(self, obj):
        t = obj.token
        return (t[:24] + "…") if len(t) > 24 else t


@admin.register(SystemSetting)
class SystemSettingAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "commission",
        "auto_validation",
        "maintenance",
        "mode_paiement",
    )


@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    list_display = ("user", "role", "active", "phone_e164", "country_code")
    list_filter = ("role", "active")
    search_fields = ("user__username", "user__email", "phone_e164")
    raw_id_fields = ("user",)


@admin.register(SiteContent)
class SiteContentAdmin(admin.ModelAdmin):
    list_display = ("key", "value")
    search_fields = ("key", "value")


class MessageInline(admin.TabularInline):
    model = Message
    extra = 0
    raw_id_fields = ("sender", "reply_to")


@admin.register(Conversation)
class ConversationAdmin(admin.ModelAdmin):
    list_display = ("id", "client", "prestataire", "updated_at")
    raw_id_fields = ("client", "prestataire")
    inlines = (MessageInline,)
    search_fields = ("client__username", "prestataire__username")


@admin.register(Message)
class MessageAdmin(admin.ModelAdmin):
    list_display = ("id", "conversation", "sender", "body", "created_at")
    list_filter = ("created_at",)
    raw_id_fields = ("conversation", "sender", "reply_to")
    search_fields = ("body",)


@admin.register(Rating)
class RatingAdmin(admin.ModelAdmin):
    list_display = ("reservation", "provider", "client", "note", "created_at")
    list_filter = ("note",)
    raw_id_fields = ("reservation", "client", "provider")
    search_fields = ("commentaire",)


# Utilisateurs Django — même table que les comptes des apps (JWT / login API)
try:
    admin.site.unregister(User)
except NotRegistered:
    pass


@admin.register(User)
class BabifixUserAdmin(DjangoUserAdmin):
    list_display = (
        "username",
        "email",
        "first_name",
        "last_name",
        "is_staff",
        "is_active",
    )
    list_filter = ("is_staff", "is_superuser", "is_active")


@admin.register(Abonnement)
class AbonnementAdmin(admin.ModelAdmin):
    list_display = (
        "client",
        "pack_nom",
        "interventions_restantes",
        "prix",
        "date_debut",
        "date_fin",
        "statut",
    )
    list_filter = ("statut", "date_debut", "date_fin")
    search_fields = ("client__username", "pack_nom")


class ProSiteInline(admin.TabularInline):
    model = ProSite
    extra = 0
    fields = ("nom", "commune", "adresse", "actif")


@admin.register(ProAccount)
class ProAccountAdmin(admin.ModelAdmin):
    list_display = (
        "raison_sociale", "formule", "commission_rate", "sla_heures",
        "abonnement_mensuel_fcfa", "actif",
    )
    list_filter = ("formule", "actif")
    search_fields = ("raison_sociale", "contact_nom", "contact_email")
    inlines = [ProSiteInline]


@admin.register(ProSite)
class ProSiteAdmin(admin.ModelAdmin):
    list_display = ("nom", "pro_account", "commune", "actif")
    list_filter = ("actif", "commune")
    search_fields = ("nom", "adresse", "pro_account__raison_sociale")


@admin.register(ProInvoice)
class ProInvoiceAdmin(admin.ModelAdmin):
    list_display = (
        "reference", "pro_account", "periode", "nombre_interventions",
        "total_fcfa", "statut",
    )
    list_filter = ("statut", "periode")
    search_fields = ("reference", "pro_account__raison_sociale")


@admin.register(PlatformRevenue)
class PlatformRevenueAdmin(admin.ModelAdmin):
    list_display = (
        "id", "source", "amount_fcfa", "reference", "payment", "created_at",
    )
    list_filter = ("source", "created_at")
    search_fields = ("reference", "description")


@admin.register(WalletTransaction)
class WalletTransactionAdmin(admin.ModelAdmin):
    list_display = (
        "id", "provider", "tx_type", "amount_fcfa", "status", "reference", "created_at",
    )
    list_filter = ("tx_type", "status", "created_at")
    search_fields = ("reference", "provider__nom", "description")
    raw_id_fields = ("provider",)


from .models import MetierPropose as _MetierPropose


@admin.register(_MetierPropose)
class MetierProposeAdmin(admin.ModelAdmin):
    list_display = ("nom", "votes_display", "statut", "created_at")
    list_filter = ("statut",)
    search_fields = ("nom",)
    actions = ["rendre_disponible"]

    @admin.display(description="Demandes")
    def votes_display(self, obj):
        return f"{obj.votes} / {_MetierPropose.SEUIL}"

    @admin.action(description="Marquer disponible + notifier les interesses")
    def rendre_disponible(self, request, queryset):
        from django.utils import timezone as _tz
        n = 0
        for m in queryset:
            m.statut = _MetierPropose.Statut.DISPONIBLE
            m.disponible_at = _tz.now()
            m.save(update_fields=["statut", "disponible_at"])
            try:
                from .views_extra import send_babifix_email_html
                for em in (m.emails or []):
                    send_babifix_email_html(
                        to_email=em,
                        subject=f"BABIFIX : Le metier « {m.nom} » est disponible !",
                        html_content=(
                            f"<p>Bonne nouvelle ! Le metier <b>{m.nom}</b> que vous "
                            f"avez demande est desormais disponible sur BABIFIX. "
                            f"Ouvrez l'application pour en profiter.</p>"
                        ),
                    )
            except Exception:
                pass
            n += 1
        self.message_user(request, f"{n} metier(s) rendu(s) disponible(s) et interesses notifies.")


admin.site.site_header = "BABIFIX — Administration"
admin.site.site_title = "BABIFIX Admin"
admin.site.index_title = "CRUD : prestataires, réservations, paiements, contenido…"


# ── Configuration plateforme (taux/seuils/deltas modifiables) ────────────────
from .models import PlatformConfig as _PlatformConfig


@admin.register(_PlatformConfig)
class PlatformConfigAdmin(admin.ModelAdmin):
    """Réglages globaux BABIFIX (singleton pk=1)."""

    fieldsets = (
        ("Commission", {"fields": ("caution_commission_pct",)}),
        ("Gating fiabilité", {
            "fields": ("fiabilite_gating_actif", "fiabilite_seuil"),
            "description": "Désactivé par défaut. Une fois activé, un score bas "
                           "déprioritise le prestataire et signale le client en "
                           "prépaiement.",
        }),
        ("Deltas de fiabilité (signés)", {
            "fields": (
                "delta_completion_presta", "delta_completion_client",
                "delta_client_annulation_suspecte", "delta_client_annulation_tardive",
                "delta_presta_noshow", "delta_presta_annulation_tardive",
            ),
        }),
        (None, {"fields": ("updated_at",)}),
    )
    readonly_fields = ("updated_at",)

    def has_add_permission(self, request):
        # Singleton : pas d'ajout si la ligne existe déjà.
        return not _PlatformConfig.objects.exists()

    def has_delete_permission(self, request, obj=None):
        return False
