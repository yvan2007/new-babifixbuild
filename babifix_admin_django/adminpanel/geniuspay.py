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
GENIUSPAY_BASE_URL    = "https://geniuspay.ci/api/v1/merchant"   # new_Version (old: pay.genius.ci)
GENIUSPAY_WEBHOOK_URL = os.getenv("GENIUSPAY_WEBHOOK_URL", getattr(settings, "GENIUSPAY_WEBHOOK_URL", ""))
GENIUSPAY_SUCCESS_URL = os.getenv("GENIUSPAY_SUCCESS_URL", getattr(settings, "GENIUSPAY_SUCCESS_URL", ""))
GENIUSPAY_ERROR_URL   = os.getenv("GENIUSPAY_ERROR_URL",   getattr(settings, "GENIUSPAY_ERROR_URL", ""))

# Interrupteur explicite : GENIUSPAY_SIMULATE=true|1|yes force le mode
# simulation (auto-validation) quelles que soient les clés. Indispensable pour
# tester en ligne (Render) avec de vraies clés mais sans confirmation USSD
# réelle. Mettre la variable à false en production réelle.
GENIUSPAY_SIMULATE = os.getenv("GENIUSPAY_SIMULATE", "").strip().lower() in ("1", "true", "yes", "on")

# Mode SIMULATION : interrupteur explicite, OU clés sandbox (pk_sandbox/
# sk_sandbox), OU clés absentes → on auto-valide les paiements sans dépendre de
# l'API temps réel (utile en démo et sur Render). En clés LIVE, vrai flux + webhook.
GENIUSPAY_SANDBOX = (
    GENIUSPAY_SIMULATE
    or (GENIUSPAY_PUBLIC_KEY or "").startswith("pk_sandbox")
    or (GENIUSPAY_SECRET_KEY or "").startswith("sk_sandbox")
    or not GENIUSPAY_PUBLIC_KEY
    or not GENIUSPAY_SECRET_KEY
)

# Mapping opérateurs BABIFIX → codes GeniusPay
_OPERATOR_MAP = {
    "ORANGE_MONEY": "orange_money",
    "MTN_MOMO":     "mtn_money",
    "WAVE":         "wave",
    "PAWAPAY":      "pawapay",
    "MOOV":         "pawapay",   # PawaPay gère Moov via auto-routing
}

# Statuts antérieurs à la confirmation : passables à « Confirmee » au paiement
# de l'acompte. Au-delà, on ne régresse jamais le statut.
_PRE_CONFIRM_STATUSES = {
    "En attente", "PENDING", "DEMANDE_ENVOYEE", "DEVIS_ENVOYE", "DEVIS_ACCEPTE",
}


def _apply_payment_phase(reservation, payment) -> str:
    """Applique un paiement à la réservation SELON LA PHASE (acompte/solde).

    1er paiement (acompte non validé) = acompte ; 2e = solde. On se base sur
    ``acompte_valide`` pour ne PAS réécraser l'acompte au paiement du solde
    (sinon le client « repaie » le reste indéfiniment). Utilisé par l'init
    (simulation/sandbox) ET par le webhook. Retourne 'acompte' ou 'solde'.
    """
    from decimal import Decimal
    total = reservation.montant or Decimal("0")
    paid_now = Decimal(str(payment.montant or 0))
    if not reservation.acompte_valide:
        reservation.acompte_valide = True
        reservation.montant_verse = paid_now
        reservation.montant_restant = max(Decimal("0"), total - paid_now)
        fields = ["acompte_valide", "montant_verse", "montant_restant"]
        if reservation.statut in _PRE_CONFIRM_STATUSES:
            reservation.statut = Reservation.Status.CONFIRMED
            fields.append("statut")
        reservation.save(update_fields=fields)
        return "acompte"
    new_verse = (reservation.montant_verse or Decimal("0")) + paid_now
    if new_verse > total:
        new_verse = total
    reservation.montant_verse = new_verse
    reservation.montant_restant = max(Decimal("0"), total - new_verse)
    fields = ["montant_verse", "montant_restant"]
    solde_complet = reservation.montant_restant <= 0
    if solde_complet:
        reservation.solde_valide = True
        fields.append("solde_valide")
    # ORDRE MÉTIER (Mobile Money) : le client confirme les travaux AVANT de payer
    # le solde. Si la confirmation est déjà faite et que le solde vient d'être
    # complété, on finalise ICI : passage « Terminee » + libération des fonds au
    # prestataire. (Si pas encore confirmé, on attend la confirmation.)
    if (
        solde_complet
        and reservation.client_confirme_prestation_at
        and reservation.statut not in ("Terminee", "Annulee")
    ):
        reservation.statut = Reservation.Status.DONE
        fields.append("statut")
    reservation.save(update_fields=fields)
    if solde_complet and reservation.client_confirme_prestation_at:
        try:
            from .services.escrow_service import EscrowService
            EscrowService.release_funds(reservation)
        except Exception:
            pass
    return "solde"


