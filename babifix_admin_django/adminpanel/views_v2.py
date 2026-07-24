"""
BABIFIX — Nouvelles fonctionnalités v2
  1.  GET  /api/client/reservations               — historique réservations client
  2.  GET  /api/client/reservations/<ref>          — détail réservation + statut temps réel
  3.  POST /api/client/reservations/<ref>/cancel   — annulation réservation
  4.  POST /api/client/reservations/<ref>/dispute  — ouvrir un litige
  5.  POST /api/auth/forgot-password               — demande reset mot de passe
  6.  POST /api/auth/reset-password                — confirmer reset avec token
  7.  POST /api/auth/refresh                       — refresh token JWT
  8.  GET  /api/auth/verify-email/<token>          — confirmer email
  9.  PATCH /api/prestataire/profile               — modifier profil prestataire
  10. GET  /api/prestataire/portfolio              — galerie réalisations prestataire
  11. POST /api/prestataire/portfolio              — ajouter photo réalisation
  12. DELETE /api/prestataire/portfolio/<idx>      — supprimer photo réalisation
  13. POST /api/prestataire/reservations/<ref>/rate-client — noter le client
  14. GET  /api/client/notifications               — notifications persistantes client
  15. POST /api/admin/push-broadcast               — push notif manuelle tous users
"""

import json
import logging
import re
import secrets
import uuid
from datetime import timedelta

from django.contrib.auth.models import User
from django.db import transaction
from django.http import JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_GET, require_http_methods

from .auth import (
    create_refresh_token,
    create_token,
    require_api_auth,
    verify_refresh_token,
    verify_token,
)
from .models import (
    DeviceToken,
    Dispute,
    Notification,
    Provider,
    Rating,
    Reservation,
    UserProfile,
    WalletTransaction,
    recalc_provider_rating_stats,
)
from .push_dispatch import _schedule

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────────────────
# Version minimale des apps (force update) — public, sans auth.
# Pilotable par variables d'environnement, sans redéploiement de code.
# ─────────────────────────────────────────────────────────────────────────────
@require_http_methods(["GET"])
def api_app_version(request):
    """Renvoie la version minimale requise + la dernière version par app/plateforme.

    L'app compare sa version installée à `min_version` ; si elle est
    inférieure, elle affiche un écran de mise à jour bloquant.
    Paramètre `?app=client|prestataire` (défaut: client).
    """
    import os

    app = (request.GET.get("app", "client") or "client").strip().lower()
    prefix = "PRESTA" if app.startswith("presta") else "CLIENT"

    def _env(name, default=""):
        return os.getenv(f"APP_{prefix}_{name}", os.getenv(f"APP_{name}", default))

    return JsonResponse(
        {
            "app": app,
            "android": {
                "min_version": _env("MIN_VERSION_ANDROID", "1.0.0"),
                "latest_version": _env("LATEST_VERSION_ANDROID", "1.0.0"),
                "store_url": _env(
                    "STORE_URL_ANDROID",
                    "https://play.google.com/store/apps/details?id=ci.babifix",
                ),
            },
            "ios": {
                "min_version": _env("MIN_VERSION_IOS", "1.0.0"),
                "latest_version": _env("LATEST_VERSION_IOS", "1.0.0"),
                "store_url": _env("STORE_URL_IOS", ""),
            },
            "message": _env(
                "UPDATE_MESSAGE",
                "Une nouvelle version de BABIFIX est disponible. Mettez à jour pour continuer.",
            ),
        }
    )


@csrf_exempt
@require_http_methods(["POST"])
def api_app_log_error(request):
    """Reçoit les crashs des apps mobiles et les journalise (logger.error).

    Si Sentry est actif côté serveur, ces erreurs y remontent automatiquement
    (intégration logging). Alternative légère à sentry_flutter (qui cassait le
    build mobile). Public + rate-limité ; ne renvoie jamais d'erreur à l'app.
    """
    from .throttle import check_rate_limit

    if check_rate_limit(request, "log_error", max_requests=20, window=60):
        return JsonResponse({"ok": True})  # silencieux : on ignore le surplus
    try:
        p = json.loads(request.body or b"{}")
    except json.JSONDecodeError:
        return JsonResponse({"ok": True})
    msg = str(p.get("message", ""))[:500]
    stack = str(p.get("stack", ""))[:4000]
    app = str(p.get("app", ""))[:20]
    version = str(p.get("version", ""))[:20]
    platform = str(p.get("platform", ""))[:20]
    logger.error("MOBILE[%s/%s v%s] %s\n%s", app, platform, version, msg, stack)
    return JsonResponse({"ok": True})


# ─────────────────────────────────────────────────────────────────────────────
# Helpers internes
# ─────────────────────────────────────────────────────────────────────────────


def _frais_mise_en_relation_config() -> float:
    """Frais fixe de mise en relation (config plateforme) — pour l'app client,
    affiché AVANT le paiement de la caution (transport + frais = total)."""
    try:
        from .models import PlatformConfig
        return float(PlatformConfig.get_solo().frais_mise_en_relation_fcfa or 0)
    except Exception:
        return 500.0


