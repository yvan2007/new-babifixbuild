"""
Cockpit Admin Unifie BABIFIX :
- Compteurs sidebar globaux temps reel
- Transcription complete de reservation (Timeline, Devis + Coherence SmartDevisAdvisor, Escrow/Paiements, Appels LiveKit, Bon de commande PDF, Top 3 Smart Matching)
- Simulateur & Dispatch Smart Matching unifie
- Gestion inter-applications : Metiers proposes, Appels superviseur, Avis & notes vocales, BABIFIX Pro B2B, Abonnements & Fidelite, Sante Apps / FCM Push stats
- Actions POST consolidees pour dashboard()
"""

from __future__ import annotations

import json
import os
from datetime import timedelta
from decimal import Decimal

from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.contrib.auth.models import User
from django.db.models import Avg, Count, Q, Sum
from django.http import JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_GET, require_http_methods

from .models import (
    Abonnement,
    AdminAuditLog,
    Call,
    Category,
    Devis,
    DeviceToken,
    Dispute,
    MetierPropose,
    Notification,
    Payment,
    PlatformConfig,
    PlatformRevenue,
    ProAccount,
    ProInvoice,
    ProSite,
    Provider,
    Rating,
    Reservation,
    ReservationStatusHistory,
    SystemSetting,
    UserProfile,
    WalletTransaction,
)
from .models_v2 import ClientRating
from .services.intelligence_service import SmartDevisAdvisor, SmartProviderScorer
from .services.matching_service import MatchingCriteria, MatchingService
from .services.platform_config_service import (
    broadcast_platform_config,
    build_public_platform_config,
    get_dynamic_tier_configs,
)
from .services.provider_subscription_service import PREMIUM_TIERS, STANDARD_TIER


def _is_staff(user) -> bool:
    return bool(user and user.is_authenticated and (user.is_staff or user.is_superuser))


def _sanitize_slug(name: str) -> str:
    import re
    import unicodedata

    raw = unicodedata.normalize("NFKD", (name or "").strip()).encode("ascii", "ignore").decode("ascii")
    slug = re.sub(r"[^a-zA-Z0-9]+", "-", raw.lower()).strip("-")
    return slug or "service"


def compute_sidebar_counts() -> dict:
    """Compteurs globaux fiables pour la navigation laterale, independants des filtres de section."""
    pending_providers = Provider.objects.filter(
        statut=Provider.Status.PENDING, is_deleted=False
    ).count()
    open_disputes = Dispute.objects.filter(decision=Dispute.Decision.OPEN).count()
    pending_withdrawals = WalletTransaction.objects.filter(
        tx_type="debit", status="pending"
    ).count()
    pending_calls = Provider.objects.filter(
        whatsapp_interview_requested=True,
        supervisor_verified_at__isnull=True,
        is_deleted=False,
    ).count()
    pending_metiers = MetierPropose.objects.filter(
        statut=MetierPropose.Statut.EN_ATTENTE
    ).count()
    unread_notifications = Notification.objects.filter(lu=False).count()
    unassigned_reservations = Reservation.objects.filter(
        assigned_provider__isnull=True
    ).exclude(statut__in=["Terminee", "DONE", "Annulee", "CANCELLED"]).count()

    return {
        "pending_providers": pending_providers,
        "open_disputes": open_disputes,
        "pending_withdrawals": pending_withdrawals,
        "pending_calls": pending_calls,
        "pending_metiers": pending_metiers,
        "unread_notifications": unread_notifications,
        "unassigned_reservations": unassigned_reservations,
    }


