"""
CinetPay Mobile Money — Côte d'Ivoire
Endpoints : initiate / status / webhook
"""

import hashlib
import hmac
import json
import logging
import os
import uuid
from datetime import datetime

from django.conf import settings
from django.http import JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_GET, require_POST

import urllib.request
import urllib.error

from .auth import require_api_auth
from .throttle import check_rate_limit, rate_limited_response
from .models import Payment, Reservation

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Config CinetPay (variables d'environnement)
# ---------------------------------------------------------------------------
CINETPAY_APIKEY = os.getenv("CINETPAY_APIKEY", "")
CINETPAY_SITE_ID = os.getenv("CINETPAY_SITE_ID", "")
CINETPAY_BASE_URL = "https://api-checkout.cinetpay.com/v2"


def _cinetpay_post(path: str, payload: dict) -> dict:
    """HTTP POST vers l'API CinetPay — stdlib urllib (aucune dépendance)."""
    url = CINETPAY_BASE_URL + path
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        logger.error("CinetPay HTTP %s — %s", e.code, body)
        return {"code": str(e.code), "message": body}
    except Exception as exc:
        logger.error("CinetPay network error: %s", exc)
        return {"code": "NETWORK_ERROR", "message": str(exc)}


def _verify_webhook_signature(payload: dict, received_sig: str) -> bool:
    """Vérifie la signature HMAC-SHA256 du webhook CinetPay."""
    if not CINETPAY_APIKEY:
        # Clé non configurée → accepter en dev (warning)
        logger.warning("CINETPAY_APIKEY non configurée — signature ignorée en dev.")
        return True
    # CinetPay signe : cpm_site_id + cpm_trans_id + cpm_amount + apikey
    msg = (
        str(payload.get("cpm_site_id", ""))
        + str(payload.get("cpm_trans_id", ""))
        + str(payload.get("cpm_amount", ""))
        + CINETPAY_APIKEY
    )
    expected = hmac.new(
        CINETPAY_APIKEY.encode("utf-8"),
        msg.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    return hmac.compare_digest(expected, received_sig or "")


# ---------------------------------------------------------------------------
# Initiation paiement Mobile Money
# POST /api/paiements/cinetpay/initiate/
# ---------------------------------------------------------------------------
@csrf_exempt
@require_api_auth(["client", "prestataire", "admin"])
def cinetpay_initiate(request):
    # ✅ S5: Rate limiting sur les paiements
    if check_rate_limit(request, "cinetpay", max_requests=10, window=60):
        return rate_limited_response()
    
    if request.method != "POST":
        return JsonResponse({"error": "method_not_allowed"}, status=405)
    try:
        payload = json.loads(request.body)
    except (json.JSONDecodeError, ValueError):
        return JsonResponse({"error": "invalid_json"}, status=400)

    reservation_id = payload.get("reservation")
    montant = payload.get("montant")
    operator = str(payload.get("operator", "ORANGE_MONEY")).upper()
    phone = str(payload.get("phone", "")).strip()
    mode = str(payload.get("mode_paiement", "MOBILE_MONEY")).upper()

    if not reservation_id or not montant:
        return JsonResponse({"error": "missing_fields"}, status=400)
    if not phone:
        return JsonResponse({"error": "phone_required"}, status=400)

    try:
        reservation = Reservation.objects.get(pk=reservation_id)
    except Reservation.DoesNotExist:
        return JsonResponse({"error": "reservation_not_found"}, status=404)

    # Idempotence : vérifier si paiement PENDING existe déjà
    existing = Payment.objects.filter(
        reservation=reservation,
        etat=Payment.State.PENDING,
    ).first()
    if existing:
        return JsonResponse(
            {
                "transaction_id": existing.reference_externe,
                "payment_id": existing.pk,
                "status": "PENDING",
                "message": "Paiement déjà en cours.",
            }
        )

    # Générer un identifiant de transaction unique
    transaction_id = "BABFX-" + uuid.uuid4().hex[:16].upper()

    # Créer le paiement local en PENDING
    payment_ref = "PAY-" + uuid.uuid4().hex[:10].upper()
    payment = Payment.objects.create(
        reference=payment_ref,
        client=reservation.client,
        prestataire=reservation.prestataire,
        montant=str(montant),
        commission="0",
        etat=Payment.State.PENDING,
        reservation=reservation,
        type_paiement=Payment.TypePaiement.MOBILE_MONEY,
        valide_par_admin=False,
        reference_externe=transaction_id,
    )

    # Appel CinetPay si clés configurées
    if CINETPAY_APIKEY and CINETPAY_SITE_ID:
        # Mapper opérateur CI → code CinetPay
        operator_map = {
            "ORANGE_MONEY": "OM",
            "MTN_MOMO": "MTNCI",
            "WAVE": "WAVE",
            "MOOV": "MOOV",
        }
        cp_operator = operator_map.get(operator, "OM")
        cinetpay_payload = {
            "apikey": CINETPAY_APIKEY,
            "site_id": CINETPAY_SITE_ID,
            "transaction_id": transaction_id,
            "amount": int(montant),
            "currency": "XOF",
            "description": f"BABIFIX — Réservation {reservation.reference}",
            "phone_number": phone,
            "payment_method": cp_operator,
            "customer_name": reservation.client,
            "customer_email": "",
            "notify_url": os.getenv("CINETPAY_NOTIFY_URL", ""),
            "return_url": os.getenv("CINETPAY_RETURN_URL", ""),
        }
        cp_resp = _cinetpay_post("/payment", cinetpay_payload)
        cp_code = str(cp_resp.get("code", "")).upper()
        if cp_code not in ("00", "200", "SUCCESS", "CREATED"):
            payment.delete()
            return JsonResponse(
                {
                    "error": "cinetpay_error",
                    "message": cp_resp.get("message", "Erreur CinetPay"),
                },
                status=502,
            )

    return JsonResponse(
        {
            "transaction_id": transaction_id,
            "payment_id": payment.pk,
            "status": "PENDING",
            "message": "Paiement initié. En attente de confirmation USSD.",
        }
    )


# ---------------------------------------------------------------------------
# Statut d'un paiement CinetPay
# GET /api/paiements/cinetpay/status/<transaction_id>/
# ---------------------------------------------------------------------------
@require_api_auth(["client", "prestataire", "admin"])
@require_GET
def cinetpay_status(request, transaction_id):
    try:
        payment = Payment.objects.get(reference_externe=transaction_id)
    except Payment.DoesNotExist:
        return JsonResponse({"error": "not_found"}, status=404)

    # Mapper l'état interne vers le statut API
    status_map = {
        Payment.State.PENDING: "PENDING",
        Payment.State.COMPLETE: "SUCCESS",
        Payment.State.DISPUTE: "FAILED",
    }
    return JsonResponse(
        {
            "transaction_id": transaction_id,
            "status": status_map.get(payment.etat, "PENDING"),
            "amount": payment.montant,
            "reference": payment.reference,
        }
    )


# ---------------------------------------------------------------------------
# Webhook CinetPay (notification asynchrone)
# POST /api/paiements/cinetpay/webhook/
# ---------------------------------------------------------------------------
@csrf_exempt
def cinetpay_webhook(request):
    """
    CinetPay envoie un POST avec les données de paiement.
    cpm_result == '00' → SUCCÈS
    """
    if request.method != "POST":
        return JsonResponse({"error": "method_not_allowed"}, status=405)

    try:
        if request.content_type and "json" in request.content_type:
            payload = json.loads(request.body)
        else:
            payload = dict(request.POST)
            payload = {
                k: v[0] if isinstance(v, list) else v for k, v in payload.items()
            }
    except Exception:
        return JsonResponse({"error": "invalid_payload"}, status=400)

    transaction_id = payload.get("cpm_trans_id", "")
    result_code = str(payload.get("cpm_result", "")).strip()
    received_sig = payload.get("signature", "")

    logger.info("CinetPay webhook — tx=%s result=%s", transaction_id, result_code)

    if not transaction_id:
        return JsonResponse({"error": "missing_transaction_id"}, status=400)

    # Vérification signature (optionnelle en dev)
    if not _verify_webhook_signature(payload, received_sig):
        logger.warning(
            "CinetPay webhook — signature invalide pour tx=%s", transaction_id
        )
        return JsonResponse({"error": "invalid_signature"}, status=403)

    try:
        payment = Payment.objects.get(reference_externe=transaction_id)
    except Payment.DoesNotExist:
        logger.warning("CinetPay webhook — paiement introuvable tx=%s", transaction_id)
        return JsonResponse(
            {"message": "OK"}
        )  # Toujours 200 pour éviter les retry CinetPay

    # Vérification du montant payé vs montant réservation
    webhook_amount = payload.get("cpm_amount")
    if webhook_amount is not None:
        try:
            expected_amount = int(float(payment.montant))
            received_amount = int(float(webhook_amount))
            if expected_amount != received_amount:
                logger.warning(
                    "CinetPay webhook — montant mismatch pour tx=%s: attendu=%d, reçu=%d",
                    transaction_id,
                    expected_amount,
                    received_amount,
                )
                return JsonResponse({"error": "amount_mismatch"}, status=400)
        except (TypeError, ValueError) as e:
            logger.warning(
                "CinetPay webhook — montant invalide tx=%s: %s", transaction_id, e
            )

    if result_code == "00":
        # SUCCÈS
        payment.etat = Payment.State.COMPLETE
        payment.valide_par_admin = False  # Validé automatiquement par CinetPay
        payment.save(update_fields=["etat", "valide_par_admin"])

        # Mettre à jour le cash_flow de la réservation
        if payment.reservation:
            payment.reservation.cash_flow_status = (
                Reservation.CashFlowStatus.PENDING_ADMIN
            )
            payment.reservation.save(update_fields=["cash_flow_status"])

            # Notifier le prestataire que le client a payé
            try:
                from adminpanel.push_dispatch import _schedule

                _schedule(
                    [payment.reservation.prestataire_user_id],
                    "BABIFIX — Paiement reçu",
                    f"Le client a payé pour {payment.reservation.reference}. Vous pouvez commencer l'intervention.",
                    {
                        "type": "payment.received",
                        "reference": payment.reservation.reference,
                    },
                )
            except Exception:
                pass

        # Générer et envoyer le reçu PDF au client
        try:
            from adminpanel.services.invoice_service import InvoiceService
            from adminpanel.views_extra import send_babifix_email_html
            from django.template.loader import render_to_string

            pdf_bytes = InvoiceService.generate_pdf(payment)
            if pdf_bytes and payment.reservation and payment.reservation.client_user:
                client_email = payment.reservation.client_user.email
                invoice_number = InvoiceService.generate_invoice_number(payment)
                html_content = render_to_string(
                    "emails/receipt_email.html",
                    {
                        "invoice_number": invoice_number,
                        "reference": payment.reservation.reference,
                        "service_title": payment.reservation.titre or payment.reservation.reference,
                        "montant": payment.montant,
                        "operateur": payment.operateur or "Mobile Money",
                        "client_name": payment.reservation.client_user.get_full_name()
                        or payment.reservation.client_user.username,
                    },
                )
                send_babifix_email_html(
                    to_email=client_email,
                    subject=f"BABIFIX — Reçu de paiement {invoice_number}",
                    html_content=html_content,
                    attachments=[
                        (f"recu_{invoice_number}.pdf", pdf_bytes, "application/pdf")
                    ],
                )
                logger.info("Reçu PDF envoyé à %s pour paiement %s", client_email, payment.reference)
        except Exception as exc:
            logger.warning("Erreur envoi reçu PDF pour paiement %s: %s", payment.reference, exc)

        # Créditer le wallet prestataire (net après commission 15 %)
        try:
            from adminpanel.services.wallet_service import WalletService
            wallet_result = WalletService.credit_provider(payment)
            logger.info("WalletService credit: %s", wallet_result)
        except Exception as exc:
            logger.warning("Erreur crédit wallet prestataire pour paiement %s: %s", payment.reference, exc)

        logger.info("CinetPay webhook — paiement %s SUCCÈS", payment.reference)
    else:
        # ÉCHEC
        payment.etat = Payment.State.DISPUTE
        payment.save(update_fields=["etat"])
        logger.info(
            "CinetPay webhook — paiement %s ÉCHEC (code=%s)",
            payment.reference,
            result_code,
        )

    return JsonResponse({"message": "OK"})
