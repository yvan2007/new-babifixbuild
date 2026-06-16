"""
BABIFIX — Vues API Finance & Business
  - Parrainage : GET code + stats, POST appliquer code
  - Premium prestataire : GET tiers, POST souscrire
  - Urgence : surcharge +20% au moment de la réservation
  - Analytics plateforme : revenus BABIFIX, KPIs
  - Voice comment : POST upload note vocale sur avis
  - Multi-devis : GET comparaison des devis d'une réservation
  - Retraits admin : GET pending, POST valider
"""

import json
import logging
import os
import uuid
from decimal import Decimal

from django.contrib.auth.decorators import login_required
from django.http import JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_GET, require_http_methods

from .auth import require_api_auth
from .models import (
    Payment,
    PlatformRevenue,
    Provider,
    Reservation,
    UserProfile,
    WalletTransaction,
)

logger = logging.getLogger(__name__)

URGENCE_SURCHARGE_PCT = 20   # +20% sur le montant si demande urgente


# =============================================================================
# PARRAINAGE — GET /api/auth/referral/  |  POST /api/auth/referral/apply/
# =============================================================================

@csrf_exempt
@require_api_auth(["client", "prestataire", "admin"])
def api_referral(request):
    """
    GET  → code parrainage + stats (filleuls, crédits)
    POST → appliquer un code reçu (inscription tardive)
    """
    from django.contrib.auth.models import User
    from .services.referral_service import ReferralService

    user_id = request.api_user_id
    try:
        user = User.objects.get(pk=user_id)
    except User.DoesNotExist:
        return JsonResponse({"error": "user_not_found"}, status=404)

    if request.method == "GET":
        # Générer un code si inexistant
        profile, _ = UserProfile.objects.get_or_create(user=user)
        if not profile.referral_code:
            result = ReferralService.create_referral_code(user)
        stats = ReferralService.get_referral_stats(user)
        return JsonResponse(stats, status=200)

    if request.method == "POST":
        try:
            body = json.loads(request.body)
        except (json.JSONDecodeError, TypeError):
            return JsonResponse({"error": "invalid_json"}, status=400)

        code = str(body.get("code") or "").strip()
        if not code:
            return JsonResponse({"error": "code_required"}, status=400)

        result = ReferralService.apply_referral_code(code, user)
        if result.success:
            return JsonResponse({"ok": True, "message": "Code appliqué avec succès"}, status=200)
        return JsonResponse({"error": result.error}, status=400)

    return JsonResponse({"error": "method_not_allowed"}, status=405)


# =============================================================================
# PREMIUM PRESTATAIRE — GET /api/prestataire/premium/tiers/
#                       POST /api/prestataire/premium/subscribe/
# =============================================================================

@require_api_auth(["prestataire", "admin"])
@require_GET
def api_premium_tiers(request):
    """GET → liste des offres premium disponibles."""
    from .services.provider_subscription_service import ProviderSubscriptionService
    tiers = ProviderSubscriptionService.get_available_tiers()
    return JsonResponse({"tiers": tiers}, status=200)