def compute_cockpit_extras(section: str, request) -> dict:
    """Charge uniquement les donnees additionnelles pertinentes pour la section active."""
    pub_cfg = build_public_platform_config()
    ctx: dict = {
        "sidebar_counts": compute_sidebar_counts(),
        "platform_config": PlatformConfig.get_solo(),
        "public_config": pub_cfg,
    }

    if section in ("finances", "paiements", "dashboard", "payouts", "parametres"):
        std_cfg, prem_cfgs = get_dynamic_tier_configs()
        now = timezone.now()
        active_prov_qs = Provider.objects.filter(
            statut=Provider.Status.VALID, is_deleted=False
        )
        total_valid = active_prov_qs.count()
        gold_cnt = active_prov_qs.filter(
            is_premium=True, premium_tier="gold"
        ).filter(Q(premium_until__isnull=True) | Q(premium_until__gte=now)).count()
        silver_cnt = active_prov_qs.filter(
            is_premium=True, premium_tier="silver"
        ).filter(Q(premium_until__isnull=True) | Q(premium_until__gte=now)).count()
        std_cnt = max(0, total_valid - gold_cnt - silver_cnt)

        r_std = float(std_cfg["commission_effective_pct"])
        r_sil = float(prem_cfgs["silver"]["commission_effective_pct"])
        r_gld = float(prem_cfgs["gold"]["commission_effective_pct"])
        weighted_take = r_std
        if total_valid > 0:
            weighted_take = round(
                (std_cnt * r_std + silver_cnt * r_sil + gold_cnt * r_gld) / total_valid,
                1,
            )

        rev_total = float(
            PlatformRevenue.objects.filter(refunded_at__isnull=True).aggregate(
                s=Sum("amount_fcfa")
            )["s"] or 0
        )
        rev_comm = float(
            PlatformRevenue.objects.filter(
                source=PlatformRevenue.Source.COMMISSION, refunded_at__isnull=True
            ).aggregate(s=Sum("amount_fcfa"))["s"] or 0
        )
        rev_prem = float(
            PlatformRevenue.objects.filter(
                source=PlatformRevenue.Source.PREMIUM, refunded_at__isnull=True
            ).aggregate(s=Sum("amount_fcfa"))["s"] or 0
        )
        rev_pen = float(
            PlatformRevenue.objects.filter(
                source=PlatformRevenue.Source.PENALITE, refunded_at__isnull=True
            ).aggregate(s=Sum("amount_fcfa"))["s"] or 0
        )

        # Wallets par palier (pour les cartes Wallet 3D)
        wallet_gold = float(
            active_prov_qs.filter(is_premium=True, premium_tier="gold").aggregate(
                s=Sum("solde_fcfa")
            )["s"] or 0
        )
        wallet_silver = float(
            active_prov_qs.filter(is_premium=True, premium_tier="silver").aggregate(
                s=Sum("solde_fcfa")
            )["s"] or 0
        )
        wallet_std = float(
            active_prov_qs.exclude(
                is_premium=True, premium_tier__in=["silver", "gold"]
            ).aggregate(s=Sum("solde_fcfa"))["s"] or 0
        )

        ctx["tier_economics"] = {
            "total_valid": total_valid,
            "standard_count": std_cnt,
            "silver_count": silver_cnt,
            "gold_count": gold_cnt,
            "weighted_take_rate_pct": weighted_take,
            "standard_cfg": std_cfg,
            "silver_cfg": prem_cfgs["silver"],
            "gold_cfg": prem_cfgs["gold"],
            "rev_total": rev_total,
            "rev_commission": rev_comm,
            "rev_premium": rev_prem,
            "rev_penalite": rev_pen,
            "wallet_standard_fcfa": wallet_std,
            "wallet_silver_fcfa": wallet_silver,
            "wallet_gold_fcfa": wallet_gold,
        }

    if section in ("categories", "catalogue"):
        from .models import CategoryCommission
        from .services.catalogue_service import CatalogueService

        cat_comm_map = {
            cc.category_id: cc.commission_rate
            for cc in CategoryCommission.objects.filter(actif=True)
        }
        all_cats = list(
            Category.objects.filter(is_deleted=False).order_by("ordre_affichage", "nom")
        )
        cat_counts = {
            c.id: len(CatalogueService.get_catalogue_items(c.id)) for c in all_cats
        }
        ctx["category_custom_rates"] = cat_comm_map
        ctx["catalogue_counts_by_cat"] = cat_counts
        ctx["cat_studio_metrics"] = {
            "total": len(all_cats),
            "actives": sum(1 for c in all_cats if c.actif),
            "custom_comm_count": len(cat_comm_map),
            "catalogue_total": sum(cat_counts.values()),
            "sensibles_count": sum(1 for c in all_cats if getattr(c, "regime_kyc", "") == Category.RegimeKyc.SENSIBLE_CASIER),
        }
        pending_metiers = list(
            MetierPropose.objects.filter(statut=MetierPropose.Statut.EN_ATTENTE)
            .annotate(waiting_providers_count=Count("providers_en_attente"))
            .order_by("-created_at")
        )
        pending_metiers.sort(key=lambda m: (-int(getattr(m, "waiting_providers_count", 0) or 0), -m.votes))
        ctx["pending_metiers_for_categories"] = pending_metiers

        if section == "catalogue":
            active_cats = [c for c in all_cats if c.actif] or all_cats
            raw_cat_id = (request.GET.get("cat_id") or "").strip()
            selected_cat = None
            if raw_cat_id.isdigit():
                selected_cat = next(
                    (c for c in active_cats if c.id == int(raw_cat_id)), None
                )
            if not selected_cat and active_cats:
                selected_cat = active_cats[0]
            raw_items = (
                CatalogueService.get_catalogue_items(selected_cat.id)
                if selected_cat
                else []
            )
            type_labels = {
                "FOURNITURE": "Fourniture",
                "MAIN_OEUVRE": "Main d'oeuvre",
                "DEPLACEMENT": "Deplacement",
                "AUTRE": "Autre",
            }
            for item in raw_items:
                item["type_display"] = type_labels.get(
                    item.get("type_ligne", ""), item.get("type_ligne", "Fourniture")
                )
            ctx["catalogue_categories"] = active_cats
            ctx["catalogue_selected"] = selected_cat
            ctx["catalogue_items"] = raw_items
            ctx["catalogue_units"] = (
                CatalogueService.get_recommended_units(selected_cat.id)
                if selected_cat
                else []
            )

    if section == "paiements":
        ctx["client_abonnements"] = (
            Abonnement.objects.select_related("client").order_by("-created_at", "-id")[:30]
        )
        ctx["premium_providers"] = (
            Provider.objects.filter(is_premium=True, is_deleted=False)
            .order_by("-premium_since", "-id")[:30]
        )

    if section == "prestataires":
        ctx["supervisor_call_queue"] = (
            Provider.objects.filter(
                whatsapp_interview_requested=True,
                supervisor_verified_at__isnull=True,
                is_deleted=False,
            )
            .select_related("category", "user")
            .order_by("-id")[:20]
        )
        ctx["recent_calls"] = (
            Call.objects.select_related("caller", "callee", "reservation")
            .order_by("-started_at")[:20]
        )

    if section == "reservations":
        ctx["matching_categories"] = Category.objects.filter(actif=True).order_by(
            "ordre_affichage", "nom"
        )
        ctx["urgent_or_unassigned"] = (
            Reservation.objects.filter(
                Q(assigned_provider__isnull=True) | Q(is_urgent=True)
            )
            .exclude(statut__in=["Terminee", "DONE", "Annulee", "CANCELLED"])
            .order_by("-is_urgent", "-created_at")[:10]
        )

    if section == "clients":
        # Points fidelite & parrainage reels depuis UserProfile
        loyalty_profiles = (
            UserProfile.objects.filter(role=UserProfile.Role.CLIENT)
            .select_related("user")
            .order_by("-points_fidelite", "-id")[:25]
        )
        ctx["loyalty_summary"] = {
            "total_points": UserProfile.objects.filter(
                role=UserProfile.Role.CLIENT
            ).aggregate(s=Sum("points_fidelite"))["s"] or 0,
            "referrals_count": UserProfile.objects.filter(
                recommended_by__isnull=False
            ).count(),
            "top_profiles": loyalty_profiles,
        }

    if section == "notifications":
        dt_qs = DeviceToken.objects.all()
        ctx["fcm_stats"] = {
            "total_devices": dt_qs.count(),
            "android_devices": dt_qs.filter(platform=DeviceToken.Platform.ANDROID).count(),
            "ios_devices": dt_qs.filter(platform=DeviceToken.Platform.IOS).count(),
            "web_devices": dt_qs.filter(platform=DeviceToken.Platform.WEB).count(),
            "client_app_devices": dt_qs.filter(app=DeviceToken.App.CLIENT).count(),
            "pro_app_devices": dt_qs.filter(app=DeviceToken.App.PRO).count(),
        }

    if section == "ecosysteme":
        metiers = list(MetierPropose.objects.all().order_by("statut", "-created_at"))
        metiers.sort(key=lambda m: (0 if m.statut == "en_attente" else 1, -m.votes))
        ctx["metiers_proposes"] = metiers
        ctx["pro_accounts"] = (
            ProAccount.objects.select_related("user").prefetch_related("sites").order_by("-created_at")[:30]
        )
        ctx["pro_invoices"] = (
            ProInvoice.objects.select_related("pro_account").order_by("-created_at", "-id")[:30]
        )
        ctx["client_reviews"] = (
            Rating.objects.select_related("reservation", "client", "provider")
            .order_by("-created_at")[:30]
        )
        ctx["provider_to_client_reviews"] = (
            ClientRating.objects.select_related("reservation", "prestataire_user", "client_user")
            .order_by("-created_at")[:20]
        )
        ctx["ecosystem_stats"] = {
            "metiers_pending": sum(1 for m in metiers if m.statut == "en_attente"),
            "metiers_threshold_reached": sum(
                1 for m in metiers if m.statut == "en_attente" and m.votes >= MetierPropose.SEUIL
            ),
            "pro_accounts_active": ProAccount.objects.filter(actif=True).count(),
            "pro_sites_total": ProSite.objects.filter(actif=True).count(),
            "reviews_with_voice": Rating.objects.exclude(voice_note_url="").count(),
            "avg_rating": round(float(Rating.objects.aggregate(a=Avg("note"))["a"] or 0), 2),
        }

    if section == "kpis":
        from .views_finance import _compute_business_kpis

        try:
            days = max(1, min(365, int(request.GET.get("days", 30))))
        except (TypeError, ValueError):
            days = 30
        ctx["kpis_days"] = days
        ctx["business_kpis"] = _compute_business_kpis(days)
        ctx["app_versions"] = {
            "client_android_min": os.getenv("APP_CLIENT_MIN_VERSION_ANDROID", os.getenv("APP_MIN_VERSION_ANDROID", "1.0.0")),
            "client_android_latest": os.getenv("APP_CLIENT_LATEST_VERSION_ANDROID", os.getenv("APP_LATEST_VERSION_ANDROID", "1.0.0")),
            "presta_android_min": os.getenv("APP_PRESTA_MIN_VERSION_ANDROID", os.getenv("APP_MIN_VERSION_ANDROID", "1.0.0")),
            "presta_android_latest": os.getenv("APP_PRESTA_LATEST_VERSION_ANDROID", os.getenv("APP_LATEST_VERSION_ANDROID", "1.0.0")),
            "geniuspay_mode": "LIVE" if os.getenv("GENIUSPAY_PUBLIC_KEY", "").startswith("pk_live_") else "SIMULATION / TEST",
            "livekit_ok": bool(os.getenv("LIVEKIT_URL") and os.getenv("LIVEKIT_API_KEY")),
            "firebase_ok": bool(os.getenv("FIREBASE_PROJECT_ID") or os.getenv("GOOGLE_APPLICATION_CREDENTIALS")),
            "smtp_ok": bool(os.getenv("EMAIL_HOST") and os.getenv("EMAIL_HOST_USER")),
        }

    return ctx