def _res_to_dict(res: Reservation, uid: int, frais_mise_en_relation: float | None = None) -> dict:
    """Sérialise une Reservation pour l'API client."""
    has_rating = hasattr(res, "rating") and res.rating is not None
    if frais_mise_en_relation is None:
        frais_mise_en_relation = _frais_mise_en_relation_config()
    return {
        "id": res.pk,
        "reference": res.reference,
        "title": res.title or res.reference,
        "prestataire": res.prestataire,
        "prestataire_id": res.assigned_provider_id,
        "montant": res.montant,
        "statut": res.statut,
        "payment_type": res.payment_type,
        "mobile_money_operator": res.mobile_money_operator,
        "address_label": res.address_label,
        "address_street": res.address_street or "",
        "address_quartier": res.address_quartier or "",
        "address_ville": res.address_ville or "",
        "address_pays": res.address_pays or "",
        "address_repere": res.address_repere or "",
        "address_is_approximate": res.address_is_approximate,
        "latitude": res.latitude,
        "longitude": res.longitude,
        "client_message": res.client_message,
        "cash_flow_status": res.cash_flow_status,
        "dispute_ouverte": res.dispute_ouverte,
        # Caution de visite de diagnostic (Phase 3). 0 / False = pas de visite.
        # Phase 5 : la caution = TRANSPORT (100 % presta). Le client paie EN PLUS
        # un frais fixe de mise en relation (config plateforme) → exposé ici pour
        # l'afficher AVANT paiement (transport + frais = total).
        "caution_montant": float(res.caution_montant or 0),
        "caution_motif": res.caution_motif or "",
        "caution_payee": bool(res.caution_payee),
        "caution_deduite": bool(res.caution_deduite),
        "frais_mise_en_relation": frais_mise_en_relation,
        "can_cancel": res.statut
        in ("En attente", "Confirmee", "DEMANDE_ENVOYEE", "DEVIS_EN_COURS",
            "DEVIS_ENVOYE", "VISITE_DIAGNOSTIC"),
        "can_rate": res.statut == "Terminee" and not has_rating,
        "can_dispute": res.statut in ("Terminee", "En cours")
        and not res.dispute_ouverte,
        "rated": has_rating,
        "rating_note": res.rating.note if has_rating else None,
    }


def _get_res_for_client(reference: str, uid: int):
    try:
        return Reservation.objects.select_related("assigned_provider", "rating").get(
            reference=reference, client_user_id=uid
        )
    except Reservation.DoesNotExist:
        return None


# ─────────────────────────────────────────────────────────────────────────────
# 1. GET /api/client/reservations — historique
# ─────────────────────────────────────────────────────────────────────────────
@require_GET
@require_api_auth(["client", "admin"])
def api_client_reservations_list(request):
    """Liste toutes les réservations du client connecté, du plus récent au plus ancien."""
    uid = request.api_user_id
    statut_filter = request.GET.get("statut", "")  # optionnel : ?statut=En attente
    qs = (
        Reservation.objects.filter(client_user_id=uid)
        .select_related("assigned_provider", "rating")
        .order_by("-pk")
    )
    if statut_filter:
        qs = qs.filter(statut=statut_filter)
    frais_mise_en_relation = _frais_mise_en_relation_config()
    return JsonResponse({
        "reservations": [_res_to_dict(r, uid, frais_mise_en_relation) for r in qs]
    })


# ─────────────────────────────────────────────────────────────────────────────
# 2. GET /api/client/reservations/<ref> — détail
# ─────────────────────────────────────────────────────────────────────────────
@require_GET
@require_api_auth(["client", "admin"])
def api_client_reservation_detail(request, reference):
    uid = request.api_user_id
    res = _get_res_for_client(reference, uid)
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)
    data = _res_to_dict(res, uid)
    data.update(_res_receipt_extras(res))
    return JsonResponse(data)