@csrf_exempt
@require_api_auth(["prestataire", "admin"])
def api_premium_subscribe(request):
    """
    GET  → statut abonnement actuel
    POST → souscrire/changer tier {tier: 'bronze'|'silver'|'gold', duration_days: 30}
    Paiement déduit du wallet prestataire (ou initié via GeniusPay si insuffisant).
    """
    from .services.provider_subscription_service import ProviderSubscriptionService, PREMIUM_TIERS
    from .services.wallet_service import WalletService

    user_id = request.api_user_id
    provider = Provider.objects.filter(user_id=user_id).first()
    if not provider:
        return JsonResponse({"error": "provider_not_found"}, status=404)

    if request.method == "GET":
        sub = ProviderSubscriptionService.get_subscription(provider)
        return JsonResponse({
            "is_premium": provider.is_premium,
            "tier": provider.premium_tier or "standard",
            "premium_since": provider.premium_since.isoformat() if provider.premium_since else None,
            "premium_until": provider.premium_until.isoformat() if provider.premium_until else None,
            "days_remaining": max(
                0,
                (provider.premium_until - timezone.now()).days
                if provider.premium_until and provider.premium_until > timezone.now()
                else 0,
            ),
            "commission_effective": float(
                ProviderSubscriptionService.calculate_effective_commission(provider)
            ),
        }, status=200)

    if request.method == "POST":
        try:
            body = json.loads(request.body)
        except (json.JSONDecodeError, TypeError):
            return JsonResponse({"error": "invalid_json"}, status=400)

        tier = str(body.get("tier") or "").lower()
        duration_days = int(body.get("duration_days") or 30)

        # Retour au palier gratuit (résiliation)
        if tier == "standard":
            provider.is_premium = False
            provider.premium_tier = ""
            provider.save(update_fields=["is_premium", "premium_tier"])
            return JsonResponse({
                "ok": True,
                "tier": "standard",
                "premium_until": None,
                "commission_effective": float(
                    ProviderSubscriptionService.calculate_effective_commission(provider)
                ),
            }, status=200)

        if tier not in PREMIUM_TIERS:
            return JsonResponse({"error": "tier_invalide", "valid": list(PREMIUM_TIERS.keys())}, status=400)

        price = Decimal(str(PREMIUM_TIERS[tier]["price"]))

        # Tenter de débiter le wallet
        if (provider.solde_fcfa or Decimal("0")) >= price:
            from django.db import transaction
            with transaction.atomic():
                prov = Provider.objects.select_for_update().get(pk=provider.pk)
                prov.solde_fcfa -= price
                prov.save(update_fields=["solde_fcfa"])
                WalletTransaction.objects.create(
                    provider=prov,
                    tx_type="debit",
                    amount_fcfa=price,
                    reference=f"PREMIUM-{tier}",
                    description=f"Souscription abonnement Premium {tier.title()} ({duration_days}j)",
                    status="success",
                )
            # Enregistrer dans les revenus BABIFIX
            WalletService.credit_provider_premium(provider, tier, price)
        else:
            # Solde insuffisant → retourner les infos pour paiement Mobile Money (GeniusPay)
            return JsonResponse({
                "error": "insufficient_wallet",
                "price": float(price),
                "solde_actuel": float(provider.solde_fcfa or 0),
                "message": "Solde insuffisant. Veuillez recharger votre wallet ou payer via Mobile Money.",
                "geniuspay_required": True,
                "tier": tier,
                "duration_days": duration_days,
            }, status=402)

        result = ProviderSubscriptionService.subscribe(provider, tier, duration_days)
        if not result.success:
            return JsonResponse({"error": result.error}, status=500)

        # Notification push
        try:
            from .push_dispatch import _schedule
            _schedule(
                [provider.user_id],
                "BABIFIX Premium activé !",
                f"Votre abonnement {tier.title()} est actif jusqu'au {provider.premium_until.strftime('%d/%m/%Y')}.",
                {
                    "type": "premium.activated",
                    "tier": tier,
                    "route": "/prestataire/premium",
                },
            )
        except Exception:
            pass

        return JsonResponse({
            "ok": True,
            "tier": tier,
            "premium_until": provider.premium_until.isoformat() if provider.premium_until else None,
            "commission_effective": float(
                ProviderSubscriptionService.calculate_effective_commission(provider)
            ),
        }, status=200)

    return JsonResponse({"error": "method_not_allowed"}, status=405)


# =============================================================================
# CALCULATEUR DE RENTABILITÉ PREMIUM — GET /api/prestataire/premium/calculator/
# =============================================================================

