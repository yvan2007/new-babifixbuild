"""
GeniusPay — Passerelle de paiement Mobile Money (Côte d'Ivoire)
https://pay.genius.ci/docs/api

Opérateurs supportés (CI) : Orange Money, MTN MoMo, Wave, PawaPay
Flux : initiate → payment_url/checkout_url → webhook (HMAC-SHA256)
"""

import hashlib
import hmac
import json
import logging
import os
import uuid

from django.conf import settings
from django.http import JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_GET

from .auth import require_api_auth
from .throttle import check_rate_limit, rate_limited_response
from .models import Payment, Reservation

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Config (env vars — à renseigner dans .env ou settings.py)
# ---------------------------------------------------------------------------
GENIUSPAY_PUBLIC_KEY  = os.getenv("GENIUSPAY_PUBLIC_KEY",  getattr(settings, "GENIUSPAY_PUBLIC_KEY", ""))
GENIUSPAY_SECRET_KEY  = os.getenv("GENIUSPAY_SECRET_KEY",  getattr(settings, "GENIUSPAY_SECRET_KEY", ""))
GENIUSPAY_BASE_URL    = os.getenv("GENIUSPAY_API_URL",     getattr(settings, "GENIUSPAY_API_URL", "https://pay.genius.ci/api/v1/merchant"))
GENIUSPAY_WEBHOOK_URL = os.getenv("GENIUSPAY_WEBHOOK_URL", getattr(settings, "GENIUSPAY_WEBHOOK_URL", ""))
GENIUSPAY_SUCCESS_URL = os.getenv("GENIUSPAY_SUCCESS_URL", getattr(settings, "GENIUSPAY_SUCCESS_URL", ""))
GENIUSPAY_ERROR_URL   = os.getenv("GENIUSPAY_ERROR_URL",   getattr(settings, "GENIUSPAY_ERROR_URL", ""))
# Wallet marchand source des versements (payouts). Optionnel : si vide, GeniusPay
# utilise le wallet principal du compte.
GENIUSPAY_WALLET_ID   = os.getenv("GENIUSPAY_WALLET_ID",   getattr(settings, "GENIUSPAY_WALLET_ID", ""))

# Mapping opérateurs BABIFIX → codes GeniusPay
_OPERATOR_MAP = {
    "ORANGE_MONEY": "orange_money",
    "MTN_MOMO":     "mtn_money",
    "WAVE":         "wave",
    "PAWAPAY":      "pawapay",
    "MOOV":         "pawapay",   # PawaPay gère Moov via auto-routing
}

# Mapping opérateurs (côté wallet prestataire, en minuscules) → providers PAYOUT.
# La doc payout attend : wave | orange_money | mtn | moov
_PAYOUT_PROVIDER_MAP = {
    "orange": "orange_money",
    "orange_money": "orange_money",
    "mtn": "mtn",
    "mtn_money": "mtn",
    "mtn_momo": "mtn",
    "wave": "wave",
    "moov": "moov",
}


# ---------------------------------------------------------------------------
# HTTP helper — stdlib urllib (aucune dépendance externe)
# ---------------------------------------------------------------------------
def _genius_request(method: str, path: str, payload: dict | None = None) -> dict:
    """Appel REST vers l'API GeniusPay avec authentification par en-têtes."""
    import urllib.request
    import urllib.error

    url = GENIUSPAY_BASE_URL + path
    data = json.dumps(payload).encode("utf-8") if payload else None
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type":  "application/json",
            "X-API-Key":     GENIUSPAY_PUBLIC_KEY,
            "X-API-Secret":  GENIUSPAY_SECRET_KEY,
        },
        method=method.upper(),
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        logger.error("GeniusPay HTTP %s %s — %s", method, path, body)
        try:
            return json.loads(body)
        except Exception:
            return {"success": False, "error": body, "status_code": e.code}
    except Exception as exc:
        logger.error("GeniusPay network error: %s", exc)
        return {"success": False, "error": str(exc)}


