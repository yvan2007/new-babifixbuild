"""
BABIFIX  :  Nouvelles fonctionnalités v2
  1.  GET  /api/client/reservations                :  historique réservations client
  2.  GET  /api/client/reservations/<ref>           :  détail réservation + statut temps réel
  3.  POST /api/client/reservations/<ref>/cancel    :  annulation réservation
  4.  POST /api/client/reservations/<ref>/dispute   :  ouvrir un litige
  5.  POST /api/auth/forgot-password                :  demande reset mot de passe
  6.  POST /api/auth/reset-password                 :  confirmer reset avec token
  7.  POST /api/auth/refresh                        :  refresh token JWT
  8.  GET  /api/auth/verify-email/<token>           :  confirmer email
  9.  PATCH /api/prestataire/profile                :  modifier profil prestataire
  10. GET  /api/prestataire/portfolio               :  galerie réalisations prestataire
  11. POST /api/prestataire/portfolio               :  ajouter photo réalisation
  12. DELETE /api/prestataire/portfolio/<idx>       :  supprimer photo réalisation
  13. POST /api/prestataire/reservations/<ref>/rate-client  :  noter le client
  14. GET  /api/client/notifications                :  notifications persistantes client
  15. POST /api/admin/push-broadcast                :  push notif manuelle tous users
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
# Version minimale des apps (force update)  :  public, sans auth.
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
    """Recoit les crashs, erreurs HTTP et latences mobiles et les persiste dans SystemEventLog.

    Public + rate-limite (anti-flood), redaction stricte des secrets et deduplication 60s.
    """
    from .services.observability_service import (
        build_client_ip,
        record_system_event,
        redact_mapping,
        redact_text,
    )
    from .throttle import check_rate_limit

    if check_rate_limit(request, "log_error", max_requests=20, window=60):
        return JsonResponse({"ok": True})  # silencieux : anti-flood
    try:
        p = json.loads(request.body or b"{}")
    except json.JSONDecodeError:
        return JsonResponse({"ok": True})

    msg = redact_text(p.get("message", ""), max_len=1000)
    stack = redact_text(p.get("stack", ""), max_len=4000)
    app = str(p.get("app", "client"))[:20].lower()
    version = str(p.get("version", ""))[:24]
    platform = str(p.get("platform", ""))[:20]
    endpoint = str(p.get("endpoint") or p.get("screen") or "/mobile-app")[:255]
    raw_level = str(p.get("level") or "error").lower()
    level = raw_level if raw_level in {"critical", "error", "slow", "warning"} else "error"
    try:
        status_code = int(p.get("status_code")) if p.get("status_code") is not None else None
    except (TypeError, ValueError):
        status_code = None
    try:
        duration_ms = float(p.get("duration_ms")) if p.get("duration_ms") is not None else None
    except (TypeError, ValueError):
        duration_ms = None

    source = "mobile_pro" if "prest" in app or "pro" in app else "mobile_client"
    extra_payload = redact_mapping(p.get("extra")) if isinstance(p.get("extra"), dict) else ""

    logger.error("MOBILE[%s/%s v%s] %s\n%s", app, platform, version, msg, stack)
    record_system_event(
        source=source,
        level=level,
        message=msg or "Erreur application mobile",
        endpoint=endpoint,
        method=str(p.get("method") or "APP")[:12],
        status_code=status_code,
        duration_ms=duration_ms,
        user=getattr(request, "user", None),
        user_label=redact_text(p.get("user_label") or "", max_len=120),
        client_ip=build_client_ip(request),
        user_agent=request.META.get("HTTP_USER_AGENT", ""),
        exception_type=str(p.get("exception_type") or ("SlowMobileAPI" if level == "slow" else "FlutterError"))[:120],
        source_file=str(p.get("screen") or platform)[:255],
        traceback_text=stack,
        payload_redacted=json.dumps(extra_payload, ensure_ascii=False) if extra_payload else "",
        app_version=f"{platform} v{version}".strip()[:48],
    )
    return JsonResponse({"ok": True})


# ─────────────────────────────────────────────────────────────────────────────
# Helpers internes
# ─────────────────────────────────────────────────────────────────────────────


def _frais_mise_en_relation_config() -> float:
    """Frais fixe de mise en relation (config plateforme)  :  pour l'app client,
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
# 1. GET /api/client/reservations  :  historique
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
# 2. GET /api/client/reservations/<ref>  :  détail
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
# 3. POST /api/client/reservations/<ref>/cancel  :  annuler
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["POST", "PATCH"])
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

        # ── Reglement de la caution de visite (Phase 3) ──────────────────────
        # Visite deja effectuee : le presta garde la caution ; sinon : remboursee
        # au client (commission plateforme neutralisee proprement).
        if (
            res.caution_payee
            and not res.caution_deduite
            and not res.caution_remboursee
            and not res.visite_effectuee
        ):
            res.caution_remboursee = True
            fields.append("caution_remboursee")
            try:
                from adminpanel.models import PlatformRevenue, Payment
                cpay = Payment.objects.filter(
                    reference__startswith=f"CAUTION-{res.reference}"
                ).first()
                if cpay:
                    updated_cnt = PlatformRevenue.objects.filter(
                        payment=cpay,
                        refunded_at__isnull=True,
                    ).update(refunded_at=timezone.now())
                    if not updated_cnt and (cpay.commission or 0) > 0:
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

        # ── Score de fiabilite + detection anti-contournement (Phase 4) ──────
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
                + (f" : {motif}" if motif else ""),
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
# 4. POST /api/client/reservations/<ref>/dispute  :  ouvrir un litige
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
    return JsonResponse({"ok": True, "litige_reference": ref_litige})