@require_api_auth(["prestataire", "admin"])
@require_GET
def api_premium_calculator(request):
    """
    Calcule, à partir de l'activité réelle (GMV des 30 derniers jours), l'intérêt
    économique de chaque palier payant et la formule recommandée pour ce prestataire.
    """
    from .services.provider_subscription_service import ProviderSubscriptionService

    provider = Provider.objects.filter(user_id=request.api_user_id).first()
    if not provider:
        return JsonResponse({"error": "provider_not_found"}, status=404)

    return JsonResponse(ProviderSubscriptionService.profitability(provider), status=200)


# =============================================================================
# FIDÉLITÉ CLIENT — GET/POST /api/client/fidelite/
# =============================================================================

# Niveaux de fidélité : (seuil_min, nom, couleur, réduction %)
FIDELITE_NIVEAUX = [
    (0, "Bronze", "#CD7F32", 0),
    (5, "Argent", "#64748B", 5),
    (10, "Or", "#F59E0B", 10),
    (20, "Platine", "#A855F7", 15),
]

FIDELITE_GARANTIES = [
    {"icon": "verified_rounded", "titre": "Prestataires vérifiés",
     "description": "Identité contrôlée (CNI + photo) et dossier validé par BABIFIX avant toute mission."},
    {"icon": "lock_rounded", "titre": "Paiement sécurisé",
     "description": "Votre argent est encadré et libéré uniquement une fois la prestation confirmée."},
    {"icon": "support_agent_rounded", "titre": "Litige sous 48 h",
     "description": "Un souci ? Ouvrez un litige : BABIFIX tranche (remboursement, partage ou libération)."},
    {"icon": "star_rounded", "titre": "Notation transparente",
     "description": "Chaque prestataire est noté par les clients après chaque intervention."},
]


def _fidelite_niveau(nb_missions: int):
    """Retourne (niveau_courant, prochain_niveau, prochain_seuil)."""
    current = FIDELITE_NIVEAUX[0]
    nxt = None
    for i, niv in enumerate(FIDELITE_NIVEAUX):
        if nb_missions >= niv[0]:
            current = niv
            nxt = FIDELITE_NIVEAUX[i + 1] if i + 1 < len(FIDELITE_NIVEAUX) else None
    return current, nxt


@require_api_auth(["client", "admin"])
@require_GET
def api_client_fidelite(request):
    """GET → programme de fidélité du client : niveau, réduction, garanties, parrainage."""
    from django.contrib.auth.models import User
    from .models import UserProfile
    from .services.referral_service import ReferralService
    from .services.fidelite_service import FideliteService

    try:
        user = User.objects.get(pk=request.api_user_id)
    except User.DoesNotExist:
        return JsonResponse({"error": "user_not_found"}, status=404)

    nb_missions = Reservation.objects.filter(
        client_user_id=user.id, statut=Reservation.Status.DONE
    ).count()

    current, nxt = _fidelite_niveau(nb_missions)

    # S'assurer que le client a un code de parrainage
    profile = UserProfile.objects.filter(user=user).first()
    if profile and not profile.referral_code:
        try:
            ReferralService.create_referral_code(user)
        except Exception:
            pass
    stats = ReferralService.get_referral_stats(user)
    points = FideliteService.summary(user)

    return JsonResponse({
        "niveau": current[1],
        "couleur": current[2],
        "reduction_pct": current[3],
        "nb_reservations": nb_missions,
        "prochain_niveau": nxt[1] if nxt else None,
        "prochain_seuil": nxt[0] if nxt else None,
        "garanties": FIDELITE_GARANTIES,
        "referral_code": stats.get("code") or "",
        "referral_credits": stats.get("credits_earned", 0),
        "filleuls_count": stats.get("filleuls", 0),
        # Bonus : compteur de points cumulés (1 pt / 1 000 F dépensés)
        "points": points.get("points", 0),
    }, status=200)


# =============================================================================
# VOICE NOTE SUR AVIS — POST /api/client/reservations/<ref>/rating-voice/
# =============================================================================