def _res_receipt_extras(res: Reservation) -> dict:
    """Champs complémentaires pour le reçu (parties, lignes, dates, montants).

    Séparé de `_res_to_dict` pour ne pas alourdir la liste : ces requêtes
    (devis, lignes, user) ne sont faites que sur l'écran de détail / reçu.
    """
    # Devis le plus pertinent : ACCEPTE > ENVOYE > dernier en date.
    devis = (
        res.devis_set.filter(statut="ACCEPTE").order_by("-created_at").first()
        or res.devis_set.filter(statut="ENVOYE").order_by("-created_at").first()
        or res.devis_set.order_by("-created_at").first()
    )
    lignes = []
    if devis:
        for li in devis.lignes.all():
            lignes.append(
                {
                    "designation": li.description,
                    "quantite": li.quantite,
                    "prix_unitaire": str(li.prix_unitaire),
                    "total": str(li.total),
                }
            )

    # Date du reçu : prestation terminée > confirmation client > devis > maintenant.
    dt = (
        res.prestation_terminee_at
        or res.client_confirme_prestation_at
        or (devis.created_at if devis else None)
        or timezone.now()
    )

    # Financier exact : le SOUS-TOTAL du reçu = prestation complète (avant toute
    # déduction de caution). `res.montant` est déjà NET de la caution une fois
    # celle-ci déduite → l'utiliser comme sous-total gonflerait le % de
    # commission. On reconstruit donc le total réel.
    from decimal import Decimal as _D
    _caution = res.caution_montant or _D("0")
    if devis and getattr(devis, "total_ttc", None):
        _sous_total = devis.total_ttc
    else:
        _sous_total = (res.montant or _D("0")) + (
            _caution if res.caution_deduite else _D("0")
        )

    # ── Calcul financier EXACT et RÉCONCILIÉ (Phase 5) ──────────────────────
    # Modèle : le TRANSPORT (caution) revient à 100 % au prestataire ; BABIFIX
    # prend un FRAIS FIXE de mise en relation payé EN PLUS par le client à la
    # visite. Sur le devis, la commission (18/13/8 %) porte sur le RESTE réglé
    # via le devis (le transport, déjà versé au presta, en est déduit).
    #   • Client paie au total : sous_total (devis) + frais de mise en relation.
    #   • Prestataire touche    : transport + (reste − commission) = sous_total − commission.
    #   • BABIFIX touche        : frais de mise en relation + commission devis.
    try:
        from .models import PlatformConfig
        _frais_mer = _D(str(PlatformConfig.get_solo().frais_mise_en_relation_fcfa or 0))
    except Exception:
        _frais_mer = _D("500")
    # Frais affiché seulement quand une visite payante a eu lieu.
    _frais_mer = _frais_mer if res.caution_payee else _D("0")
    # Commission sur la caution : SUPPRIMÉE (transport 100 % presta). Conservé à 0
    # pour compatibilité d'affichage des anciennes apps.
    _caution_comm = _D("0")

    # Reste réglé par le client sur le devis = sous-total − transport déjà versé.
    _reste_client = _sous_total - (_caution if res.caution_payee else _D("0"))
    if _reste_client < 0:
        _reste_client = _D("0")

    # Taux de commission de devis : RÉEL figé sur le devis (18/13/8 %).
    _comm_rate = None
    if devis is not None:
        try:
            _comm_rate = int(devis.commission_rate)
        except (TypeError, ValueError):
            _comm_rate = None
    if not _comm_rate:
        _comm_rate = 18

    # Commission de devis sur le RESTE (le transport n'est pas retaxé). Sans
    # caution, reste = sous-total → commission sur le total, comme avant.
    _comm = (_reste_client * _D(_comm_rate) / _D("100")).quantize(_D("1"))

    # Net prestataire = transport (caution) + (reste − commission) = sous_total − commission.
    _net_presta = _sous_total - _comm
    if _net_presta < 0:
        _net_presta = _D("0")

    # Remise fidélité éventuelle (absorbée par BABIFIX) déduite de ce que paie
    # le client. Total client = devis + frais − remise fidélité.
    _remise_fid = res.remise_fidelite or _D("0")
    _total_client = _sous_total + _frais_mer - _remise_fid
    if _total_client < 0:
        _total_client = _D("0")

    # Identité du client (nom lisible + e-mail).
    cu = res.client_user
    client_nom = ""
    client_email = ""
    if cu:
        client_nom = (cu.get_full_name() or cu.username or "").strip()
        client_email = cu.email or ""
    if not client_nom:
        client_nom = res.client or "Client"
    if not client_email and "@" in (res.client or ""):
        client_email = res.client

    # Identité du prestataire (depuis le profil Provider).
    prov = res.assigned_provider
    presta_nom = (prov.nom if prov else "") or res.prestataire or "Prestataire"
    presta_email = ""
    presta_spec = ""
    if prov:
        presta_spec = prov.specialite or ""
        if prov.user:
            presta_email = prov.user.email or ""

    return {
        "created_at": dt.isoformat(),
        # Date PRÉVUE choisie par le client (créneau) → date « nécessaire » du
        # reçu ; created_at reste la date de réservation, à titre indicatif.
        "scheduled_date": (
            res.scheduled_date.isoformat() if res.scheduled_date else None
        ),
        "commission": str(_comm),
        "commission_rate": _comm_rate,
        # Sous-total (prestation complète) + caution → reçu au calcul exact.
        "sous_total": str(_sous_total),
        "caution_payee": res.caution_payee,
        "caution_montant": str(_caution),
        "caution_commission": str(_caution_comm),
        "caution_deduite": res.caution_deduite,
        # Frais fixe de mise en relation (payé EN PLUS par le client à la visite).
        "frais_mise_en_relation": str(_frais_mer),
        # Remise fidélité appliquée (absorbée par BABIFIX).
        "remise_fidelite": str(_remise_fid),
        # Total réellement déboursé par le client = devis + frais − remise.
        "total_client": str(_total_client),
        # Net réellement reversé au presta (transport + reste − commission devis).
        "net_prestataire": str(_net_presta),
        # Reste réglé par le client sur le devis après déduction du transport.
        "reste_client": str(_reste_client),
        # Statut du devis (ENVOYE → devis actionnable : accepter / refuser).
        "devis_statut": (devis.statut if devis else None),
        "montant_verse": str(res.montant_verse or 0),
        "montant_restant": str(res.montant_restant or 0),
        "acompte_valide": res.acompte_valide,
        "solde_valide": res.solde_valide,
        "client_data": {
            "nom": client_nom,
            "email": client_email,
            "phone": "",
        },
        "prestataire_data": {
            "nom": presta_nom,
            "email": presta_email,
            "specialite": presta_spec,
            "phone": "",
        },
        "devis": lignes,
        "diagnostic": (devis.diagnostic if devis else "") or res.client_message or "",
    }