# ─────────────────────────────────────────────────────────────────────────────
# 5. POST /api/auth/forgot-password  :  demander un reset
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
    email = str(payload.get("email", "") or "").replace("\r", "").replace("\n", "").strip().lower()[:254]
    if not email:
        return JsonResponse({"error": "email_required"}, status=400)
    # Toujours répondre ok pour ne pas révéler si l'email existe
    user = User.objects.filter(email__iexact=email, is_active=True).first()
    if user:
        # Code OTP numérique 6 chiffres ergonomique sur mobile + compatible token urlsafe
        token = f"{secrets.randbelow(900000) + 100000}"
        profile, _ = UserProfile.objects.get_or_create(
            user=user, defaults={"role": "client"}
        )
        profile.reset_token = token
        profile.reset_token_created_at = timezone.now()
        profile.save(update_fields=["reset_token", "reset_token_created_at"])
        # Ne jamais exposer le code de réinitialisation en clair hors mode DEBUG local
        if getattr(settings, "DEBUG", False):
            logger.debug("[BABIFIX RESET OTP dev] Email=%s", user.email)
        # Email transactionnel
        _send_reset_email(user.email, token)
    return JsonResponse(
        {"ok": True, "message": "Si cet email existe, un lien a été envoyé."}
    )


def _send_verification_email(to_email: str, token: str) -> None:
    from .services.email_service import send_babifix_html_email

    send_babifix_html_email(
        to_email=to_email,
        subject="Votre code de confirmation BABIFIX",
        template_name="emails/otp_confirmation_email.html",
        context={"otp_code": token},
        async_send=True,
    )


def _send_reset_email(to_email: str, token: str) -> None:
    from .services.email_service import send_babifix_html_email

    send_babifix_html_email(
        to_email=to_email,
        subject="Reinitialisation de votre mot de passe BABIFIX",
        template_name="emails/password_reset_otp.html",
        context={"otp_code": token},
        async_send=True,
    )