def handle_cockpit_post_action(request, action: str, settings_obj: SystemSetting) -> tuple[bool, str]:
    """
    Traite les actions POST supplementaires du cockpit admin.
    Retourne (handled: bool, target_section: str).
    """
    if action == "toggle_maintenance":
        from .models import SiteContent

        settings_obj.maintenance = not bool(settings_obj.maintenance)
        settings_obj.save()
        maint_item, _ = SiteContent.objects.get_or_create(key="maintenance_schedule")
        m_cfg = dict(maint_item.json_value) if isinstance(maint_item.json_value, dict) else {}
        if "allow_active_missions" not in m_cfg:
            m_cfg["allow_active_missions"] = True
            maint_item.json_value = m_cfg
            maint_item.save()

        active_cnt = Reservation.objects.exclude(
            statut__in=["Terminee", "DONE", "Annulee", "CANCELLED", "Refusee", "REJECTED"]
        ).count()
        AdminAuditLog.objects.create(
            admin_user=request.user,
            action=AdminAuditLog.ActionType.OTHER,
            target_type="PlatformConfig",
            target_id=PlatformConfig.get_solo().pk,
            target_label="Mode Maintenance Apps",
            details={
                "maintenance": settings_obj.maintenance,
                "allow_active_missions": m_cfg.get("allow_active_missions", True),
                "active_missions_count": active_cnt,
            },
        )
        broadcast_platform_config()
        messages.success(
            request,
            "Mode maintenance ACTIVE sur toutes les applications."
            if settings_obj.maintenance
            else "Mode maintenance DESACTIVE : applications de nouveau en ligne.",
        )
        ret_sec = (request.POST.get("return_section") or "parametres").strip()
        return True, ret_sec

    if action == "params_update":
        cfg = PlatformConfig.get_solo()
        commission = (request.POST.get("commission") or "").strip()
        if commission.isdigit():
            val = max(1, min(35, int(commission)))
            settings_obj.commission = val
            cfg.base_commission_pct = val
        settings_obj.auto_validation = request.POST.get("auto_validation") == "on"
        settings_obj.maintenance = request.POST.get("maintenance") == "on"
        mode_raw = (request.POST.get("mode_paiement") or "").strip()[:120]
        if mode_raw:
            settings_obj.mode_paiement = mode_raw
        settings_obj.save()

        def _int_field(name: str, lo: int, hi: int):
            raw = (request.POST.get(name) or "").strip()
            if raw.isdigit():
                setattr(cfg, name, max(lo, min(hi, int(raw))))

        _int_field("frais_mise_en_relation_fcfa", 0, 50000)
        _int_field("commission_floor_pct", 1, 20)
        _int_field("silver_commission_reduction", 0, 20)
        _int_field("gold_commission_reduction", 0, 25)
        _int_field("silver_price_fcfa", 0, 500000)
        _int_field("gold_price_fcfa", 0, 1000000)
        _int_field("standard_max_devis", 1, 50)
        _int_field("silver_max_devis", 1, 200)
        _int_field("silver_visibility_boost_pct", 0, 300)
        _int_field("gold_visibility_boost_pct", 0, 500)
        _int_field("min_withdrawal_fcfa", 100, 100000)
        _int_field("daily_withdrawal_cap_fcfa", 5000, 10000000)
        _int_field("urgency_surcharge_pct", 0, 100)
        _int_field("escrow_auto_confirm_hours", 6, 336)
        _int_field("matching_radius_km", 1, 250)
        _int_field("fiabilite_seuil", 10, 95)
        _int_field("radar_visite_sans_devis_jours", 1, 30)
        _int_field("suspension_score_seuil", 5, 60)
        _int_field("suspension_visites_suspectes", 1, 20)

        if "platform_config_present" in request.POST:
            cfg.fiabilite_gating_actif = request.POST.get("fiabilite_gating_actif") == "on"
            cfg.auto_suspension_actif = request.POST.get("auto_suspension_actif") == "on"

        if "platform_apps_sync_present" in request.POST:
            cfg.allow_cash_payments = request.POST.get("allow_cash_payments") == "on"
            cfg.allow_mobile_money_payments = request.POST.get("allow_mobile_money_payments") == "on"
            cfg.require_kyc_for_visibility = request.POST.get("require_kyc_for_visibility") == "on"
            cfg.require_supervisor_interview = request.POST.get("require_supervisor_interview") == "on"
            ops = [op.strip().lower() for op in request.POST.getlist("enabled_operators") if op.strip()]
            if ops:
                cfg.enabled_operators_csv = ",".join(ops)
            if "support_phone" in request.POST:
                cfg.support_phone = (request.POST.get("support_phone") or "").strip()[:32]
            if "support_whatsapp" in request.POST:
                cfg.support_whatsapp = (request.POST.get("support_whatsapp") or "").strip()[:32]

            from datetime import datetime, timedelta
            from .models import SiteContent

            maint_item, _ = SiteContent.objects.get_or_create(key="maintenance_schedule")
            m_cfg = dict(maint_item.json_value) if isinstance(maint_item.json_value, dict) else {}

            raw_sched = (
                (request.POST.get("maintenance_scheduled_at") or "").strip()[:40]
                if "maintenance_scheduled_at" in request.POST
                else str(m_cfg.get("scheduled_at") or "").strip()
            )
            raw_end = (
                (request.POST.get("maintenance_end_at") or "").strip()[:40]
                if "maintenance_end_at" in request.POST
                else str(m_cfg.get("estimated_end_at") or "").strip()
            )

            def _parse_dt_local(val):
                if not val:
                    return None
                return datetime.strptime(val[:16], "%Y-%m-%dT%H:%M")

            try:
                sched_dt = _parse_dt_local(raw_sched)
                end_dt = _parse_dt_local(raw_end)
            except ValueError:
                messages.error(
                    request,
                    "Format date/heure invalide : veuillez selectionner une date et une heure valides.",
                )
                return True, "parametres"

            now_local = datetime.now() - timedelta(minutes=5)
            if sched_dt is not None and sched_dt < now_local:
                messages.error(
                    request,
                    "Exception horaire : la date et l'heure de debut de maintenance ne peuvent pas etre dans le passe.",
                )
                return True, "parametres"
            if end_dt is not None and end_dt < now_local:
                messages.error(
                    request,
                    "Exception horaire : la date et l'heure de fin estimee ne peuvent pas etre dans le passe.",
                )
                return True, "parametres"
            if sched_dt is not None and end_dt is not None and end_dt <= sched_dt:
                messages.error(
                    request,
                    "Exception horaire : la date et l'heure de fin doivent etre posterieures au debut de maintenance.",
                )
                return True, "parametres"

            if "maintenance_scheduled_at" in request.POST:
                m_cfg["scheduled_at"] = raw_sched
            if "maintenance_end_at" in request.POST:
                m_cfg["estimated_end_at"] = raw_end
            if "maintenance_message" in request.POST:
                m_cfg["message"] = (request.POST.get("maintenance_message") or "").strip()[:260]
            if "maintenance_schedule_present" in request.POST:
                m_cfg["allow_active_missions"] = request.POST.get("maintenance_allow_active") == "on"
            maint_item.json_value = m_cfg
            maint_item.save()

        cfg.save()

        AdminAuditLog.objects.create(
            admin_user=request.user,
            action=AdminAuditLog.ActionType.OTHER,
            target_type="PlatformConfig",
            target_id=cfg.pk,
            target_label="Parametres & Sync Apps",
            details={
                "base_commission_pct": cfg.base_commission_pct,
                "silver_price_fcfa": cfg.silver_price_fcfa,
                "gold_price_fcfa": cfg.gold_price_fcfa,
                "min_withdrawal_fcfa": cfg.min_withdrawal_fcfa,
                "maintenance": settings_obj.maintenance,
            },
        )
        broadcast_platform_config()

        messages.success(
            request,
            "Parametres enregistres et diffuses en temps reel vers les apps Client, Prestataire et la Vitrine.",
        )
        return True, "parametres"

    if action == "metier_approve":
        pk = (request.POST.get("pk") or "").strip()
        create_cat = request.POST.get("create_category") == "1"
        regime_kyc = (request.POST.get("regime_kyc") or Category.RegimeKyc.STANDARD_TERRAIN).strip()
        if regime_kyc not in (Category.RegimeKyc.STANDARD_TERRAIN, Category.RegimeKyc.SENSIBLE_CASIER):
            regime_kyc = Category.RegimeKyc.STANDARD_TERRAIN
        return_section = (request.POST.get("return_section") or "ecosysteme").strip()
        if return_section not in ("ecosysteme", "categories"):
            return_section = "ecosysteme"

        if pk.isdigit():
            metier = MetierPropose.objects.filter(pk=int(pk)).first()
            if metier:
                metier.statut = MetierPropose.Statut.DISPONIBLE
                metier.disponible_at = timezone.now()
                metier.save(update_fields=["statut", "disponible_at"])
                created_cat = False
                attached_count = 0
                target_cat = Category.objects.filter(nom__iexact=metier.nom).first()
                if create_cat and not target_cat:
                    target_cat = Category.objects.create(
                        nom=metier.nom,
                        description=f"Categorie ouverte suite aux demandes de la communaute ({metier.votes} vote(s)).",
                        icone_slug="outils",
                        regime_kyc=regime_kyc,
                        actif=True,
                    )
                    created_cat = True
                elif target_cat and not target_cat.actif:
                    target_cat.actif = True
                    target_cat.save(update_fields=["actif"])

                if target_cat:
                    attached_count = Provider.objects.filter(
                        metier_propose=metier, category__isnull=True
                    ).update(category=target_cat, specialite=target_cat.nom)
                    for prov_att in Provider.objects.filter(metier_propose=metier, user__isnull=False):
                        Notification.objects.create(
                            user=prov_att.user,
                            title=f"Votre metier '{target_cat.nom}' est desormais ouvert sur BABIFIX !",
                            notif_type="system",
                        )

                Notification.objects.create(
                    title=f"Metier valide : {metier.nom} ({metier.votes} demande(s), {attached_count} artisan(s) rattache(s))",
                    notif_type="system",
                )
                AdminAuditLog.objects.create(
                    admin_user=request.user,
                    action=AdminAuditLog.ActionType.OTHER,
                    target_type="MetierPropose",
                    target_id=metier.pk,
                    target_label=metier.nom,
                    details={
                        "create_category": created_cat,
                        "regime_kyc": regime_kyc,
                        "attached_providers": attached_count,
                        "votes": metier.votes,
                    },
                )
                msg_extra = " et categorie active creee" if created_cat else ""
                if attached_count:
                    msg_extra += f" ({attached_count} artisan(s) rattache(s))"
                messages.success(request, f"Metier « {metier.nom} » marque disponible{msg_extra}.")
        return True, return_section

    if action == "metier_delete":
        pk = (request.POST.get("pk") or "").strip()
        if pk.isdigit():
            MetierPropose.objects.filter(pk=int(pk)).delete()
            messages.success(request, "Proposition de metier supprimee.")
        return True, "ecosysteme"

    if action == "supervisor_verify_provider":
        pid = (request.POST.get("provider_id") or "").strip()
        certify = request.POST.get("certify") == "on" or request.POST.get("certify") == "1"
        if pid.isdigit():
            prov = Provider.objects.filter(pk=int(pid)).first()
            if prov:
                now = timezone.now()
                prov.supervisor_verified_at = now
                prov.supervisor_verified_by = request.user.username or "admin"
                prov.whatsapp_interview_requested = False
                fields = [
                    "supervisor_verified_at",
                    "supervisor_verified_by",
                    "whatsapp_interview_requested",
                ]
                if certify:
                    prov.is_certified = True
                    prov.certified_at = now
                    fields.extend(["is_certified", "certified_at"])
                prov.save(update_fields=fields)
                if prov.user_id:
                    Notification.objects.create(
                        user_id=prov.user_id,
                        title="Entretien superviseur valide",
                        body="Votre entretien terrain BABIFIX a ete valide par l'equipe supervision.",
                        notif_type="kyc",
                    )
                messages.success(
                    request,
                    f"Entretien superviseur valide pour {prov.nom}"
                    + (" (badge Certifie active)." if certify else "."),
                )
        return True, "prestataires"

    if action == "pro_account_toggle":
        pk = (request.POST.get("pk") or "").strip()
        if pk.isdigit():
            acc = ProAccount.objects.filter(pk=int(pk)).first()
            if acc:
                acc.actif = not acc.actif
                acc.save(update_fields=["actif"])
                messages.success(
                    request,
                    f"Compte B2B {acc.raison_sociale} : {'active' if acc.actif else 'suspendu'}.",
                )
        return True, "ecosysteme"

    if action == "pro_invoice_mark_paid":
        pk = (request.POST.get("pk") or "").strip()
        if pk.isdigit():
            inv = ProInvoice.objects.filter(pk=int(pk)).first()
            if inv:
                inv.statut = ProInvoice.Statut.PAYEE
                inv.save(update_fields=["statut"])
                messages.success(request, f"Facture B2B {inv.reference} marquee payee.")
        return True, "ecosysteme"

    if action == "notifications_mark_all_read":
        updated = Notification.objects.filter(lu=False).update(lu=True)
        messages.success(request, f"{updated} notification(s) marquee(s) comme lue(s).")
        return True, "notifications"

    if action == "notification_mark_read":
        pk = (request.POST.get("pk") or "").strip()
        if pk.isdigit():
            Notification.objects.filter(pk=int(pk)).update(lu=True)
            messages.success(request, "Notification marquee comme lue.")
        return True, "notifications"

    if action == "rating_delete":
        pk = (request.POST.get("pk") or "").strip()
        if pk.isdigit():
            rating = Rating.objects.select_related("provider").filter(pk=int(pk)).first()
            if rating:
                prov = rating.provider
                rating.delete()
                if prov:
                    from .models import recalc_provider_rating_stats

                    recalc_provider_rating_stats(prov)
                messages.success(request, "Avis modere et note prestataire recalculee.")
        return True, "ecosysteme"

    if action == "reservation_smart_assign":
        ref = (request.POST.get("reference") or "").strip()
        pid = (request.POST.get("provider_id") or "").strip()
        res = Reservation.objects.filter(reference=ref).first()
        prov = Provider.objects.filter(pk=int(pid), statut=Provider.Status.VALID, is_deleted=False).first() if pid.isdigit() else None
        if res and prov:
            _apply_provider_assignment(res, prov, request.user, source="dashboard_smart_dispatch")
            messages.success(request, f"Reservation {res.reference} affectee a {prov.nom}.")
        else:
            messages.error(request, "Impossible d'affecter : reservation ou prestataire introuvable.")
        return True, "reservations"

    return False, ""