# ---------------------------------------------------------------------------
# PAYOUT (versement sortant vers Mobile Money) — POST /payouts (auth Bearer)
# ---------------------------------------------------------------------------
def _genius_payout_request(payload: dict) -> dict:
    """Appel POST /payouts. L'API payout utilise l'auth Bearer ; on envoie
    aussi les en-têtes X-API-* pour compatibilité."""
    import urllib.request
    import urllib.error

    url = GENIUSPAY_BASE_URL + "/payouts"
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type":  "application/json",
            "Authorization": f"Bearer {GENIUSPAY_SECRET_KEY}",
            "X-API-Key":     GENIUSPAY_PUBLIC_KEY,
            "X-API-Secret":  GENIUSPAY_SECRET_KEY,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=25) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        logger.error("GeniusPay payout HTTP error: %s", body)
        try:
            return json.loads(body)
        except Exception:
            return {"success": False, "error": body, "status_code": e.code}
    except Exception as exc:
        logger.error("GeniusPay payout network error: %s", exc)
        return {"success": False, "error": str(exc)}


def geniuspay_send_payout(
    *,
    amount,
    phone: str,
    operator: str,
    recipient_name: str,
    reference: str,
    description: str = "",
) -> dict:
    """Déclenche un versement Mobile Money vers un prestataire.

    Retour normalisé :
      {ok: bool, status: "pending|processing|completed|failed",
       external_reference: str, fees, net, error}
    - Sans clés API → simulation (succès) pour le développement.
    """
    provider = _PAYOUT_PROVIDER_MAP.get((operator or "").strip().lower())
    if not provider:
        return {"ok": False, "error": f"operateur_invalide:{operator}"}
    if not phone:
        return {"ok": False, "error": "telephone_requis"}
    try:
        amount_int = int(float(amount))
    except (TypeError, ValueError):
        return {"ok": False, "error": "montant_invalide"}
    if amount_int <= 0:
        return {"ok": False, "error": "montant_invalide"}

    # Mode simulation (dev / clés absentes) : versement simulé réussi.
    if not GENIUSPAY_PUBLIC_KEY or not GENIUSPAY_SECRET_KEY:
        logger.warning("GeniusPay payout : clés absentes — simulation pour %s", reference)
        return {
            "ok": True,
            "status": "completed",
            "external_reference": "PYT-SIMUL-" + uuid.uuid4().hex[:8].upper(),
            "fees": 0,
            "net": amount_int,
            "simulated": True,
        }

    payload: dict = {
        "recipient": {"name": recipient_name or "Prestataire BABIFIX", "phone": phone},
        "destination": {"type": "mobile_money", "provider": provider, "account": phone},
        "amount": amount_int,
        "currency": "XOF",
        "description": description or f"Retrait BABIFIX {reference}",
        "idempotency_key": reference,
        "metadata": {"reference": reference, "source": "babifix_wallet_withdrawal"},
    }
    if GENIUSPAY_WALLET_ID:
        payload["wallet_id"] = GENIUSPAY_WALLET_ID

    resp = _genius_payout_request(payload)
    payout = resp.get("payout") or {}
    if resp.get("success") and payout:
        return {
            "ok": True,
            "status": payout.get("status", "pending"),
            "external_reference": payout.get("reference", "") or reference,
            "fees": payout.get("fees", 0),
            "net": payout.get("net_amount", amount_int),
        }
    return {
        "ok": False,
        "error": resp.get("error") or resp.get("message") or "payout_failed",
        "raw": resp,
    }


# ---------------------------------------------------------------------------
# Vérification signature webhook
# Formula : HMAC-SHA256(timestamp + "." + json_body_string, secret_key)
# ---------------------------------------------------------------------------
def _verify_webhook_signature(raw_body: bytes, timestamp: str, received_sig: str) -> bool:
    if not GENIUSPAY_SECRET_KEY:
        # Fail-OPEN seulement en développement (DEBUG). En production, on REFUSE
        # les webhooks non signés pour empêcher tout faux « paiement réussi ».
        if getattr(settings, "DEBUG", False):
            logger.warning("GENIUSPAY_SECRET_KEY absente — signature ignorée (DEBUG).")
            return True
        logger.error("GENIUSPAY_SECRET_KEY absente en production — webhook REFUSÉ.")
        return False
    message = (timestamp + "." + raw_body.decode("utf-8")).encode("utf-8")
    expected = hmac.new(
        GENIUSPAY_SECRET_KEY.encode("utf-8"),
        message,
        hashlib.sha256,
    ).hexdigest()
    return hmac.compare_digest(expected, received_sig or "")