# ─────────────────────────────────────────────────────────────────────────────
# 6. POST /api/auth/reset-password  :  confirmer le reset
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["POST"])
def api_auth_reset_password(request):
    from .throttle import check_rate_limit, rate_limited_response

    if check_rate_limit(request, "reset_password", max_requests=5, window=300):
        return rate_limited_response()
    try:
        payload = json.loads(request.body or b"{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    token = str(payload.get("token", "") or "").strip()
    email_hint = str(payload.get("email", "") or "").strip().lower()
    new_password = str(payload.get("new_password", "") or "").strip()
    if not token or not new_password:
        return JsonResponse({"error": "token_and_new_password_required"}, status=400)
    if len(new_password) < 6:
        return JsonResponse({"error": "password_too_short"}, status=400)
    qs = UserProfile.objects.filter(reset_token=token, user__is_active=True).select_related("user")
    if email_hint:
        qs = qs.filter(user__email__iexact=email_hint)
    profile = qs.first()
    if not profile:
        return JsonResponse({"error": "invalid_token"}, status=400)
    # Vérifier expiration stricte (15 min)
    if profile.reset_token_created_at:
        age = (timezone.now() - profile.reset_token_created_at).total_seconds()
        if age > 900:
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
# 6b. POST /api/auth/change-password : modifier le mot de passe quand connecte
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["POST"])
def api_auth_change_password(request):
    from .auth import verify_token, create_token, create_refresh_token
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        return JsonResponse({"error": "missing_token", "message": "Authentification requise."}, status=401)
    tok = auth_header.split(" ", 1)[1].strip()
    payload = verify_token(tok)
    if not payload:
        return JsonResponse({"error": "invalid_token", "message": "Session expirée ou invalide."}, status=401)
    
    uid = payload.get("uid") or payload.get("user_id") or payload.get("sub")
    try:
        user_id = int(uid)
        user = User.objects.get(pk=user_id, is_active=True)
    except Exception:
        return JsonResponse({"error": "user_not_found", "message": "Utilisateur introuvable."}, status=404)
    
    try:
        body = json.loads(request.body.decode("utf-8") or "{}")
    except Exception:
        return JsonResponse({"error": "invalid_json"}, status=400)
    
    current_password = str(body.get("current_password") or body.get("old_password") or "").strip()
    new_password = str(body.get("new_password") or "").strip()
    
    if not current_password or not new_password:
        return JsonResponse({"error": "fields_required", "message": "Mot de passe actuel et nouveau mot de passe requis."}, status=400)
    
    if not user.check_password(current_password):
        return JsonResponse({"error": "invalid_current_password", "message": "Le mot de passe actuel est incorrect."}, status=400)
    
    if len(new_password) < 6:
        return JsonResponse({"error": "password_too_short", "message": "Le nouveau mot de passe doit comporter au moins 6 caractères."}, status=400)
    
    user.set_password(new_password)
    user.save()
    
    profile = UserProfile.objects.filter(user=user, active=True).first()
    role = profile.role if profile else "client"
    new_tok = create_token(user.id, role)
    new_ref = create_refresh_token(user.id, role)
    
    return JsonResponse({
        "ok": True,
        "message": "Mot de passe modifié avec succès.",
        "token": new_tok,
        "access": new_tok,
        "refresh": new_ref,
    })


# ─────────────────────────────────────────────────────────────────────────────
# 7. POST /api/auth/refresh  :  renouveler le token
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
    from .auth import _is_user_active_and_role_ok

    uid = token_payload.get("uid")
    role = token_payload.get("role")
    if not _is_user_active_and_role_ok(uid, role):
        return JsonResponse({"error": "account_disabled"}, status=403)
    # Révoquer l'ancien refresh token JWT pour empêcher son rejeu (rotation stricte)
    if refresh_token and token_payload.get("jti"):
        try:
            from .jwt_auth import _blacklist_jti
            _blacklist_jti(token_payload["jti"])
        except Exception:
            pass
    new_token = create_token(uid, role)
    new_refresh = create_refresh_token(uid, role)
    return JsonResponse(
        {"token": new_token, "access": new_token, "refresh": new_refresh, "role": role}
    )