def _apply_provider_assignment(res: Reservation, prov: Provider, actor: User, source: str = "smart_dispatch"):
    """Affecte un prestataire a une reservation, journalise historique + audit + notifications."""
    old_prov_name = res.prestataire or "A affecter"
    old_status = res.statut
    res.assigned_provider = prov
    res.prestataire = prov.nom
    if prov.user_id:
        res.prestataire_user_id = prov.user_id
    if res.statut in ("En attente", "DEMANDE_ENVOYEE", ""):
        res.statut = Reservation.Status.DEMANDE_ENVOYEE
    res.save(update_fields=["assigned_provider", "prestataire", "prestataire_user", "statut"])

    ReservationStatusHistory.objects.create(
        reservation=res,
        old_status=old_status,
        new_status=res.statut,
        changed_by=actor,
        comment=f"Affectation intelligente ({source}) : {old_prov_name} -> {prov.nom}",
    )
    AdminAuditLog.objects.create(
        admin_user=actor,
        action=AdminAuditLog.ActionType.OTHER,
        target_type="Reservation",
        target_id=res.pk,
        target_label=res.reference,
        details={"old_provider": old_prov_name, "new_provider": prov.nom, "source": source},
    )
    try:
        from .push_dispatch import _schedule

        uids = []
        if prov.user_id:
            uids.append(prov.user_id)
            Notification.objects.create(
                user_id=prov.user_id,
                title=f"Nouvelle mission assignee : {res.reference}",
                body=f"{res.title or 'Intervention'} ({res.address_quartier or res.address_ville or 'Abidjan'})",
                notif_type="reservation",
                reference=res.reference,
            )
        if res.client_user_id:
            uids.append(res.client_user_id)
            Notification.objects.create(
                user_id=res.client_user_id,
                title=f"Artisan affecte : {prov.nom}",
                body=f"Votre demande {res.reference} a ete confiee a {prov.nom}.",
                notif_type="reservation",
                reference=res.reference,
            )
        if uids:
            _schedule(
                user_ids=uids,
                title=f"BABIFIX : {res.reference}",
                body=f"Prestataire assigne : {prov.nom}",
                data={"type": "reservation.assigned", "reference": res.reference},
            )
    except Exception:
        pass