@csrf_exempt
@require_api_auth(["client", "admin"])
def api_rating_voice_upload(request, reference):
    """
    POST multipart/form-data avec fichier audio (field name: 'voice_note').
    Enregistre l'URL de la note vocale sur le Rating existant.
    """
    if request.method != "POST":
        return JsonResponse({"error": "method_not_allowed"}, status=405)

    from django.conf import settings
    from .models import Rating

    user_id = request.api_user_id
    try:
        reservation = Reservation.objects.get(reference=reference, client_user_id=user_id)
    except Reservation.DoesNotExist:
        return JsonResponse({"error": "reservation_not_found"}, status=404)

    try:
        rating = Rating.objects.get(reservation=reservation)
    except Rating.DoesNotExist:
        return JsonResponse({"error": "rating_not_found", "message": "Notez d'abord la prestation"}, status=404)

    audio_file = request.FILES.get("voice_note")
    if not audio_file:
        return JsonResponse({"error": "voice_note_file_required"}, status=400)

    # Valider le type
    allowed_types = {"audio/mpeg", "audio/mp4", "audio/ogg", "audio/wav", "audio/webm"}
    if audio_file.content_type not in allowed_types:
        return JsonResponse({"error": "invalid_audio_type"}, status=400)

    # Max 5 MB
    if audio_file.size > 5 * 1024 * 1024:
        return JsonResponse({"error": "file_too_large", "max_mb": 5}, status=400)

    ext_map = {
        "audio/mpeg": "mp3", "audio/mp4": "m4a", "audio/ogg": "ogg",
        "audio/wav": "wav", "audio/webm": "webm",
    }
    ext = ext_map.get(audio_file.content_type, "audio")
    filename = f"{uuid.uuid4().hex}.{ext}"
    name = f"voice_notes/{filename}"

    # Stockage par défaut = Cloudinary si configuré (persistant), sinon disque local.
    from django.core.files.storage import default_storage

    storage = default_storage
    if "cloudinary" in type(storage).__module__.lower():
        # Cloudinary traite l'audio comme une ressource « video ».
        try:
            from cloudinary_storage.storage import VideoMediaCloudinaryStorage

            storage = VideoMediaCloudinaryStorage()
        except Exception:
            storage = default_storage
    try:
        saved_name = storage.save(name, audio_file)
        voice_url = storage.url(saved_name)
    except Exception:
        # Repli disque local.
        save_dir = os.path.join(settings.MEDIA_ROOT, "voice_notes")
        os.makedirs(save_dir, exist_ok=True)
        filepath = os.path.join(save_dir, filename)
        audio_file.seek(0)
        with open(filepath, "wb") as f:
            for chunk in audio_file.chunks():
                f.write(chunk)
        voice_url = f"{settings.MEDIA_URL}voice_notes/{filename}"

    rating.voice_note_url = voice_url
    rating.save(update_fields=["voice_note_url"])

    return JsonResponse({"ok": True, "voice_note_url": voice_url}, status=200)


# =============================================================================
# ANALYTICS PLATEFORME — GET /api/admin/platform-revenue/
# =============================================================================