# ─────────────────────────────────────────────────────────────────────────────
# 8. GET /api/auth/verify-email/<token>  :  confirmer l'email
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
# 8b. POST /api/auth/verify-email-otp : valider le code OTP a 6 chiffres
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["POST"])
def api_auth_verify_email_otp(request):
    # Protection anti-brute-force : maximum 5 tentatives par minute
    from .throttle import check_rate_limit, rate_limited_response
    if check_rate_limit(request, "verify_email_otp", max_requests=5, window=60):
        return rate_limited_response()

    try:
        body = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)

    email = (body.get("email") or "").strip().lower()
    otp = (body.get("otp") or body.get("code") or "").strip()

    if not email or not otp:
        return JsonResponse({"error": "email_and_otp_required", "message": "Email et code OTP requis."}, status=400)

    profile = (
        UserProfile.objects.filter(user__email__iexact=email, email_verify_token=otp)
        .select_related("user")
        .first()
    )
    if not profile:
        return JsonResponse({"error": "invalid_otp", "message": "Code de confirmation erroné ou expiré."}, status=400)

    # Invalidation immédiate du code à usage unique (anti-rejeu)
    profile.email_verified = True
    profile.email_verify_token = ""
    profile.save(update_fields=["email_verified", "email_verify_token"])
    logger.info("Email verifie avec succes par OTP pour %s", email)
    return JsonResponse({"ok": True, "message": "Email vérifié avec succès."})


# ─────────────────────────────────────────────────────────────────────────────
# 8c. POST /api/auth/resend-email-otp : renvoyer un code OTP a 6 chiffres
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["POST"])
def api_auth_resend_email_otp(request):
    # Protection anti-inondation : maximum 3 renvois toutes les 2 minutes
    from .throttle import check_rate_limit, rate_limited_response
    if check_rate_limit(request, "resend_email_otp", max_requests=3, window=120):
        return rate_limited_response()

    try:
        body = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)

    email = (body.get("email") or "").strip().lower()
    if not email:
        return JsonResponse({"error": "email_required", "message": "Adresse email requise."}, status=400)

    import secrets
    profile = UserProfile.objects.filter(user__email__iexact=email).select_related("user").first()
    if profile:
        new_otp = f"{secrets.randbelow(900000) + 100000}"
        profile.email_verify_token = new_otp
        profile.save(update_fields=["email_verify_token"])
        _send_verification_email(email, new_otp)

    return JsonResponse({"ok": True, "message": "Si cette adresse existe, un nouveau code a été envoyé."})


# ─────────────────────────────────────────────────────────────────────────────
# 9. DELETE /api/auth/delete-account  :  supprimer son compte (loi CI n°2013-450)
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

    # ── Anonymisation (loi ivoirienne n°2013-450  :  droit à l'effacement).
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
# 9. PATCH /api/prestataire/profile  :  modifier profil
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
                "cni_recto_url": provider.cni_recto_url or "",
                "cni_verso_url": provider.cni_verso_url or "",
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
    allowed = {"nom", "specialite", "ville", "bio", "tarif_horaire", "years_experience", "latitude", "longitude"}
    for field in allowed:
        if field in payload and payload[field] is not None:
            val = payload[field]
            if field in ("tarif_horaire", "latitude", "longitude"):
                try:
                    val = float(val)
                    if field == "tarif_horaire" and val < 0:
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
    if "category_id" in payload and payload["category_id"] is not None:
        try:
            cid = int(payload["category_id"])
            cat = Category.objects.filter(pk=cid, is_deleted=False).first()
            if cat:
                provider.category = cat
                if not payload.get("specialite"):
                    provider.specialite = cat.nom
                    update_fields.append("specialite")
                update_fields.append("category")
        except (TypeError, ValueError):
            pass
    # Photo portrait  :  base64 → fichier sur disque
    portrait = payload.get("photo_portrait_url", "") or payload.get("photo_portrait_b64", "")
    if portrait and isinstance(portrait, str) and portrait.startswith("data:image/"):
        from .views import _decode_and_save_media
        saved = _decode_and_save_media(portrait, "portraits", "portrait")
        if saved:
            provider.photo_portrait_url = saved
            update_fields.append("photo_portrait_url")
    if update_fields:
        provider.save(update_fields=update_fields)
        try:
            from .perf_signals import invalidate_public_catalog_cache

            invalidate_public_catalog_cache()
        except Exception:
            pass
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
    # POST  :  ajouter une photo
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
# 13. POST /api/prestataire/reservations/<ref>/rate-client  :  noter le client
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
# 14. GET /api/client/notifications  :  liste notifications persistantes
# ─────────────────────────────────────────────────────────────────────────────
@require_GET
@require_api_auth(["client", "prestataire", "admin"])
def api_user_notifications(request):
    uid = request.api_user_id
    unread_only = str(request.GET.get("unread_only", "") or "").strip() in ("1", "true", "True")
    base_qs = Notification.objects.filter(user_id=uid)
    unread_total = base_qs.filter(lu=False).count()
    qs = (base_qs.filter(lu=False) if unread_only else base_qs).order_by("-created_at")[:50]
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
    return JsonResponse({"notifications": data, "unread": unread_total})


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
    unread_total = Notification.objects.filter(user_id=uid, lu=False).count()
    return JsonResponse({"ok": True, "unread": unread_total})