@login_required
@require_GET
def api_admin_reservation_transcription(request, reference):
    """GET /api/admin/reservations/<ref>/transcription/
    Retourne le dossier complet d'une reservation pour le tiroir de transcription admin.
    Respecte la confidentialite : les messages prives de chat ne sont jamais exposes.
    """
    if not _is_staff(request.user):
        return JsonResponse({"error": "admin_required"}, status=403)

    res = (
        Reservation.objects.select_related("client_user", "prestataire_user", "assigned_provider", "assigned_provider__category")
        .filter(reference=reference)
        .first()
    )
    if not res:
        return JsonResponse({"error": "reservation_not_found"}, status=404)

    history_rows = [
        {
            "old_status": h.old_status,
            "new_status": h.new_status,
            "changed_by": h.changed_by.username if h.changed_by_id else "Systeme",
            "comment": h.comment,
            "created_at": timezone.localtime(h.created_at).strftime("%d/%m/%Y %H:%M"),
        }
        for h in res.status_history.select_related("changed_by").order_by("created_at")
    ]

    devis_list = []
    cat_id = res.assigned_provider.category_id if res.assigned_provider_id else None
    plafond = float(getattr(res.assigned_provider, "plafond_intervention_fcfa", 0) or 0) if res.assigned_provider_id else 0
    for d in res.devis_set.select_related("prestataire").prefetch_related("lignes").order_by("-created_at"):
        lignes = [
            {
                "type_ligne": lg.type_ligne,
                "description": lg.description,
                "quantite": lg.quantite,
                "unite": lg.unite,
                "prix_unitaire": float(lg.prix_unitaire or 0),
                "total": float(lg.total or 0),
                "marque": lg.marque,
            }
            for lg in d.lignes.all()
        ]
        coherence = SmartDevisAdvisor.check_devis_coherence(
            total_ttc=float(d.total_ttc or 0),
            category_id=cat_id,
            description=d.diagnostic or res.description_probleme or res.title or "",
            plafond_fcfa=plafond,
        )
        devis_list.append(
            {
                "reference": d.reference,
                "statut": d.statut,
                "est_estimation": bool(d.est_estimation),
                "prestataire": d.prestataire.nom if d.prestataire_id else res.prestataire,
                "diagnostic": d.diagnostic,
                "sous_total": float(d.sous_total or 0),
                "commission_rate": d.commission_rate,
                "commission_montant": float(d.commission_montant or 0),
                "net_prestataire": float(d.net_prestataire or 0),
                "total_ttc": float(d.total_ttc or 0),
                "created_at": timezone.localtime(d.created_at).strftime("%d/%m/%Y %H:%M"),
                "lignes": lignes,
                "coherence": coherence,
            }
        )

    payments = [
        {
            "reference": p.reference,
            "montant": float(p.montant or 0),
            "commission": float(p.commission or 0),
            "net": float((p.montant or 0) - (p.commission or 0)),
            "etat": p.etat,
            "type_paiement": p.type_paiement,
            "valide_par_admin": bool(p.valide_par_admin),
            "created_at": timezone.localtime(p.created_at).strftime("%d/%m/%Y %H:%M"),
        }
        for p in res.payments.order_by("-created_at")
    ]

    calls = [
        {
            "id": c.pk,
            "kind": c.kind,
            "status": c.status,
            "caller": c.caller.username if c.caller_id else "",
            "callee": c.callee.username if c.callee_id else "",
            "duration_seconds": c.duration_seconds,
            "started_at": timezone.localtime(c.started_at).strftime("%d/%m/%Y %H:%M"),
        }
        for c in res.calls.select_related("caller", "callee").order_by("-started_at")[:15]
    ]

    dispute = (
        Dispute.objects.filter(Q(reservation=res) | Q(reference=res.reference))
        .order_by("-id")
        .first()
    )
    dispute_data = (
        {
            "reference": dispute.reference,
            "motif": dispute.motif,
            "priorite": dispute.priorite,
            "decision": dispute.decision,
            "description": dispute.description,
        }
        if dispute
        else None
    )

    # Suggestions Smart Matching (Top 3 artisans reels)
    matches = []
    if res.statut not in ("Terminee", "DONE", "Annulee", "CANCELLED"):
        for ms in MatchingService.recommend_for_reservation(res, limit=3):
            p = ms.provider
            matches.append(
                {
                    "provider_id": p.pk,
                    "nom": p.nom,
                    "specialite": p.specialite,
                    "ville": p.ville,
                    "tier": ms.tier,
                    "commission_pct": ms.commission_pct,
                    "score": ms.score,
                    "distance_km": ms.distance_km,
                    "fiabilite_score": p.fiabilite_score,
                    "average_rating": round(float(p.average_rating or 0), 2),
                    "reasons": ms.reasons,
                    "breakdown": ms.breakdown,
                }
            )

    return JsonResponse(
        {
            "reservation": {
                "id": res.pk,
                "reference": res.reference,
                "title": res.title or res.reference,
                "statut": res.statut,
                "demande_type": res.demande_type,
                "client": res.client,
                "prestataire": res.prestataire,
                "assigned_provider_id": res.assigned_provider_id,
                "montant": float(res.montant or 0),
                "montant_verse": float(res.montant_verse or 0),
                "montant_restant": float(res.montant_restant or 0),
                "remise_fidelite": float(res.remise_fidelite or 0),
                "caution_montant": float(res.caution_montant or 0),
                "caution_payee": bool(res.caution_payee),
                "visite_effectuee": bool(res.visite_effectuee),
                "visite_suspecte": bool(res.visite_suspecte),
                "visite_suspecte_motif": res.visite_suspecte_motif,
                "payment_type": res.payment_type,
                "mobile_money_operator": res.mobile_money_operator,
                "funds_released": bool(res.funds_released_at),
                "refund_owed_fcfa": float(res.refund_owed_fcfa or 0),
                "refund_status": res.refund_status,
                "is_urgent": bool(res.is_urgent),
                "description_probleme": res.description_probleme or res.client_message,
                "disponibilites_client": res.disponibilites_client,
                "address_label": res.address_label,
                "address_quartier": res.address_quartier,
                "address_ville": res.address_ville,
                "address_repere": res.address_repere,
                "latitude": res.latitude,
                "longitude": res.longitude,
                "created_at": timezone.localtime(res.created_at).strftime("%d/%m/%Y %H:%M"),
                "bon_commande_url": f"/api/reservations/{res.reference}/bon-de-commande/pdf/",
            },
            "privacy_notice": "Messagerie privee chiffree client-prestataire non exposee (Loi n° 2013-450).",
            "history": history_rows,
            "devis": devis_list,
            "payments": payments,
            "calls": calls,
            "dispute": dispute_data,
            "smart_matches": matches,
        }
    )