# ─────────────────────────────────────────────────────────────────────────────
# 3. POST /api/client/reservations/<ref>/cancel — annuler
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client", "admin"])
def api_client_cancel_reservation(request, reference):
    uid = request.api_user_id
    res = _get_res_for_client(reference, uid)
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)
    if res.statut not in (
        "En attente",
        "Confirmee",
        "DEMANDE_ENVOYEE",
        "DEVIS_EN_COURS",
        "DEVIS_ENVOYE",
        "VISITE_DIAGNOSTIC",
    ):
        return JsonResponse(
            {"error": "cannot_cancel", "statut": res.statut}, status=400
        )
    # Motif d'annulation (optionnel) saisi par le client.
    motif = ""
    try:
        payload = json.loads(request.body or b"{}")
        motif = str(payload.get("motif", "") or "").strip()[:255]
    except (json.JSONDecodeError, TypeError):
        pass
    statut_avant = res.statut
    with transaction.atomic():
        res.statut = Reservation.Status.CANCELLED
        fields = ["statut"]
        if motif:
            res.cancellation_reason = motif
            fields.append("cancellation_reason")

        # ── Règlement de la caution de visite (Phase 3) ──────────────────────
        # Visite déjà effectuée → le presta garde la caution ; sinon → remboursée
        # au client (commission plateforme rendue aussi).
        if (
            res.caution_payee
            and not res.caution_deduite
            and not res.caution_remboursee
            and not res.visite_effectuee
        ):
            res.caution_remboursee = True
            fields.append("caution_remboursee")
            # La plateforme rend sa commission de caution : écriture négative
            # d'offset (le champ refunded_at a été retiré du modèle → on
            # neutralise via un revenu négatif, cohérent avec la compta).
            try:
                from adminpanel.models import PlatformRevenue, Payment
                cpay = Payment.objects.filter(
                    reference__startswith=f"CAUTION-{res.reference}"
                ).first()
                if cpay and (cpay.commission or 0) > 0:
                    PlatformRevenue.objects.create(
                        amount_fcfa=-cpay.commission,
                        source=PlatformRevenue.Source.COMMISSION,
                        reference=res.reference,
                        description=f"Remboursement commission caution {res.reference}",
                        payment=cpay,
                    )
            except Exception:
                pass

        res.save(update_fields=fields)

        # ── Score de fiabilité + détection anti-contournement (Phase 4) ──────
        try:
            from adminpanel.services.reliability_service import ReliabilityService
            _stage = "after_devis" if statut_avant == "DEVIS_ENVOYE" else "before_devis"
            ReliabilityService.on_cancellation(res, by="CLIENT", stage=_stage)
        except Exception:
            pass

        # Notifier le prestataire
        if res.prestataire_user_id:
            Notification.objects.create(
                title=f"Réservation {reference} annulée par le client"
                + (f" — {motif}" if motif else ""),
                user_id=res.prestataire_user_id,
            )
    if res.prestataire_user_id:
        _schedule(
            user_ids=[res.prestataire_user_id],
            title="Réservation annulée",
            body=f"Le client a annulé la réservation {reference}.",
            data={"type": "reservation_cancelled", "reference": reference},
        )
    return JsonResponse({"ok": True, "statut": res.statut})


# ─────────────────────────────────────────────────────────────────────────────
# 4. POST /api/client/reservations/<ref>/dispute — ouvrir un litige
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client", "admin"])
def api_client_open_dispute(request, reference):
    uid = request.api_user_id
    res = _get_res_for_client(reference, uid)
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)
    if res.dispute_ouverte:
        return JsonResponse({"error": "dispute_already_open"}, status=400)
    if res.statut not in ("Terminee", "En cours"):
        return JsonResponse(
            {"error": "cannot_dispute", "statut": res.statut}, status=400
        )
    try:
        payload = json.loads(request.body or b"{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    motif = str(payload.get("motif", "") or "").strip()
    if not motif:
        return JsonResponse({"error": "motif_required"}, status=400)
    ref_litige = f"LIT-{uuid.uuid4().hex[:8].upper()}"
    with transaction.atomic():
        Dispute.objects.create(
            reference=ref_litige,
            motif=motif[:200],
            client=res.client,
            prestataire=res.prestataire,
            priorite=Dispute.Priority.MEDIUM,
            decision=Dispute.Decision.OPEN,
            reservation=res,
        )
        res.dispute_ouverte = True
        res.save(update_fields=["dispute_ouverte"])
        Notification.objects.create(title=f"Nouveau litige {ref_litige} : {reference}")
    return JsonResponse({"ok": True, "litige_reference": ref_litige})


# ─────────────────────────────────────────────────────────────────────────────
# 5. POST /api/auth/forgot-password — demander un reset
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["POST"])
def api_auth_forgot_password(request):
    # Anti-spam / anti-énumération : limiter les demandes de réinitialisation.
    from .throttle import check_rate_limit, rate_limited_response
    if check_rate_limit(request, "forgot_password", max_requests=4, window=300):
        return rate_limited_response()
    try:
        payload = json.loads(request.body or b"{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    email = str(payload.get("email", "") or "").strip().lower()
    if not email:
        return JsonResponse({"error": "email_required"}, status=400)
    # Toujours répondre ok pour ne pas révéler si l'email existe
    user = User.objects.filter(email__iexact=email).first()
    if user:
        token = secrets.token_urlsafe(32)
        profile, _ = UserProfile.objects.get_or_create(
            user=user, defaults={"role": "client"}
        )
        profile.reset_token = token
        profile.reset_token_created_at = timezone.now()
        profile.save(update_fields=["reset_token", "reset_token_created_at"])
        # Email transactionnel
        _send_reset_email(user.email, token)
    return JsonResponse(
        {"ok": True, "message": "Si cet email existe, un lien a été envoyé."}
    )


def _send_verification_email(to_email: str, token: str) -> None:
    import threading

    from django.core.mail import send_mail
    from django.conf import settings

    def _deliver() -> None:
        # SMTP en arrière-plan : ne bloque pas l'inscription (sinon CancelledError).
        try:
            send_mail(
                subject="Confirmez votre email BABIFIX",
                message=(
                    f"Bonjour,\n\n"
                    f"Merci de vous être inscrit sur BABIFIX.\n"
                    f"Pour confirmer votre email, utilisez ce code dans l'application :\n\n"
                    f"{token}\n\n"
                    f"L'équipe BABIFIX | contact@babifix.ci"
                ),
                from_email=getattr(settings, "DEFAULT_FROM_EMAIL", "contact@babifix.ci"),
                recipient_list=[to_email],
                fail_silently=True,
            )
        except Exception as exc:
            logger.warning("Verify email non envoyé (%s) : %s", to_email, exc)

    threading.Thread(target=_deliver, daemon=True).start()


def _send_reset_email(to_email: str, token: str) -> None:
    import threading

    from django.core.mail import send_mail
    from django.conf import settings

    def _deliver() -> None:
        # SMTP en arrière-plan : ne bloque pas la requête (sinon CancelledError).
        try:
            send_mail(
                subject="Réinitialisation de votre mot de passe BABIFIX",
                message=(
                    f"Bonjour,\n\n"
                    f"Vous avez demandé à réinitialiser votre mot de passe BABIFIX.\n\n"
                    f"Utilisez ce token dans l'application :\n{token}\n\n"
                    f"Ce lien expire dans 30 minutes.\n\n"
                    f"Si vous n'êtes pas à l'origine de cette demande, ignorez cet email.\n\n"
                    f"L'équipe BABIFIX | contact@babifix.ci"
                ),
                from_email=getattr(settings, "DEFAULT_FROM_EMAIL", "contact@babifix.ci"),
                recipient_list=[to_email],
                fail_silently=True,
            )
        except Exception as exc:
            logger.warning("Reset email non envoyé (%s) : %s", to_email, exc)

    threading.Thread(target=_deliver, daemon=True).start()


# ─────────────────────────────────────────────────────────────────────────────
# 6. POST /api/auth/reset-password — confirmer le reset
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["POST"])
def api_auth_reset_password(request):
    try:
        payload = json.loads(request.body or b"{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    token = str(payload.get("token", "") or "").strip()
    new_password = str(payload.get("new_password", "") or "").strip()
    if not token or not new_password:
        return JsonResponse({"error": "token_and_new_password_required"}, status=400)
    if len(new_password) < 6:
        return JsonResponse({"error": "password_too_short"}, status=400)
    profile = (
        UserProfile.objects.filter(reset_token=token).select_related("user").first()
    )
    if not profile:
        return JsonResponse({"error": "invalid_token"}, status=400)
    # Vérifier expiration (30 min)
    if profile.reset_token_created_at:
        age = (timezone.now() - profile.reset_token_created_at).total_seconds()
        if age > 1800:
            return JsonResponse({"error": "token_expired"}, status=400)
    user = profile.user
    user.set_password(new_password)
    user.save()
    profile.reset_token = ""
    profile.reset_token_created_at = None
    profile.save(update_fields=["reset_token", "reset_token_created_at"])
    return JsonResponse(
        {"ok": True, "message": "Mot de passe réinitialisé avec succès."}
    )


# ─────────────────────────────────────────────────────────────────────────────
# 7. POST /api/auth/refresh — renouveler le token
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["POST"])
def api_auth_refresh_token(request):
    refresh_token = ""
    try:
        payload = json.loads(request.body or b"{}")
    except json.JSONDecodeError:
        payload = {}

    refresh_token = str(payload.get("refresh", "") or "").strip()
    token_payload = verify_refresh_token(refresh_token) if refresh_token else None

    if not token_payload:
        auth_header = request.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return JsonResponse({"error": "missing_token"}, status=401)
        old_token = auth_header.split(" ", 1)[1].strip()
        token_payload = verify_token(old_token)
    if not token_payload:
        return JsonResponse({"error": "invalid_or_expired_token"}, status=401)
    uid = token_payload.get("uid")
    role = token_payload.get("role")
    new_token = create_token(uid, role)
    new_refresh = create_refresh_token(uid, role)
    return JsonResponse(
        {"token": new_token, "access": new_token, "refresh": new_refresh, "role": role}
    )