# ---------------------------------------------------------------------------
# POST /api/paiements/geniuspay/initiate/
# ---------------------------------------------------------------------------
@csrf_exempt
@require_api_auth(["client", "prestataire", "admin"])
def geniuspay_initiate(request):
    """
    Initie un paiement GeniusPay pour une réservation.

    Body JSON :
      reservation    (int)    — ID de la réservation
      montant        (int)    — Montant en XOF (min 200)
      payment_method (str)    — ORANGE_MONEY | MTN_MOMO | WAVE | PAWAPAY | MOOV
                                Omettre → page de paiement hébergée (checkout_url)
      phone          (str)    — Téléphone du client (format international +225…)
      customer_name  (str)    — Nom affiché sur la passerelle
      customer_email (str)    — Email du client (optionnel)

    Réponse :
      transaction_id  — Référence GeniusPay (MTX-…)
      payment_url     — URL de paiement direct (si opérateur spécifié)
      checkout_url    — URL page hébergée (si pas d'opérateur)
      payment_id      — ID local du paiement
      status          — "pending"
    """
    if check_rate_limit(request, "geniuspay", max_requests=10, window=60):
        return rate_limited_response()

    if request.method != "POST":
        return JsonResponse({"error": "method_not_allowed"}, status=405)
    try:
        payload = json.loads(request.body)
    except (json.JSONDecodeError, ValueError):
        return JsonResponse({"error": "invalid_json"}, status=400)

    reservation_id  = payload.get("reservation")
    montant         = payload.get("montant")
    operator_raw    = str(payload.get("payment_method", "")).upper().strip()
    phone           = str(payload.get("phone", "")).strip()
    customer_name   = str(payload.get("customer_name", "Client BABIFIX")).strip()
    customer_email  = str(payload.get("customer_email", "")).strip()

    if not reservation_id or not montant:
        return JsonResponse({"error": "missing_fields", "detail": "reservation et montant sont requis"}, status=400)

    try:
        montant_int = int(float(montant))
    except (TypeError, ValueError):
        return JsonResponse({"error": "invalid_amount"}, status=400)

    if montant_int < 200:
        return JsonResponse({"error": "amount_too_low", "detail": "Montant minimum : 200 XOF"}, status=400)

    try:
        reservation = Reservation.objects.get(pk=reservation_id)
    except Reservation.DoesNotExist:
        return JsonResponse({"error": "reservation_not_found"}, status=404)

    # Idempotence : paiement PENDING déjà existant ?
    existing = Payment.objects.filter(
        reservation=reservation,
        etat=Payment.State.PENDING,
    ).first()
    if existing:
        return JsonResponse({
            "transaction_id": existing.reference_externe,
            "payment_id":     existing.pk,
            "status":         "pending",
            "message":        "Paiement déjà en cours.",
        })

    # Référence locale unique
    payment_ref = "GPAY-" + uuid.uuid4().hex[:10].upper()

    # Créer le paiement local en PENDING
    payment = Payment.objects.create(
        reference=payment_ref,
        client=str(reservation.client) if reservation.client else "",
        prestataire=str(reservation.prestataire) if reservation.prestataire else "",
        montant=str(montant_int),
        commission="0",
        etat=Payment.State.PENDING,
        reservation=reservation,
        type_paiement=Payment.TypePaiement.MOBILE_MONEY,
        valide_par_admin=False,
        reference_externe="",   # sera renseigné après appel API
    )

    # Appel GeniusPay si clés configurées
    if not GENIUSPAY_PUBLIC_KEY or not GENIUSPAY_SECRET_KEY:
        logger.warning("GeniusPay : clés API non configurées — mode simulation")
        simulated_ref = "MTX-SIMUL-" + uuid.uuid4().hex[:8].upper()
        payment.reference_externe = simulated_ref
        payment.etat = Payment.State.COMPLETE
        payment.valide_par_admin = True
        from decimal import Decimal
        from adminpanel.models import SystemSetting
        setting = SystemSetting.objects.first()
        commission_pct = setting.commission if setting else 18
        commission_rate = Decimal(str(commission_pct)) / Decimal("100")
        gross = Decimal(str(payment.montant or 0))
        commission = (gross * commission_rate).quantize(Decimal("1"))
        payment.commission = str(commission)
        payment.save(update_fields=["reference_externe", "etat", "valide_par_admin", "commission"])
        # Phase F : même en simulation on passe par l'escrow.
        try:
            from adminpanel.services.escrow_service import EscrowService
            EscrowService.mark_escrow_received(payment)
        except Exception as exc:
            logger.warning("simu escrow failed: %s", exc)
        return JsonResponse({
            "transaction_id": simulated_ref,
            "payment_id":     payment.pk,
            "payment_url":    "",
            "checkout_url":   "",
            "status":         "completed",
            "message":        "Paiement simulé avec succès (développement).",
        })

    # Construire le payload GeniusPay
    genius_payload: dict = {
        "amount":   montant_int,
        "currency": "XOF",
        "customer": {
            "name":    customer_name,
            "email":   customer_email or f"client_{payment.pk}@babifix.ci",
            "phone":   phone or "",
            "country": "CI",
        },
        "metadata": {
            "reservation_id":  str(reservation.pk),
            "reservation_ref": str(reservation.reference),
            "payment_ref":     payment_ref,
        },
        "success_url": GENIUSPAY_SUCCESS_URL or "",
        "error_url":   GENIUSPAY_ERROR_URL   or "",
    }

    # Opérateur spécifié → paiement direct
    if operator_raw and operator_raw in _OPERATOR_MAP:
        genius_payload["payment_method"] = _OPERATOR_MAP[operator_raw]

    genius_resp = _genius_request("POST", "/payments", genius_payload)

    if not genius_resp.get("success"):
        payment.delete()
        error_msg = (
            genius_resp.get("message")
            or genius_resp.get("error")
            or "Erreur GeniusPay"
        )
        logger.error("GeniusPay initiate error: %s", genius_resp)
        return JsonResponse(
            {"error": "geniuspay_error", "message": error_msg},
            status=502,
        )

    data = genius_resp.get("data", {})
    genius_reference = data.get("reference", "")

    payment.reference_externe = genius_reference
    payment.save(update_fields=["reference_externe"])

    return JsonResponse({
        "transaction_id": genius_reference,
        "payment_id":     payment.pk,
        "payment_url":    data.get("payment_url", ""),
        "checkout_url":   data.get("checkout_url", ""),
        "status":         data.get("status", "pending"),
        "message":        "Paiement initié. Suivez les instructions sur votre téléphone.",
    })