@login_required
@require_GET
def api_admin_matching_simulate(request):
    """GET /api/admin/matching/simulate/
    Permet a l'admin de tester le moteur reel de matching (criteres ou reservation existante).
    """
    if not _is_staff(request.user):
        return JsonResponse({"error": "admin_required"}, status=403)

    ref = (request.GET.get("reservation_ref") or "").strip()
    if ref:
        res = Reservation.objects.filter(reference=ref).first()
        if not res:
            return JsonResponse({"error": "reservation_not_found"}, status=404)
        ranked = MatchingService.recommend_for_reservation(res, limit=8)
        mode = "reservation"
    else:
        q = (request.GET.get("q") or "").strip()
        cat_raw = (request.GET.get("category_id") or "").strip()
        cat_id = int(cat_raw) if cat_raw.isdigit() else None
        city = (request.GET.get("ville") or "").strip()
        only_avail = request.GET.get("only_available", "1") != "0"

        def _f(name):
            v = (request.GET.get(name) or "").strip()
            try:
                return float(v) if v else None
            except ValueError:
                return None

        criteria = MatchingCriteria(
            category_id=cat_id,
            query=q,
            lat=_f("lat"),
            lon=_f("lon"),
            client_city=city,
            price_max=_f("price_max"),
            adaptive_radius=True,
            only_available=only_avail,
        )
        ranked = MatchingService.recommend_providers(criteria, limit=10)
        mode = "criteria"

    results = []
    for idx, ms in enumerate(ranked, start=1):
        p = ms.provider
        results.append(
            {
                "rank": idx,
                "provider_id": p.pk,
                "nom": p.nom,
                "specialite": p.specialite,
                "category": p.category.nom if p.category_id else "",
                "ville": p.ville,
                "tarif_horaire": float(p.tarif_horaire) if p.tarif_horaire is not None else None,
                "score": ms.score,
                "distance_km": ms.distance_km,
                "same_city": ms.same_city,
                "availability_score": ms.availability_score,
                "fiabilite_score": p.fiabilite_score,
                "average_rating": round(float(p.average_rating or 0), 2),
                "rating_count": p.rating_count,
                "tier": ms.tier,
                "commission_pct": ms.commission_pct,
                "is_certified": bool(p.is_certified),
                "reasons": ms.reasons,
                "breakdown": ms.breakdown,
            }
        )

    return JsonResponse({"ok": True, "mode": mode, "count": len(results), "results": results})