def _send_receipt_email(payment) -> None:
    """Génère le reçu PDF et l'envoie par e-mail au client (silencieux si échec)."""
    try:
        from .services.invoice_service import InvoiceService
        from .views_extra import send_babifix_email_html
        from django.template.loader import render_to_string

        res = getattr(payment, "reservation", None)
        client_user = getattr(res, "client_user", None) if res else None
        if not (client_user and client_user.email):
            return
        pdf_bytes = InvoiceService.generate_pdf(payment)
        if not pdf_bytes:
            return
        invoice_number = InvoiceService.generate_invoice_number(payment)
        html_content = render_to_string(
            "emails/receipt_email.html",
            {
                "invoice_number": invoice_number,
                "reference":      res.reference,
                "service_title":  getattr(res, "title", None) or res.reference,
                "montant":        payment.montant,
                "operateur":      "GeniusPay / Mobile Money",
                "client_name":    client_user.get_full_name() or client_user.username,
            },
        )
        send_babifix_email_html(
            to_email=client_user.email,
            subject=f"BABIFIX : Reçu de paiement {invoice_number}",
            html_content=html_content,
            attachments=[(f"recu_{invoice_number}.pdf", pdf_bytes, "application/pdf")],
        )
    except Exception as exc:  # noqa: BLE001
        logger.warning(
            "Erreur envoi reçu PDF pour paiement %s: %s",
            getattr(payment, "reference", "?"), exc,
        )


# ---------------------------------------------------------------------------
# HTTP helper — stdlib urllib (aucune dépendance externe)
# ---------------------------------------------------------------------------
def _genius_request(method: str, path: str, payload: dict | None = None) -> dict:
    """Appel REST vers l'API GeniusPay via cloudscraper (bypass Cloudflare)."""
    import cloudscraper

    scraper = cloudscraper.create_scraper(browser={"browser": "chrome", "platform": "windows", "desktop": True})
    url = GENIUSPAY_BASE_URL + path
    headers = {
        "Authorization":    f"Bearer {GENIUSPAY_PUBLIC_KEY}",
        "Accept":           "application/json, text/plain, */*",
        "Accept-Language":  "fr-FR,fr;q=0.9",
    }
    try:
        resp = scraper.request(method.upper(), url, json=payload, headers=headers, timeout=20)
        if resp.status_code >= 400:
            logger.error("GeniusPay HTTP %d %s %s — %s", resp.status_code, method, path, resp.text[:500])
            return {"success": False, "error": resp.text, "status_code": resp.status_code}
        return resp.json()
    except Exception as exc:
        logger.error("GeniusPay network error: %s", exc)
        return {"success": False, "error": str(exc)}