@login_required
@require_GET
def api_admin_platform_revenue(request):
    """Revenus BABIFIX, retraits en attente, KPIs (admin uniquement)."""
    from .services.wallet_service import WalletService
    from django.db.models import Sum, Count, Avg
    from django.contrib.auth.models import User

    days = int(request.GET.get("days", 30))
    summary = WalletService.get_platform_summary(days)

    # KPIs globaux
    total_providers = Provider.objects.filter(is_deleted=False, statut="Valide").count()
    premium_providers = Provider.objects.filter(is_premium=True, is_deleted=False).count()
    total_wallet = Provider.objects.aggregate(total=Sum("solde_fcfa"))["total"] or 0

    # Taux de conversion réservations → terminées
    threshold = timezone.now() - timezone.timedelta(days=days)
    total_resa = Reservation.objects.filter(created_at__gte=threshold).count()
    done_resa = Reservation.objects.filter(created_at__gte=threshold, statut="Terminee").count()
    conversion = round(done_resa / total_resa * 100, 1) if total_resa > 0 else 0

    # Top 5 prestataires par revenus générés
    top_providers = list(
        WalletTransaction.objects.filter(
            tx_type="credit",
            created_at__gte=threshold,
        ).values("provider__nom").annotate(
            total=Sum("amount_fcfa"), missions=Count("id")
        ).order_by("-total")[:5]
    )

    # Retraits en attente (à traiter par l'admin)
    pending_withdrawals = list(
        WalletTransaction.objects.filter(tx_type="debit", status="pending").select_related(
            "provider"
        ).order_by("-created_at").values(
            "id", "amount_fcfa", "phone", "operator",
            "provider__nom", "provider__id", "created_at", "description",
        )[:20]
    )

    return JsonResponse({
        **summary,
        "total_providers_actifs": total_providers,
        "premium_providers": premium_providers,
        "total_wallet_providers_fcfa": float(total_wallet),
        "conversion_rate_pct": conversion,
        "reservations_total": total_resa,
        "reservations_terminees": done_resa,
        "top_providers": [
            {
                "nom": p["provider__nom"],
                "revenus": float(p["total"] or 0),
                "transactions": p["missions"],
            }
            for p in top_providers
        ],
        "pending_withdrawals": [
            {
                "id": w["id"],
                "amount": float(w["amount_fcfa"]),
                "phone": w["phone"],
                "operator": w["operator"],
                "provider_nom": w["provider__nom"],
                "provider_id": w["provider__id"],
                "created_at": w["created_at"].isoformat() if w["created_at"] else None,
            }
            for w in pending_withdrawals
        ],
    }, status=200)


def _compute_business_kpis(days: int = 30) -> dict:
    """KPIs business BABIFIX (stratégie) : GMV, take rate, missions/jour,
    rétention prestataire M+1, escrow vs espèces, note moyenne / NPS."""
    from django.db.models import Sum, Count, Avg
    from .models import Rating

    now = timezone.now()
    start = now - timezone.timedelta(days=days)
    prev_start = now - timezone.timedelta(days=2 * days)

    # Réservation n'a pas de created_at : on date les missions par prestation_terminee_at.
    done = Reservation.objects.filter(
        statut=Reservation.Status.DONE,
        prestation_terminee_at__isnull=False,
    )
    done_period = done.filter(prestation_terminee_at__gte=start)

    gmv = float(done_period.aggregate(s=Sum("montant"))["s"] or 0)
    missions = done_period.count()
    missions_per_day = round(missions / days, 1) if days else 0

    # Take rate effectif = commission encaissée / GMV
    commission_rev = float(
        PlatformRevenue.objects.filter(source="commission", created_at__gte=start)
        .aggregate(s=Sum("amount_fcfa"))["s"] or 0
    )
    take_rate = round(commission_rev / gmv * 100, 1) if gmv else 0

    # Rétention prestataire M+1 : actifs sur la période précédente ET la période courante
    prev_ids = set(
        done.filter(prestation_terminee_at__gte=prev_start, prestation_terminee_at__lt=start)
        .values_list("assigned_provider_id", flat=True)
    )
    prev_ids.discard(None)
    cur_ids = set(
        done_period.values_list("assigned_provider_id", flat=True)
    )
    cur_ids.discard(None)
    retained = len(prev_ids & cur_ids)
    retention_pct = round(retained / len(prev_ids) * 100, 1) if prev_ids else 0

    # Escrow (Mobile Money / Carte) vs espèces sur les missions terminées
    by_pay = dict(
        done_period.values_list("payment_type").annotate(n=Count("id"))
    )
    cash = by_pay.get("ESPECES", 0)
    escrow = sum(v for k, v in by_pay.items() if k != "ESPECES")
    total_pay = cash + escrow
    escrow_pct = round(escrow / total_pay * 100, 1) if total_pay else 0
    cash_pct = round(cash / total_pay * 100, 1) if total_pay else 0

    # Note moyenne + NPS (promoteurs note>=4 − détracteurs note<=2)
    ratings = Rating.objects.filter(created_at__gte=start)
    nb_ratings = ratings.count()
    avg_rating = round(float(ratings.aggregate(a=Avg("note"))["a"] or 0), 2)
    if nb_ratings:
        promoters = ratings.filter(note__gte=4).count()
        detractors = ratings.filter(note__lte=2).count()
        nps = round((promoters - detractors) / nb_ratings * 100)
    else:
        nps = 0

    # Premium
    premium_silver = Provider.objects.filter(is_premium=True, premium_tier="silver").count()
    premium_gold = Provider.objects.filter(is_premium=True, premium_tier="gold").count()

    def _fmt(n):
        return f"{int(round(n)):,}".replace(",", " ")

    return {
        "period_days": days,
        "gmv_fcfa": round(gmv),
        "gmv_display": _fmt(gmv),
        "missions": missions,
        "missions_per_day": missions_per_day,
        "commission_revenue_fcfa": round(commission_rev),
        "commission_display": _fmt(commission_rev),
        "take_rate_pct": take_rate,
        "retention_m1_pct": retention_pct,
        "retention_base": len(prev_ids),
        "escrow_pct": escrow_pct,
        "cash_pct": cash_pct,
        "escrow_count": escrow,
        "cash_count": cash,
        "avg_rating": avg_rating,
        "nb_ratings": nb_ratings,
        "nps": nps,
        "premium_silver": premium_silver,
        "premium_gold": premium_gold,
    }