def _admin_notif_target_url(n) -> str:
    ref = (n.reference or "").upper()
    ntype = (n.notif_type or "").lower()
    if ref.startswith("METIER-"):
        return "/?section=ecosysteme"
    if ref.startswith("PROV-"):
        return "/?section=prestataires"
    if ref.startswith("LIT-"):
        return "/?section=litiges"
    if ref.startswith("RES-"):
        return "/?section=reservations"
    if ref.startswith("PAY-"):
        return "/?section=paiements"
    mapping = {
        "dispute": "/?section=litiges",
        "validation": "/?section=prestataires",
        "reservation": "/?section=reservations",
        "payment": "/?section=paiements",
    }
    return mapping.get(ntype, "/?section=notifications")


def _extract_notif_focus_person(n) -> str:
    title = (n.title or "").strip()
    if ":" in title:
        tail = title.split(":", 1)[1].strip()
        if tail and not tail.upper().startswith(("RES-", "LIT-", "PAY-", "PROV-", "METIER-")):
            return tail
    return ""


def _admin_notif_filter_q(user):
    from django.db.models import Q

    return Q(user__isnull=True) | Q(user=user)


@require_GET
def api_admin_notifications_feed(request):
    if not (request.user and request.user.is_authenticated and request.user.is_staff):
        return JsonResponse({"error": "admin_required"}, status=403)
    base_qs = Notification.objects.filter(_admin_notif_filter_q(request.user), lu=False)
    unread_count = base_qs.count()
    rows = base_qs.order_by("-created_at")[:20]
    items = [
        {
            "id": n.pk,
            "title": n.title,
            "body": n.body,
            "notif_type": n.notif_type,
            "reference": n.reference,
            "lu": n.lu,
            "created_at": n.created_at.isoformat(),
            "target_url": _admin_notif_target_url(n),
            "focus_ref": (n.reference or "").strip(),
            "focus_person": _extract_notif_focus_person(n),
        }
        for n in rows
    ]
    return JsonResponse({"unread_count": unread_count, "notifications": items})


@require_http_methods(["POST"])
def api_admin_notifications_mark_read(request):
    if not (request.user and request.user.is_authenticated and request.user.is_staff):
        return JsonResponse({"error": "admin_required"}, status=403)
    nid = None
    ids = []
    try:
        if request.body:
            payload = json.loads(request.body)
            nid = payload.get("id")
            ids = payload.get("ids") or []
    except json.JSONDecodeError:
        nid = request.POST.get("id")
    if not nid and not ids:
        nid = request.POST.get("id")
    target_ids = [int(x) for x in ([nid] if nid else ids) if str(x).isdigit()]
    if target_ids:
        Notification.objects.filter(_admin_notif_filter_q(request.user), pk__in=target_ids).update(lu=True)
    unread_count = Notification.objects.filter(_admin_notif_filter_q(request.user), lu=False).count()
    return JsonResponse({"ok": True, "unread_count": unread_count})