@login_required
@require_http_methods(["POST"])
def api_admin_reservation_assign(request, reference):
    """POST /api/admin/reservations/<ref>/assign/
    Affecte un prestataire specifique ou le #1 Smart Matching a une reservation.
    """
    if not _is_staff(request.user):
        return JsonResponse({"error": "admin_required"}, status=403)

    res = Reservation.objects.filter(reference=reference).first()
    if not res:
        return JsonResponse({"error": "reservation_not_found"}, status=404)

    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        payload = {}

    pid = payload.get("provider_id")
    prov = None
    if pid is not None and str(pid).isdigit():
        prov = Provider.objects.filter(
            pk=int(pid), statut=Provider.Status.VALID, is_deleted=False
        ).first()
    elif payload.get("auto"):
        matches = MatchingService.recommend_for_reservation(res, limit=1)
        prov = matches[0].provider if matches else None

    if not prov:
        return JsonResponse(
            {"error": "no_matching_provider", "message": "Aucun prestataire valide trouve pour cette demande."},
            status=400,
        )

    _apply_provider_assignment(
        res,
        prov,
        request.user,
        source="auto_smart_match" if payload.get("auto") else "admin_manual_smart",
    )
    return JsonResponse(
        {
            "ok": True,
            "reference": res.reference,
            "assigned_provider": {"id": prov.pk, "nom": prov.nom, "specialite": prov.specialite},
        }
    )