@login_required
@require_GET
def api_admin_business_kpis(request):
    """GET /api/admin/business-kpis/ — KPIs business (JSON)."""
    try:
        days = max(1, min(365, int(request.GET.get("days", 30))))
    except (TypeError, ValueError):
        days = 30
    return JsonResponse(_compute_business_kpis(days), status=200)


@login_required
def kpi_dashboard_page(request):
    """Page admin : tableau de bord des KPIs business."""
    if not (request.user.is_staff or request.user.is_superuser):
        from django.http import HttpResponseForbidden
        return HttpResponseForbidden("Accès réservé aux administrateurs BABIFIX.")
    from django.shortcuts import render
    try:
        days = max(1, min(365, int(request.GET.get("days", 30))))
    except (TypeError, ValueError):
        days = 30
    kpis = _compute_business_kpis(days)
    return render(request, "adminpanel/kpi_dashboard.html", {"kpis": kpis, "days": days})


@csrf_exempt
@login_required
def api_admin_validate_withdrawal(request, tx_id):
    """
    POST /api/admin/wallet/withdrawals/<tx_id>/validate/
    Marque un retrait comme traité (après virement Manuel ou API Mobile Money).
    """
    if request.method != "POST":
        return JsonResponse({"error": "method_not_allowed"}, status=405)

    try:
        tx = WalletTransaction.objects.select_related("provider").get(
            pk=tx_id, tx_type="debit", status="pending"
        )
    except WalletTransaction.DoesNotExist:
        return JsonResponse({"error": "transaction_not_found"}, status=404)

    tx.status = "success"
    tx.save(update_fields=["status"])

    # Notifier le prestataire
    try:
        from .push_dispatch import _schedule
        _schedule(
            [tx.provider.user_id],
            "BABIFIX — Retrait effectué",
            f"Votre retrait de {tx.amount_fcfa:,.0f} FCFA via {tx.operator.upper()} a été traité.",
            {
                "type": "wallet.withdrawal_done",
                "tx_id": str(tx.pk),
                "route": "/prestataire/wallet",
            },
        )
    except Exception:
        pass

    # WebSocket temps réel
    try:
        from asgiref.sync import async_to_sync
        from channels.layers import get_channel_layer
        channel_layer = get_channel_layer()
        async_to_sync(channel_layer.group_send)(
            f"prestataire_{tx.provider.user_id}",
            {
                "type": "prestataire_notify",
                "event_type": "wallet.withdrawal_done",
                "payload": {"tx_id": tx.pk, "amount": float(tx.amount_fcfa), "status": "success"},
            },
        )
    except Exception:
        pass

    return JsonResponse({"ok": True, "tx_id": tx_id, "status": "success"}, status=200)