@require_http_methods(["POST"])
def api_admin_notifications_mark_all_read(request):
    if not (request.user and request.user.is_authenticated and request.user.is_staff):
        return JsonResponse({"error": "admin_required"}, status=403)
    updated = Notification.objects.filter(_admin_notif_filter_q(request.user), lu=False).update(lu=True)
    return JsonResponse({"ok": True, "updated": updated, "unread_count": 0})


# ─────────────────────────────────────────────────────────────────────────────
# 15. POST /api/admin/push-broadcast  :  push manuelle vers tous les users
# ─────────────────────────────────────────────────────────────────────────────
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
    notif_type = str(payload.get("notif_type", "") or "broadcast").strip().lower()
    reference = str(payload.get("reference", "") or "").strip()
    if not title or not body:
        return JsonResponse({"error": "title_and_body_required"}, status=400)

    user_qs = User.objects.filter(is_active=True)
    if target_role in ("client", "prestataire"):
        user_qs = user_qs.filter(profile__role=target_role)
    target_user_ids = list(user_qs.values_list("id", flat=True))

    device_user_ids = list(
        DeviceToken.objects.filter(user_id__in=target_user_ids).values_list("user_id", flat=True).distinct()
    )
    if device_user_ids:
        _schedule(
            user_ids=device_user_ids,
            title=title,
            body=body,
            data={"type": notif_type, "role": target_role, "reference": reference},
        )
    # Creer une notification persistante pour chaque user cible
    notifs = [
        Notification(
            title=title,
            body=body,
            notif_type=notif_type,
            reference=reference,
            user_id=uid,
        )
        for uid in target_user_ids
    ]
    Notification.objects.bulk_create(notifs, ignore_conflicts=True)
    return JsonResponse({"ok": True, "sent_to_users": len(target_user_ids), "fcm_devices": len(device_user_ids)})


# ─────────────────────────────────────────────────────────────────────────────
# 16. GET /api/client/prestataires/<id>/portfolio  :  galerie publique
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
# 17. GET /api/reservations/<ref>/payment/quote  :  devis récap paiement
# ─────────────────────────────────────────────────────────────────────────────
@csrf_exempt
@require_http_methods(["GET"])
@require_api_auth(["client", "prestataire", "admin"])
def api_payment_quote(request, reference):
    from .models import Reservation
    from .services.escrow_service import EscrowService

    res = Reservation.objects.select_related("assigned_provider").filter(reference=reference).first()
    if not res:
        return JsonResponse({"error": "not_found"}, status=404)
    uid = int(request.api_user_id)
    role = getattr(request, "api_role", "")
    is_client = res.client_user_id == uid
    is_presta = (res.prestataire_user_id == uid) or (
        res.assigned_provider is not None and res.assigned_provider.user_id == uid
    )
    if role != "admin" and not is_client and not is_presta:
        return JsonResponse({"error": "forbidden"}, status=403)
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
# 18. GET/POST /api/client/reservations/<ref>/journal  :  journal client
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

    def _sanitize_journal_photos(items):
        if not isinstance(items, list):
            return []
        safe = []
        for item in items[:20]:
            s = str(item or "").strip()
            if s.startswith(("/media/", "https://", "http://", "data:image/")):
                safe.append(s[:1500000])
        return safe

    mode = payload.get("mode", "replace")
    if payload.get("photos_avant") is not None:
        cleaned = _sanitize_journal_photos(payload["photos_avant"])
        if mode == "replace":
            res.client_photos_avant = cleaned
        else:
            current = list(res.client_photos_avant or [])
            current.extend(cleaned)
            res.client_photos_avant = current[:40]
    if payload.get("photos_apres") is not None:
        cleaned = _sanitize_journal_photos(payload["photos_apres"])
        if mode == "replace":
            res.client_photos_apres = cleaned
        else:
            current = list(res.client_photos_apres or [])
            current.extend(cleaned)
            res.client_photos_apres = current[:40]
    if payload.get("note") is not None:
        res.client_journal_note = str(payload["note"])[:5000]
    res.client_journal_updated_at = timezone.now()
    res.save(update_fields=[
        "client_photos_avant", "client_photos_apres",
        "client_journal_note", "client_journal_updated_at",
    ])
    return JsonResponse({"ok": True})