# ─────────────────────────────────────────────────────────────────────────────
# 8. GET /api/auth/verify-email/<token> — confirmer l'email
# ─────────────────────────────────────────────────────────────────────────────
@require_GET
def api_auth_verify_email(request, token):
    profile = (
        UserProfile.objects.filter(email_verify_token=token)
        .select_related("user")
        .first()
    )
    if not profile:
        return JsonResponse({"error": "invalid_token"}, status=400)
    profile.email_verified = True
    profile.email_verify_token = ""
    profile.save(update_fields=["email_verified", "email_verify_token"])
    return JsonResponse({"ok": True, "message": "Email vérifié avec succès."})


# ─────────────────────────────────────────────────────────────────────────────
# 9. DELETE /api/auth/delete-account — supprimer son compte (loi CI n°2013-450)
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["DELETE"])
@require_api_auth(["client", "prestataire"])
def api_auth_delete_account(request):
    uid = request.api_user_id
    try:
        user = User.objects.get(id=uid)
    except User.DoesNotExist:
        return JsonResponse({"error": "user_not_found"}, status=404)

    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)

    confirmation = str(payload.get("confirmation", "")).strip().lower()
    if confirmation != "supprimer":
        return JsonResponse(
            {
                "error": "confirmation_required",
                "message": 'Envoyer {"confirmation": "supprimer"} pour confirmer',
            },
            status=400,
        )

    from decimal import Decimal as _D

    from django.db.models import Q as _Q

    provider = Provider.objects.filter(user_id=uid).first()

    # ── Garde-fous : on n'efface pas un compte avec de l'argent ou des
    #    engagements en cours (sécurité financière + protection des tiers). ──
    _ACTIVE = [
        "En attente", "Confirmee", "En cours", "En attente client",
        "DEMANDE_ENVOYEE", "DEVIS_EN_COURS", "DEVIS_ENVOYE",
        "DEVIS_ACCEPTE", "INTERVENTION_EN_COURS", "Litige",
    ]
    if provider and (provider.solde_fcfa or _D("0")) > 0:
        return JsonResponse(
            {
                "error": "solde_non_nul",
                "message": "Retirez d'abord votre solde wallet avant de supprimer votre compte.",
            },
            status=400,
        )
    if provider and WalletTransaction.objects.filter(
        provider=provider, tx_type="debit", status__in=["pending", "processing"]
    ).exists():
        return JsonResponse(
            {
                "error": "retrait_en_cours",
                "message": "Un retrait est en cours. Attendez sa finalisation avant de supprimer le compte.",
            },
            status=400,
        )
    res_filter = _Q(client_user_id=uid) | _Q(prestataire_user_id=uid)
    if provider:
        res_filter |= _Q(assigned_provider=provider)
    if Reservation.objects.filter(res_filter).filter(
        _Q(statut__in=_ACTIVE) | _Q(dispute_ouverte=True)
    ).exists():
        return JsonResponse(
            {
                "error": "engagements_en_cours",
                "message": "Terminez ou annulez vos prestations et litiges en cours avant de supprimer votre compte.",
            },
            status=400,
        )
    if Reservation.objects.filter(
        client_user_id=uid, refund_owed_fcfa__gt=0, refund_paid_at__isnull=True
    ).exists():
        return JsonResponse(
            {
                "error": "remboursement_en_attente",
                "message": "Un remboursement vous est dû. Il sera versé avant la suppression du compte.",
            },
            status=400,
        )

    # ── Anonymisation (loi ivoirienne n°2013-450 — droit à l'effacement).
    #    Soft-delete : on conserve les écritures comptables liées mais on
    #    retire les données personnelles. ──
    with transaction.atomic():
        stamp = uuid.uuid4().hex[:8]
        user.is_active = False
        user.username = f"deleted_{user.id}_{stamp}"
        user.email = ""
        user.first_name = ""
        user.last_name = ""
        user.set_unusable_password()
        user.save()

        profile = getattr(user, "profile", None)
        if profile:
            profile.active = False
            if hasattr(profile, "is_deleted"):
                profile.is_deleted = True
            if hasattr(profile, "phone_e164"):
                profile.phone_e164 = ""
            profile.save()

        if provider:
            provider.is_deleted = True
            provider.disponible = False
            provider.statut = Provider.Status.SUSPENDED
            provider.save(update_fields=["is_deleted", "disponible", "statut"])

        DeviceToken.objects.filter(user=user).delete()
        Notification.objects.filter(user=user).delete()

    return JsonResponse({"ok": True, "message": "Compte supprimé avec succès."})