# ---------------------------------------------------------------------------
# Vérification signature webhook
# Formula : HMAC-SHA256(timestamp + "." + json_body_string, secret_key)
# ---------------------------------------------------------------------------
def _verify_webhook_signature(raw_body: bytes, timestamp: str, received_sig: str) -> bool:
    if not GENIUSPAY_SECRET_KEY:
        logger.warning("GENIUSPAY_SECRET_KEY non configurée — signature ignorée en dev.")
        return True
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

    # Accepte un ID numérique OU une référence (RES-… / E2E-…) sans jamais planter.
    try:
        if str(reservation_id).isdigit():
            reservation = Reservation.objects.get(pk=int(reservation_id))
        else:
            reservation = Reservation.objects.get(reference=str(reservation_id))
    except (Reservation.DoesNotExist, ValueError, TypeError):
        return JsonResponse({"error": "reservation_not_found"}, status=404)

    # Persiste l'opérateur choisi AU PAIEMENT sur la réservation (l'opérateur
    # n'est plus demandé à la réservation — seulement le mode). Sert aussi de
    # cible pour un éventuel remboursement Mobile Money.
    if operator_raw in {"ORANGE_MONEY", "MTN_MOMO", "WAVE", "MOOV"}:
        if reservation.mobile_money_operator != operator_raw:
            reservation.mobile_money_operator = operator_raw
            try:
                reservation.save(update_fields=["mobile_money_operator"])
            except Exception:
                pass

    # Idempotence : paiement PENDING déjà existant ?
    existing = Payment.objects.filter(
        reservation=reservation,
        etat=Payment.State.PENDING,
    ).first()
    if existing:
        # En mode simulation (sandbox/dev), un pending périmé bloquerait
        # l'auto-validation → on le supprime pour repartir proprement.
        if GENIUSPAY_SANDBOX or settings.DEBUG:
            existing.delete()
        else:
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

    # Tentative réelle vers l'API GeniusPay
    def _do_fake_validation(ref: str) -> JsonResponse:
        """Simulation de validation — fallback quand l'API est indisponible."""
        payment.reference_externe = ref
        payment.etat = Payment.State.COMPLETE
        payment.save(update_fields=["reference_externe", "etat"])
        phase = _apply_payment_phase(reservation, payment)
        # Reçu PDF par e-mail (acompte ET solde) — fonctionne aussi en local.
        _send_receipt_email(payment)
        return JsonResponse({
            "transaction_id": ref,
            "payment_id":     payment.pk,
            "payment_url":    "",
            "checkout_url":   "",
            "status":         "valide",
            "message": "Solde payé !" if phase == "solde"
            else "Acompte validé (simulation, API indisponible).",
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

    # Mode SIMULATION (dev / clés sandbox) → auto-validation immédiate, sans
    # dépendre de la réponse temps réel de l'agrégateur (qui renvoie "pending"
    # et ferait afficher « Erreur de paiement »). En clés LIVE → API réelle.
    if settings.DEBUG or GENIUSPAY_SANDBOX:
        logger.info("GeniusPay: mode simulation — auto-validation %s", payment_ref)
        return _do_fake_validation("MTX-SANDBOX-" + uuid.uuid4().hex[:8].upper())

    genius_resp = _genius_request("POST", "/payments", genius_payload)

    if not genius_resp.get("success"):
        # Fallback simulation si en dev ou pas de clés
        if settings.DEBUG or not GENIUSPAY_PUBLIC_KEY or not GENIUSPAY_SECRET_KEY:
            mode = "DEBUG" if settings.DEBUG else "clés API manquantes"
            logger.warning("GeniusPay API échouée, fallback simulation (%s) : %s", mode, genius_resp)
            return _do_fake_validation("MTX-SIMUL-" + uuid.uuid4().hex[:8].upper())
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

    status = data.get("status", "pending")

    # Auto-validation sandbox — pas de checkout_url ouvert par le mobile
    is_sandbox = str(genius_reference).startswith("SANDBOX_")
    if is_sandbox or status.lower() in ("success", "valide"):
        # Marquer le paiement complet
        payment.etat = Payment.State.COMPLETE
        payment.save(update_fields=["etat"])

        # Appliquer le paiement à la réservation selon la phase (acompte/solde)
        phase = "acompte"
        if payment.reservation:
            phase = _apply_payment_phase(payment.reservation, payment)
            # Reçu PDF par e-mail (acompte ET solde)
            _send_receipt_email(payment)

        # Notifier le prestataire selon la phase
        try:
            from .push_dispatch import _schedule
            if phase == "solde":
                _schedule(
                    [payment.reservation.prestataire_user_id],
                    "BABIFIX · Solde reçu",
                    f"Le client a payé le solde pour {payment.reservation.reference}.",
                    {"type": "solde.valide", "reference": payment.reservation.reference},
                )
            else:
                _schedule(
                    [payment.reservation.prestataire_user_id],
                    "BABIFIX · Acompte reçu",
                    f"Le client a payé l'acompte pour {payment.reservation.reference}. Réservation confirmée.",
                    {"type": "acompte.valide", "reference": payment.reservation.reference},
                )
        except Exception as exc:
            logger.warning("Push notification failed: %s", exc)

        logger.info("GeniusPay sandbox auto-validee (%s): %s", phase, genius_reference)
        return JsonResponse({
            "transaction_id": genius_reference,
            "payment_id":     payment.pk,
            "payment_url":    data.get("payment_url", ""),
            "checkout_url":   data.get("checkout_url", ""),
            "status":         "COMPLETE",
            "message":        "Solde payé !" if phase == "solde" else "Acompte validé !",
        })

    return JsonResponse({
        "transaction_id": genius_reference,
        "payment_id":     payment.pk,
        "payment_url":    data.get("payment_url", ""),
        "checkout_url":   data.get("checkout_url", ""),
        "status":         status,
        "message":        "Paiement initié. Suivez les instructions sur votre téléphone.",
    })


# ---------------------------------------------------------------------------
# Abonnement premium prestataire payé via Mobile Money (GeniusPay)
# ---------------------------------------------------------------------------
def _activate_premium_from_payment(payment) -> bool:
    """Active l'abonnement premium à partir d'un Payment 'PREMIUM-…' complété.

    La référence encode tout le contexte : PREMIUM-{provider_id}-{tier}-{A|M}-{hex}.
    Utilisé par la simulation (auto-validation) ET par le webhook réel.
    """
    ref = payment.reference or ""
    if not ref.startswith("PREMIUM-"):
        return False
    parts = ref.split("-")
    if len(parts) < 4:
        return False
    try:
        provider_id = int(parts[1])
    except (ValueError, TypeError):
        return False
    tier = parts[2].lower()
    is_annual = parts[3].upper() == "A"

    from .models import Provider
    from .services.provider_subscription_service import (
        ProviderSubscriptionService,
        PREMIUM_TIERS,
    )

    if tier not in PREMIUM_TIERS:
        return False
    provider = Provider.objects.filter(pk=provider_id).first()
    if not provider:
        return False

    duration = 365 if is_annual else 30
    result = ProviderSubscriptionService.subscribe(
        provider, tier, duration_days=duration, is_annual=is_annual
    )
    if not result.success:
        return False
    # Enregistrer le revenu premium + notifier le prestataire.
    try:
        from .services.wallet_service import WalletService
        WalletService.credit_provider_premium(provider, tier, payment.montant)
    except Exception as exc:
        logger.warning("credit_provider_premium failed: %s", exc)
    try:
        from .views_finance import _notify_premium_activated
        _notify_premium_activated(provider, tier, trial=False)
    except Exception:
        pass
    logger.info("Premium activé via GeniusPay pour provider=%s tier=%s", provider_id, tier)
    return True


@require_api_auth(["prestataire", "admin"])
def geniuspay_premium_initiate(request):
    """
    POST → payer un abonnement premium via Mobile Money (GeniusPay).

    Body JSON : tier ('silver'|'gold'), billing_period ('monthly'|'annual'),
                mobile_money_operator (ORANGE_MONEY|MTN_MOMO|WAVE|MOOV).

    Au succès (simulation, sandbox, ou webhook réel), l'abonnement est activé
    directement — sans transiter par le wallet.
    """
    if request.method != "POST":
        return JsonResponse({"error": "method_not_allowed"}, status=405)
    if check_rate_limit(request, "geniuspay", max_requests=10, window=60):
        return rate_limited_response()
    try:
        payload = json.loads(request.body)
    except (json.JSONDecodeError, ValueError):
        return JsonResponse({"error": "invalid_json"}, status=400)

    from .models import Provider
    from .services.provider_subscription_service import PREMIUM_TIERS, annual_price

    provider = Provider.objects.filter(user_id=request.api_user_id).first()
    if not provider:
        return JsonResponse({"error": "provider_not_found"}, status=404)

    tier = str(payload.get("tier") or "").lower()
    if tier not in PREMIUM_TIERS:
        return JsonResponse(
            {"error": "tier_invalide", "valid": list(PREMIUM_TIERS.keys())}, status=400
        )
    billing_period = str(payload.get("billing_period") or "monthly").lower()
    is_annual = billing_period == "annual"
    monthly = int(PREMIUM_TIERS[tier]["price"])
    montant_int = annual_price(monthly) if is_annual else monthly

    operator_raw = str(
        payload.get("mobile_money_operator") or payload.get("payment_method") or ""
    ).upper().strip()
    phone = str(payload.get("phone", "")).strip()
    customer_name = str(
        payload.get("customer_name", provider.nom or "Prestataire BABIFIX")
    ).strip()

    payment_ref = (
        f"PREMIUM-{provider.id}-{tier}-{'A' if is_annual else 'M'}-"
        f"{uuid.uuid4().hex[:6].upper()}"
    )
    payment = Payment.objects.create(
        reference=payment_ref,
        client="",
        prestataire=provider.nom or "",
        montant=str(montant_int),
        commission="0",
        etat=Payment.State.PENDING,
        reservation=None,
        type_paiement=Payment.TypePaiement.MOBILE_MONEY,
        valide_par_admin=False,
        reference_externe="",
    )

    def _fake_validate(extref: str) -> JsonResponse:
        payment.reference_externe = extref
        payment.etat = Payment.State.COMPLETE
        payment.save(update_fields=["reference_externe", "etat"])
        _activate_premium_from_payment(payment)
        return JsonResponse({
            "ok": True,
            "transaction_id": extref,
            "payment_id": payment.pk,
            "checkout_url": "",
            "payment_url": "",
            "status": "valide",
            "tier": tier,
            "is_annual": is_annual,
            "message": "Abonnement premium activé (simulation).",
        })

    # Mode simulation (dev / sandbox / clés absentes) → activation immédiate.
    if settings.DEBUG or GENIUSPAY_SANDBOX:
        return _fake_validate("MTX-SANDBOX-" + uuid.uuid4().hex[:8].upper())

    genius_payload = {
        "amount": montant_int,
        "currency": "XOF",
        "customer": {
            "name": customer_name,
            "email": f"presta_{provider.id}@babifix.ci",
            "phone": phone or "",
            "country": "CI",
        },
        "metadata": {
            "premium": True,
            "provider_id": str(provider.id),
            "tier": tier,
            "billing": "annual" if is_annual else "monthly",
            "payment_ref": payment_ref,
        },
        "success_url": GENIUSPAY_SUCCESS_URL or "",
        "error_url": GENIUSPAY_ERROR_URL or "",
    }
    if operator_raw in _OPERATOR_MAP:
        genius_payload["payment_method"] = _OPERATOR_MAP[operator_raw]

    genius_resp = _genius_request("POST", "/payments", genius_payload)
    if not genius_resp.get("success"):
        if settings.DEBUG or not GENIUSPAY_PUBLIC_KEY or not GENIUSPAY_SECRET_KEY:
            return _fake_validate("MTX-SIMUL-" + uuid.uuid4().hex[:8].upper())
        payment.delete()
        return JsonResponse(
            {
                "error": "geniuspay_error",
                "message": genius_resp.get("message") or genius_resp.get("error") or "Erreur GeniusPay",
            },
            status=502,
        )

    data = genius_resp.get("data", {})
    genius_reference = data.get("reference", "")
    payment.reference_externe = genius_reference
    payment.save(update_fields=["reference_externe"])
    status = data.get("status", "pending")

    if str(genius_reference).startswith("SANDBOX_") or status.lower() in ("success", "valide"):
        payment.etat = Payment.State.COMPLETE
        payment.save(update_fields=["etat"])
        _activate_premium_from_payment(payment)
        return JsonResponse({
            "ok": True,
            "transaction_id": genius_reference,
            "payment_id": payment.pk,
            "checkout_url": data.get("checkout_url", ""),
            "payment_url": data.get("payment_url", ""),
            "status": "COMPLETE",
            "tier": tier,
            "is_annual": is_annual,
            "message": "Abonnement premium activé !",
        })

    return JsonResponse({
        "transaction_id": genius_reference,
        "payment_id": payment.pk,
        "checkout_url": data.get("checkout_url", ""),
        "payment_url": data.get("payment_url", ""),
        "status": status,
        "message": "Paiement initié. Suivez les instructions sur votre téléphone.",
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

    # Vérification signature HMAC — ignorée en debug (sandbox local)
    if settings.DEBUG:
        logger.info("GeniusPay webhook — DEBUG, signature non vérifiée")
    elif environment.lower() == "sandbox":
        logger.info("GeniusPay webhook — sandbox, signature non vérifiée")
    elif not _verify_webhook_signature(raw_body, timestamp, received_sig):
        logger.warning("GeniusPay webhook — signature invalide pour event=%s", event_type)
        return JsonResponse({"error": "invalid_signature"}, status=403)

    try:
        event_data = json.loads(raw_body.decode("utf-8"))
    except Exception:
        return JsonResponse({"error": "invalid_payload"}, status=400)

    transaction_data = event_data.get("data", {})
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
        payment.valide_par_admin = False
        payment.save(update_fields=["etat", "valide_par_admin"])

        phase = "acompte"
        if payment.reservation:
            res = payment.reservation
            # Phase-aware (acompte / solde) — plus de réécrasement de l'acompte.
            phase = _apply_payment_phase(res, payment)

            # Notifier le prestataire selon la phase
            try:
                from .push_dispatch import _schedule
                if phase == "solde":
                    _schedule(
                        [res.prestataire_user_id],
                        "BABIFIX · Solde reçu",
                        f"Le client a payé le solde pour {res.reference}.",
                        {"type": "solde.valide", "reference": res.reference},
                    )
                else:
                    _schedule(
                        [res.prestataire_user_id],
                        "BABIFIX · Acompte reçu",
                        f"Le client a payé l'acompte pour {res.reference}. Réservation confirmée.",
                        {"type": "acompte.valide", "reference": res.reference},
                    )
            except Exception as exc:
                logger.warning("Push notification failed: %s", exc)

            # Reçu PDF par e-mail (acompte ET solde)
            _send_receipt_email(payment)

        # Paiement d'abonnement premium (sans réservation) → activer le premium.
        if not payment.reservation and (payment.reference or "").startswith("PREMIUM-"):
            try:
                _activate_premium_from_payment(payment)
            except Exception as exc:
                logger.warning("Premium activation (webhook) failed: %s", exc)

        logger.info("GeniusPay webhook — paiement %s SUCCÈS (%s) pour %s",
                    payment.reference, phase,
                    payment.reservation.reference if payment.reservation else "?")

    elif event_type in ("payment.failed", "payment.cancelled", "payment.expired"):
        payment.etat = Payment.State.DISPUTE
        payment.save(update_fields=["etat"])
        logger.info("GeniusPay webhook — paiement %s %s", payment.reference, event_type.upper())

    elif event_type == "webhook.test":
        logger.info("GeniusPay webhook — test reçu OK")

    return JsonResponse({"message": "OK"})