_init_client_rating()


# ─────────────────────────────────────────────────────────────────────────────
# Catalogue de devis hybride (Fournitures + Prestations par metier)
# ─────────────────────────────────────────────────────────────────────────────

def api_category_catalogue(request, category_id):
    """Retourne la liste d'items types et prix indicatifs pour un metier."""
    from .services.catalogue_service import CatalogueService
    from .models import Category

    cat_id = None
    try:
        cat_id = int(category_id)
    except (ValueError, TypeError):
        cat_id = None

    items = CatalogueService.get_catalogue_items(cat_id)
    units = CatalogueService.get_recommended_units(cat_id)

    category_name = "Tous metiers"
    icone_slug = "generique"
    if cat_id:
        c = Category.objects.filter(id=cat_id).first()
        if c:
            category_name = c.nom
            icone_slug = c.icone_slug or "generique"

    return JsonResponse({
        "success": True,
        "category_id": cat_id,
        "category_name": category_name,
        "icone_slug": icone_slug,
        "recommended_units": units,
        "items": items,
    })


def api_reservation_bon_de_commande_pdf(request, reference):
    """Telechargement du Bon de Commande contractuel officiel au format PDF (auth + ownership requis)."""
    from django.http import HttpResponse
    from .auth import _is_user_active_and_role_ok, verify_token
    from .models import Reservation
    from .services.order_form_service import OrderFormService

    # Accepter soit session Django staff authentifiée, soit JWT Bearer participant/admin
    is_admin = False
    uid = None
    if getattr(request, "user", None) and request.user.is_authenticated:
        if request.user.is_active and (request.user.is_staff or request.user.is_superuser):
            is_admin = True
        else:
            uid = request.user.id
    if not is_admin and uid is None:
        auth_header = request.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return JsonResponse({"error": "missing_token"}, status=401)
        payload = verify_token(auth_header.split(" ", 1)[1].strip())
        if not payload:
            return JsonResponse({"error": "invalid_token"}, status=401)
        role = payload.get("role")
        raw_uid = payload.get("uid") or payload.get("user_id") or payload.get("sub")
        try:
            uid = int(raw_uid)
        except (TypeError, ValueError):
            return JsonResponse({"error": "invalid_token"}, status=401)
        if not _is_user_active_and_role_ok(uid, role):
            return JsonResponse({"error": "account_disabled"}, status=403)
        if role == "admin":
            is_admin = True

    res = Reservation.objects.filter(reference=reference).select_related("assigned_provider", "client_user").first()
    if not res:
        return JsonResponse({"error": "not_found", "message": "Reservation introuvable."}, status=404)

    is_owner = (res.client_user_id == uid) or (res.prestataire_user_id == uid) or (
        res.assigned_provider is not None and res.assigned_provider.user_id == uid
    )
    if not is_admin and not is_owner:
        return JsonResponse({"error": "forbidden"}, status=403)

    pdf_bytes = OrderFormService.generate_pdf(res)
    if not pdf_bytes:
        return JsonResponse({"error": "pdf_generation_failed", "message": "Echec generation bon de commande."}, status=500)

    safe_ref = "".join(ch for ch in str(reference) if ch.isalnum() or ch in ("-", "_")) or "document"
    filename = f"Bon_Commande_Babifix_{safe_ref}.pdf"
    response = HttpResponse(pdf_bytes, content_type="application/pdf")
    response["Content-Disposition"] = f'attachment; filename="{filename}"'
    return response