# =============================================================================
# MULTI-DEVIS — GET /api/client/reservations/<ref>/devis/compare/
# =============================================================================

@require_api_auth(["client", "admin"])
@require_GET
def api_client_devis_compare(request, reference):
    """
    Retourne tous les devis d'une réservation pour comparaison côté client.
    Inclut le prestataire (note, certifié, premium) et les lignes du devis.
    """
    from .models import Devis

    user_id = request.api_user_id
    try:
        reservation = Reservation.objects.get(reference=reference, client_user_id=user_id)
    except Reservation.DoesNotExist:
        return JsonResponse({"error": "reservation_not_found"}, status=404)

    devis_qs = (
        Devis.objects.filter(reservation=reservation, statut__in=["ENVOYE", "ACCEPTE", "BROUILLON"])
        .select_related("prestataire")
        .prefetch_related("lignes")
        .order_by("total_ttc")
    )

    result = []
    for d in devis_qs:
        lignes = [
            {
                "type": l.type_ligne,
                "description": l.description,
                "quantite": l.quantite,
                "prix_unitaire": float(l.prix_unitaire),
                "total": float(l.total),
            }
            for l in d.lignes.all()
        ]
        prest = d.prestataire
        result.append({
            "devis_id": d.pk,
            "reference": d.reference,
            "statut": d.statut,
            "diagnostic": d.diagnostic,
            "date_proposee": d.date_proposee.isoformat() if d.date_proposee else None,
            "heure_debut": d.heure_debut.isoformat() if d.heure_debut else None,
            "heure_fin": d.heure_fin.isoformat() if d.heure_fin else None,
            "sous_total": float(d.sous_total),
            "commission": float(d.commission_montant),
            "total_ttc": float(d.total_ttc),
            "net_prestataire": float(d.sous_total - d.commission_montant),
            "note_prestataire": d.note_prestataire,
            "validite_jours": d.validite_jours,
            "lignes": lignes,
            "prestataire": {
                "id": prest.pk,
                "nom": prest.nom,
                "specialite": prest.specialite,
                "note": float(prest.average_rating or 0),
                "nb_avis": prest.rating_count or 0,
                "is_certified": prest.is_certified,
                "is_premium": prest.is_premium,
                "premium_tier": prest.premium_tier or "",
                "photo": prest.photo_portrait_url or "",
            },
        })

    return JsonResponse({
        "reservation_reference": reference,
        "nb_devis": len(result),
        "devis": result,
        "recommande": result[0]["devis_id"] if result else None,
    }, status=200)


# =============================================================================
# URGENCE — appliqué dans api_client_create_reservation (views.py patch)
# Endpoint séparé pour vérifier le surcoût avant de valider la demande
# GET /api/client/reservations/urgence-preview/?montant=X
# =============================================================================

@require_api_auth(["client", "admin"])
@require_GET
def api_urgence_preview(request):
    """Calcule l'aperçu du prix avec surcharge urgence (+20%)."""
    try:
        montant = Decimal(str(request.GET.get("montant", "0")))
    except Exception:
        return JsonResponse({"error": "montant_invalide"}, status=400)

    if montant <= 0:
        return JsonResponse({"error": "montant_must_be_positive"}, status=400)

    surcharge = montant * URGENCE_SURCHARGE_PCT / 100
    total = montant + surcharge

    return JsonResponse({
        "montant_base": float(montant),
        "surcharge_pct": URGENCE_SURCHARGE_PCT,
        "surcharge_fcfa": float(surcharge),
        "total_avec_urgence": float(total),
        "message": f"Demande urgente : +{URGENCE_SURCHARGE_PCT}% ({surcharge:,.0f} FCFA)",
    }, status=200)