# ---------------------------------------------------------------------------
# GET /api/paiements/geniuspay/status/<reference>/
# ---------------------------------------------------------------------------
@require_api_auth(["client", "prestataire", "admin"])
@require_GET
def geniuspay_status(request, reference: str):
    """Retourne le statut local et distant d'un paiement GeniusPay."""
    try:
        payment = Payment.objects.get(reference_externe=reference)
    except Payment.DoesNotExist:
        return JsonResponse({"error": "not_found"}, status=404)

    local_status_map = {
        Payment.State.PENDING:  "pending",
        Payment.State.COMPLETE: "completed",
        Payment.State.DISPUTE:  "failed",
    }

    # Si déjà complété localement, retourner immédiatement
    if payment.etat == Payment.State.COMPLETE:
        return JsonResponse({
            "reference":     reference,
            "payment_id":    payment.pk,
            "status":        "completed",
            "remote_status": "completed",
            "amount":        str(payment.montant),
            "payment_ref":   payment.reference,
        })

    # Interroger GeniusPay uniquement si paiement encore PENDING
    remote_status = None
    if payment.etat == Payment.State.PENDING and GENIUSPAY_PUBLIC_KEY:
        remote_resp = _genius_request("GET", f"/payments/{reference}")
        if remote_resp.get("success"):
            remote_status = remote_resp.get("data", {}).get("status")
            # Synchroniser si le statut a changé côté GeniusPay
            if remote_status == "completed" and payment.etat != Payment.State.COMPLETE:
                payment.etat = Payment.State.COMPLETE
                payment.save(update_fields=["etat"])
            elif remote_status in ("failed", "cancelled", "expired"):
                payment.etat = Payment.State.DISPUTE
                payment.save(update_fields=["etat"])

    return JsonResponse({
        "reference":     reference,
        "payment_id":    payment.pk,
        "status":        local_status_map.get(payment.etat, "pending"),
        "remote_status": remote_status,
        "amount":        str(payment.montant),
        "payment_ref":   payment.reference,
    })