@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["prestataire", "admin"])
def api_prestataire_upload_cni(request, side: str):
    """Upload sécurisé CNI recto ou verso en multipart depuis EditProfileScreen."""
    import io
    import os
    import uuid
    from PIL import Image
    from django.conf import settings
    from django.contrib.auth.models import User
    from .models import Provider
    from .secure_uploads import SafeUploadError, validate_image_upload

    uid = int(request.api_user_id)
    user = User.objects.filter(pk=uid, is_active=True).first()
    if not user:
        return JsonResponse({"error": "Authentification requise."}, status=401)

    uploaded = request.FILES.get("file")
    try:
        uploaded = validate_image_upload(uploaded, max_mb=8)
    except SafeUploadError as exc:
        return JsonResponse({"error": str(exc)}, status=400)

    # Ré-encodage Pillow : supprime les métadonnées EXIF/GPS et neutralise tout payload caché
    try:
        uploaded.seek(0)
        img = Image.open(uploaded)
        img.verify()
        uploaded.seek(0)
        img = Image.open(uploaded).convert("RGB")
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=88, optimize=True)
        clean_bytes = buf.getvalue()
    except Exception:
        return JsonResponse({"error": "invalid_image_content"}, status=400)

    subfolder = "cni"
    dest_dir = os.path.join(settings.MEDIA_ROOT, subfolder)
    os.makedirs(dest_dir, exist_ok=True)
    clean_side = "recto" if "recto" in side.lower() else "verso"
    # Nom non prédictible (UUID 128 bits) pour empêcher toute énumération de pièces CNI
    fname = f"cni_{clean_side}_{uuid.uuid4().hex}.jpg"
    full_path = os.path.join(dest_dir, fname)
    with open(full_path, "wb") as out_f:
        out_f.write(clean_bytes)
    rel_url = f"{settings.MEDIA_URL}{subfolder}/{fname}"
    prov = Provider.objects.filter(user=user).first()
    if prov:
        if clean_side == "recto":
            prov.cni_recto_url = rel_url
            prov.kyc_cni_recto_url = rel_url
            prov.save(update_fields=["cni_recto_url", "kyc_cni_recto_url"])
        else:
            prov.cni_verso_url = rel_url
            prov.kyc_cni_verso_url = rel_url
            prov.save(update_fields=["cni_verso_url", "kyc_cni_verso_url"])
    return JsonResponse({"ok": True, "url": rel_url, "side": clean_side})


@require_GET
@require_api_auth(["client", "prestataire", "admin"])
def api_client_sos_preview(request):
    """Previsualisation dynamique BABIFIX SOS 24/7 (eligibilite, horaire jour/nuit, tarif)."""
    from .services.sos_service import check_sos_eligibility

    cat_raw = request.GET.get("category_id") or request.GET.get("category")
    category_id = int(cat_raw) if (cat_raw and str(cat_raw).isdigit()) else None
    title = (request.GET.get("title") or request.GET.get("service") or "").strip()[:200]
    info = check_sos_eligibility(category_id=category_id, title=title)
    return JsonResponse({"ok": True, **info})


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["prestataire"])
def api_prestataire_sos_claim(request, reference: str):
    """Prise en charge atomique (1er artisan du secteur = gagnant) d'une mission SOS."""
    from .models import Provider
    from .services.sos_service import claim_sos_mission

    prov = Provider.objects.filter(user_id=request.api_user_id).first()
    if not prov:
        return JsonResponse({"error": "no_provider", "detail": "Profil prestataire introuvable."}, status=404)
    if prov.statut == Provider.Status.PENDING and (prov.kyc_status or "not_submitted") in ("", "not_submitted"):
        return JsonResponse(
            {
                "error": "kyc_required_to_operate",
                "detail": "Completez votre verification KYC (CNI) avant de prendre en charge une urgence SOS.",
            },
            status=403,
        )
    _ok, body, code = claim_sos_mission(prov, reference)
    return JsonResponse(body, status=code)