@login_required
@require_GET
def api_admin_push_stats(request):
    """GET /api/admin/push-stats/ : statistiques FCM reelles et apercu audience."""
    if not _is_staff(request.user):
        return JsonResponse({"error": "admin_required"}, status=403)

    dt_qs = DeviceToken.objects.all()
    role = (request.GET.get("role") or "").strip().lower()
    user_qs = User.objects.filter(is_active=True)
    if role in ("client", "prestataire"):
        user_qs = user_qs.filter(profile__role=role)
    target_ids = list(user_qs.values_list("id", flat=True))
    reach_devices = dt_qs.filter(user_id__in=target_ids).values("user_id").distinct().count()

    return JsonResponse(
        {
            "ok": True,
            "role": role or "tous",
            "estimated_users": len(target_ids),
            "estimated_fcm_devices": reach_devices,
            "platforms": {
                "android": dt_qs.filter(platform=DeviceToken.Platform.ANDROID).count(),
                "ios": dt_qs.filter(platform=DeviceToken.Platform.IOS).count(),
                "web": dt_qs.filter(platform=DeviceToken.Platform.WEB).count(),
            },
        }
    )


@require_GET
def api_public_config(request):
    """GET /api/public/config/ et /api/config/ :
    Configuration dynamique plateforme pour apps Client, Prestataire et Vitrine.
    """
    return JsonResponse(build_public_platform_config())