# ---------------------------------------------------------------------------
# POST /api/paiements/geniuspay/webhook/
# ---------------------------------------------------------------------------
@csrf_exempt
def geniuspay_webhook(request):
    """
    Réception des événements GeniusPay (payment.success, payment.failed, etc.).
    Vérification HMAC-SHA256 : HMAC(timestamp + "." + body, secret_key)
    """
    if request.method != "POST":
        return JsonResponse({"error": "method_not_allowed"}, status=405)

    raw_body  = request.body
    timestamp = request.headers.get("X-Webhook-Timestamp", "")
    received_sig = request.headers.get("X-Webhook-Signature", "")
    event_type   = request.headers.get("X-Webhook-Event", "")
    environment  = request.headers.get("X-Webhook-Environment", "")

    logger.info("GeniusPay webhook — event=%s env=%s", event_type, environment)

    # webhook.test = vérification de connectivité envoyée par le dashboard GeniusPay.
    # Pas de signature valide en sandbox — répondre 200 immédiatement.
    if event_type == "webhook.test":
        logger.info("GeniusPay webhook — test reçu OK")
        return JsonResponse({"message": "OK"})

    # Vérifier que le timestamp n'a pas plus de 5 minutes (replay protection)
    if timestamp:
        try:
            import time
            age = abs(time.time() - int(timestamp))
            if age > 300:
                logger.warning("GeniusPay webhook — timestamp trop ancien (%ds)", age)
                return JsonResponse({"error": "timestamp_expired"}, status=400)
        except (TypeError, ValueError):
            pass

    # Vérification signature HMAC
    if not _verify_webhook_signature(raw_body, timestamp, received_sig):
        logger.warning("GeniusPay webhook — signature invalide pour event=%s", event_type)
        return JsonResponse({"error": "invalid_signature"}, status=403)

    try:
        event_data = json.loads(raw_body.decode("utf-8"))
    except Exception:
        return JsonResponse({"error": "invalid_payload"}, status=400)

    transaction_data = event_data.get("data", {})

    # ── PAYOUT (versement sortant) : payout.completed / payout.failed ────────
    if event_type in ("payout.completed", "payout.failed"):
        payout_data = transaction_data.get("payout") or transaction_data
        payout_ref = payout_data.get("reference", "")
        if not payout_ref:
            return JsonResponse({"message": "OK"})
        success = event_type == "payout.completed"
        try:
            from .services.wallet_service import WalletService
            from .services.escrow_service import EscrowService

            # 1) Retrait prestataire ? 2) sinon remboursement client.
            res = WalletService.handle_payout_webhook(
                external_reference=payout_ref, success=success, raw=payout_data
            )
            if res.get("error") == "tx_not_found":
                EscrowService.handle_refund_payout_webhook(
                    external_reference=payout_ref, success=success
                )
        except Exception as exc:
            logger.exception("payout webhook handling failed: %s", exc)
        return JsonResponse({"message": "OK"})

    reference = transaction_data.get("reference", "")

    if not reference:
        logger.warning("GeniusPay webhook — référence manquante dans payload")
        return JsonResponse({"message": "OK"})  # Toujours 200 pour éviter les retries

    # Retrouver le paiement local
    try:
        payment = Payment.objects.get(reference_externe=reference)
    except Payment.DoesNotExist:
        logger.warning("GeniusPay webhook — paiement introuvable ref=%s", reference)
        return JsonResponse({"message": "OK"})

    if event_type == "payment.success":
        # Vérification montant
        webhook_amount = transaction_data.get("amount")
        if webhook_amount is not None:
            try:
                if int(float(payment.montant)) != int(float(webhook_amount)):
                    logger.warning(
                        "GeniusPay webhook — montant mismatch ref=%s : attendu=%s reçu=%s",
                        reference, payment.montant, webhook_amount,
                    )
                    return JsonResponse({"error": "amount_mismatch"}, status=400)
            except (TypeError, ValueError):
                pass

        payment.etat = Payment.State.COMPLETE
        payment.valide_par_admin = True

        # Calculer et enregistrer la commission BABIFIX
        from decimal import Decimal
        from adminpanel.models import SystemSetting
        setting = SystemSetting.objects.first()
        commission_pct = setting.commission if setting else 18
        commission_rate = Decimal(str(commission_pct)) / Decimal("100")
        gross = Decimal(str(payment.montant or 0))
        commission = (gross * commission_rate).quantize(Decimal("1"))
        payment.commission = str(commission)

        payment.save(update_fields=["etat", "valide_par_admin", "commission"])

        # Phase F : ESCROW — on ne crédite plus le wallet du prestataire ici.
        # On délègue à EscrowService qui sait distinguer cash (commission =
        # acompte définitif) vs mobile (montant total bloqué en escrow).
        # Le wallet presta ne sera crédité qu'à la confirmation client via
        # `EscrowService.release_funds`.
        if payment.reservation:
            try:
                from .services.escrow_service import EscrowService
                EscrowService.mark_escrow_received(payment)
            except Exception as exc:
                logger.exception("EscrowService.mark_escrow_received failed: %s", exc)
                # En fallback on garde l'ancien marqueur pour ne pas bloquer.
                payment.reservation.cash_flow_status = (
                    Reservation.CashFlowStatus.PENDING_ADMIN
                )
                payment.reservation.save(update_fields=["cash_flow_status"])

            # Notifier le prestataire (sans plus parler de wallet — il sera
            # crédité à la confirmation client).
            try:
                from .push_dispatch import _schedule
                _schedule(
                    [payment.reservation.prestataire_user_id],
                    "BABIFIX — Acompte reçu",
                    (
                        f"Le client a versé l'acompte pour {payment.reservation.reference}. "
                        f"Vous pouvez démarrer l'intervention."
                    ),
                    {
                        "type": "payment.received",
                        "reference": payment.reservation.reference,
                    },
                )
            except Exception as exc:
                logger.warning("Push notification failed: %s", exc)

        # B3 — Le reçu PDF est désormais envoyé À LA CONFIRMATION FINALE
        # du client (via `EscrowService.release_funds` → signal applicatif),
        # pas à l'acompte. En cash, l'acompte est seulement la commission
        # (3 600 FCFA) — envoyer un "Reçu 3 600 F" serait trompeur.
        # Voir `api_client_confirmer_travaux` qui déclenche l'envoi.

        # Phase F : NE PLUS créditer le wallet ici. Le crédit a lieu à
        # `EscrowService.release_funds`, déclenché par la confirmation
        # explicite du client.
        logger.info("GeniusPay webhook — paiement %s SUCCÈS (en escrow)", payment.reference)

    elif event_type in ("payment.failed", "payment.cancelled", "payment.expired"):
        payment.etat = Payment.State.DISPUTE
        payment.save(update_fields=["etat"])
        logger.info("GeniusPay webhook — paiement %s %s", payment.reference, event_type.upper())

    elif event_type == "webhook.test":
        logger.info("GeniusPay webhook — test reçu OK")

    return JsonResponse({"message": "OK"})