# ─────────────────────────────────────────────────────────────────────────────
# 9. PATCH /api/prestataire/profile — modifier profil
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["PATCH", "GET"])
@require_api_auth(["prestataire", "admin"])
def api_prestataire_profile_update(request):
    uid = request.api_user_id
    try:
        provider = Provider.objects.get(user_id=uid)
    except Provider.DoesNotExist:
        return JsonResponse({"error": "provider_not_found"}, status=404)
    if request.method == "GET":
        return JsonResponse(
            {
                "id": provider.pk,
                "nom": provider.nom,
                "specialite": provider.specialite,
                "ville": provider.ville,
                "bio": provider.bio,
                "tarif_horaire": float(provider.tarif_horaire)
                if provider.tarif_horaire
                else None,
                "years_experience": provider.years_experience,
                "disponible": provider.disponible,
                "statut": provider.statut,
                "average_rating": provider.average_rating,
                "rating_count": provider.rating_count,
                "photo_portrait_url": provider.photo_portrait_url,
                "latitude": float(provider.latitude)
                if provider.latitude is not None
                else None,
                "longitude": float(provider.longitude)
                if provider.longitude is not None
                else None,
            }
        )
    # PATCH
    try:
        payload = json.loads(request.body or b"{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    update_fields = []
    allowed = {"nom", "specialite", "ville", "bio", "tarif_horaire", "years_experience"}
    for field in allowed:
        if field in payload and payload[field] is not None:
            val = payload[field]
            if field == "tarif_horaire":
                try:
                    val = float(val)
                    if val < 0:
                        continue
                except (TypeError, ValueError):
                    continue
            elif field == "years_experience":
                try:
                    val = int(val)
                    if val < 0:
                        continue
                except (TypeError, ValueError):
                    continue
            elif isinstance(val, str):
                val = val.strip()[:500]
            setattr(provider, field, val)
            update_fields.append(field)
    # Photo portrait — base64 → fichier sur disque
    portrait = payload.get("photo_portrait_url", "") or payload.get("photo_portrait_b64", "")
    if portrait and isinstance(portrait, str) and portrait.startswith("data:image/"):
        from .views import _decode_and_save_media
        saved = _decode_and_save_media(portrait, "portraits", "portrait")
        if saved:
            provider.photo_portrait_url = saved
            update_fields.append("photo_portrait_url")
    if update_fields:
        provider.save(update_fields=update_fields)
    return JsonResponse(
        {
            "ok": True,
            "updated": update_fields,
            "statut": provider.statut,
        }
    )


# ─────────────────────────────────────────────────────────────────────────────
# 10-12. Portfolio prestataire (galerie réalisations)
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["GET", "POST"])
@require_api_auth(["prestataire", "admin"])
def api_prestataire_portfolio(request):
    uid = request.api_user_id
    try:
        provider = Provider.objects.get(user_id=uid)
    except Provider.DoesNotExist:
        return JsonResponse({"error": "provider_not_found"}, status=404)
    if request.method == "GET":
        photos = provider.portfolio_photos or []
        return JsonResponse({"photos": photos, "count": len(photos)})
    # POST — ajouter une photo
    try:
        payload = json.loads(request.body or b"{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    photo = str(payload.get("photo", "") or "").strip()
    caption = str(payload.get("caption", "") or "").strip()[:200]
    if not photo or not photo.startswith("data:image/"):
        return JsonResponse({"error": "photo_data_url_required"}, status=400)
    if len(photo) > 800_000:
        return JsonResponse({"error": "photo_too_large"}, status=400)
    photos = list(provider.portfolio_photos or [])
    if len(photos) >= 12:
        return JsonResponse({"error": "max_12_photos"}, status=400)
    # Sauvegarder l'image sur disque plutôt qu'en base64 en DB
    from .views import _decode_and_save_media
    photo_url = _decode_and_save_media(photo, f"portfolio/{provider.id}", "realisation")
    if not photo_url:
        photo_url = photo  # fallback base64 si échec
    entry = {"photo": photo_url, "caption": caption, "added_at": timezone.now().isoformat()}
    photos.append(entry)
    provider.portfolio_photos = photos
    provider.save(update_fields=["portfolio_photos"])
    return JsonResponse({"ok": True, "count": len(photos), "photo_url": photo_url})


@csrf_exempt
@require_http_methods(["DELETE"])
@require_api_auth(["prestataire", "admin"])
def api_prestataire_portfolio_delete(request, idx):
    uid = request.api_user_id
    try:
        provider = Provider.objects.get(user_id=uid)
    except Provider.DoesNotExist:
        return JsonResponse({"error": "provider_not_found"}, status=404)
    photos = list(provider.portfolio_photos or [])
    try:
        photos.pop(int(idx))
    except (IndexError, ValueError):
        return JsonResponse({"error": "invalid_index"}, status=400)
    provider.portfolio_photos = photos
    provider.save(update_fields=["portfolio_photos"])
    return JsonResponse({"ok": True, "count": len(photos)})


# ─────────────────────────────────────────────────────────────────────────────
# 13. POST /api/prestataire/reservations/<ref>/rate-client — noter le client
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["GET", "POST"])
@require_api_auth(["prestataire", "admin"])
def api_prestataire_rate_client(request, reference):
    uid = request.api_user_id
    try:
        res = Reservation.objects.get(reference=reference)
    except Reservation.DoesNotExist:
        return JsonResponse({"error": "not_found"}, status=404)
    if request.api_role != "admin" and res.prestataire_user_id != uid:
        prov = Provider.objects.filter(user_id=uid).first()
        if not prov or res.assigned_provider_id != prov.pk:
            return JsonResponse({"error": "forbidden"}, status=403)
    # Le prestataire peut noter le client dès que l'intervention est terminée
    # de son côté (statut Terminée/En attente client OU horodatage de fin posé),
    # sans attendre une confirmation supplémentaire. Robuste aux variations d'état.
    _done = (
        res.statut in ("Terminee", "En attente client")
        or bool(getattr(res, "prestation_terminee_at", None))
        or bool(getattr(res, "client_confirme_prestation_at", None))
    )
    if not _done:
        return JsonResponse({"error": "reservation_not_completed"}, status=400)
    if request.method == "GET":
        existing = ClientRating.objects.filter(reservation=res).first()
        if existing:
            return JsonResponse(
                {
                    "rated": True,
                    "note": existing.note,
                    "commentaire": existing.commentaire,
                }
            )
        return JsonResponse({"rated": False})
    # POST
    if ClientRating.objects.filter(reservation=res).exists():
        return JsonResponse({"error": "already_rated"}, status=400)
    try:
        payload = json.loads(request.body or b"{}")
        note = int(payload.get("note", 0))
    except (json.JSONDecodeError, TypeError, ValueError):
        return JsonResponse({"error": "invalid_json"}, status=400)
    if note < 1 or note > 5:
        return JsonResponse({"error": "note_1_to_5"}, status=400)
    commentaire = str(payload.get("commentaire", "") or "")[:1000]
    ClientRating.objects.create(
        reservation=res,
        prestataire_user_id=uid,
        client_user=res.client_user,
        note=note,
        commentaire=commentaire,
    )
    return JsonResponse({"ok": True})


# ─────────────────────────────────────────────────────────────────────────────
# 14. GET /api/client/notifications — liste notifications persistantes
# ─────────────────────────────────────────────────────────────────────────────
@require_GET
@require_api_auth(["client", "prestataire", "admin"])
def api_user_notifications(request):
    uid = request.api_user_id
    qs = Notification.objects.filter(user_id=uid).order_by("-created_at")[:50]
    data = [
        {
            "id": n.pk,
            "title": n.title,
            "body": n.body,
            "type": n.notif_type,
            "reference": n.reference,
            "lu": n.lu,
            "created_at": n.created_at.isoformat(),
        }
        for n in qs
    ]
    return JsonResponse(
        {"notifications": data, "unread": sum(1 for n in data if not n["lu"])}
    )


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client", "prestataire", "admin"])
def api_user_notifications_mark_read(request):
    uid = request.api_user_id
    try:
        payload = json.loads(request.body or b"{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    ids = payload.get("ids", [])
    if ids:
        Notification.objects.filter(pk__in=ids, user_id=uid).update(lu=True)
    else:
        Notification.objects.filter(user_id=uid, lu=False).update(lu=True)
    return JsonResponse({"ok": True})


# ─────────────────────────────────────────────────────────────────────────────
# 15. POST /api/admin/push-broadcast — push manuelle vers tous les users
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["POST"])
def api_admin_push_broadcast(request):
    from django.contrib.auth.decorators import login_required

    if not (request.user and request.user.is_authenticated and request.user.is_staff):
        return JsonResponse({"error": "admin_required"}, status=403)
    try:
        payload = json.loads(request.body or b"{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    title = str(payload.get("title", "") or "").strip()
    body = str(payload.get("body", "") or "").strip()
    target_role = (
        str(payload.get("role", "") or "").strip().lower()
    )  # '', 'client', 'prestataire'
    if not title or not body:
        return JsonResponse({"error": "title_and_body_required"}, status=400)
    qs = DeviceToken.objects.select_related("user")
    if target_role in ("client", "prestataire"):
        qs = qs.filter(user__profile__role=target_role)
    user_ids = list(qs.values_list("user_id", flat=True).distinct())
    if user_ids:
        _schedule(
            user_ids=user_ids,
            title=title,
            body=body,
            data={"type": "broadcast", "role": target_role},
        )
    # Créer une notification persistante pour chaque user ciblé
    notifs = [
        Notification(
            title=title,
            body=body,
            notif_type="broadcast",
            user_id=uid,
        )
        for uid in user_ids
    ]
    Notification.objects.bulk_create(notifs, ignore_conflicts=True)
    return JsonResponse({"ok": True, "sent_to": len(user_ids)})


# ─────────────────────────────────────────────────────────────────────────────
# 16. GET /api/client/prestataires/<id>/portfolio — galerie publique
# ─────────────────────────────────────────────────────────────────────────────
@require_GET
def api_provider_portfolio_public(request, provider_id):
    try:
        provider = Provider.objects.get(pk=provider_id, statut=Provider.Status.VALID)
    except Provider.DoesNotExist:
        return JsonResponse({"error": "not_found"}, status=404)
    photos = [
        {"photo": p.get("photo", ""), "caption": p.get("caption", "")}
        for p in (provider.portfolio_photos or [])
    ]
    return JsonResponse({"provider_id": provider_id, "photos": photos})


# ─────────────────────────────────────────────────────────────────────────────
# Modèles inline pour ClientRating (note prestataire → client)
# Ces classes sont utilisées ici directement sans migration séparée
# (voir models_v2.py pour la définition complète)
# ─────────────────────────────────────────────────────────────────────────────


def _get_client_rating_model():
    """Lazy import pour éviter les imports circulaires."""
    from .models_v2 import ClientRating

    return ClientRating


# Patch pour la vue rate-client
ClientRating = None


def _init_client_rating():
    global ClientRating
    try:
        from .models_v2 import ClientRating as CR

        ClientRating = CR
    except ImportError:
        pass


# ─────────────────────────────────────────────────────────────────────────────
# 17. GET /api/reservations/<ref>/payment/quote — devis récap paiement
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["GET"])
@require_api_auth(["client", "prestataire", "admin"])
def api_payment_quote(request, reference):
    from .models import Reservation
    from .services.escrow_service import EscrowService

    res = Reservation.objects.filter(reference=reference).first()
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)
    quote = EscrowService.quote(res)
    return JsonResponse({
        "reference": res.reference,
        "reservation_id": res.id,
        "payment_type": res.payment_type,
        "strategy": quote.strategy,
        "devis_id": quote.devis_id,
        "devis_reference": quote.devis_reference,
        "total_devis": float(quote.total_devis),
        "commission_montant": float(quote.commission_montant),
        "commission_rate": quote.commission_rate,
        "net_prestataire": float(quote.net_prestataire),
        "amount_due_online": float(quote.amount_due),
        "cash_remainder_due_to_provider": float(quote.cash_remainder),
        "acompte_valide": res.acompte_valide,
        # Montant RÉELLEMENT versé en escrow à ce stade (acompte seul, ou
        # acompte + solde) → permet d'afficher le VRAI montant détenu, pas le
        # net complet supposé.
        "montant_verse": float(res.montant_verse or 0),
        "montant_total": float(res.montant or 0),
        # Opérateur Mobile Money choisi à la réservation → pré-rempli à l'écran
        # de paiement (plus de double sélection).
        "mobile_money_operator": res.mobile_money_operator or "",
        "funds_released_at": res.funds_released_at.isoformat() if res.funds_released_at else None,
    })


# ─────────────────────────────────────────────────────────────────────────────
# 18. GET/POST /api/client/reservations/<ref>/journal — journal client
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["GET", "POST"])
@require_api_auth(["client"])
def api_client_journal(request, reference):
    from .models import Reservation

    uid = int(request.api_user_id)
    res = Reservation.objects.filter(reference=reference).first()
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)
    if res.client_user_id != uid:
        return JsonResponse({"error": "forbidden"}, status=403)

    if request.method == "GET":
        return JsonResponse({
            "client_photos_avant": res.client_photos_avant or [],
            "client_photos_apres": res.client_photos_apres or [],
            "prestataire_photos_avant": res.photos_avant or [],
            "prestataire_photos_apres": res.photos_apres or [],
            "client_journal_note": res.client_journal_note or "",
            "statut": res.statut,
            "client_journal_updated_at": res.client_journal_updated_at.isoformat() if res.client_journal_updated_at else None,
        })

    # POST
    from django.utils import timezone
    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)

    mode = payload.get("mode", "replace")
    if payload.get("photos_avant") is not None:
        if mode == "replace":
            res.client_photos_avant = payload["photos_avant"]
        else:
            current = list(res.client_photos_avant or [])
            current.extend(payload["photos_avant"])
            res.client_photos_avant = current
    if payload.get("photos_apres") is not None:
        if mode == "replace":
            res.client_photos_apres = payload["photos_apres"]
        else:
            current = list(res.client_photos_apres or [])
            current.extend(payload["photos_apres"])
            res.client_photos_apres = current
    if payload.get("note") is not None:
        res.client_journal_note = str(payload["note"])[:5000]
    res.client_journal_updated_at = timezone.now()
    res.save(update_fields=[
        "client_photos_avant", "client_photos_apres",
        "client_journal_note", "client_journal_updated_at",
    ])
    return JsonResponse({"ok": True})


_init_client_rating()
