"""
SMS Service — envoi de SMS / codes, branchable et gratuit pour démarrer.

Fournisseur choisi via la variable d'env SMS_PROVIDER :
  - "console"  (défaut) : journalise le message (gratuit, idéal en dev/test)
  - "whatsapp"          : via WhatsApp Cloud API (réutilise whatsapp_service)
  - "twilio"            : via l'API Twilio (nécessite TWILIO_* — payant)
  - "orange"            : via l'API Orange SMS CI (nécessite ORANGE_SMS_* — payant)

Pour les CODES de vérification, le canal par défaut est l'E-MAIL (gratuit, déjà
configuré). On peut forcer un envoi SMS/WhatsApp si un numéro + fournisseur sont
disponibles.

Tout est conçu pour démarrer SANS coût ni clé : on branche un vrai fournisseur
payant plus tard en ajoutant juste les variables d'environnement.
"""
from __future__ import annotations

import logging
import os
import random
from typing import Optional

logger = logging.getLogger(__name__)


def _provider() -> str:
    return (os.getenv("SMS_PROVIDER") or "console").strip().lower()


def generate_code(length: int = 6) -> str:
    """Génère un code numérique (OTP)."""
    return "".join(str(random.randint(0, 9)) for _ in range(length))


def send_sms(phone: str, message: str) -> dict:
    """Envoie un SMS via le fournisseur configuré. Retourne {ok, channel, reason}."""
    phone = (phone or "").strip()
    if not phone:
        return {"ok": False, "channel": "none", "reason": "no_phone"}

    provider = _provider()

    if provider == "whatsapp":
        try:
            from .whatsapp_service import send_text
            ok = send_text(phone, message)
            return {"ok": bool(ok), "channel": "whatsapp",
                    "reason": "ok" if ok else "whatsapp_not_configured"}
        except Exception as e:
            logger.warning("SMS/WhatsApp: %s", e)
            return {"ok": False, "channel": "whatsapp", "reason": str(e)}

    if provider == "twilio":
        return _send_twilio(phone, message)

    if provider == "orange":
        return _send_orange(phone, message)

    # Défaut "console" : gratuit, journalisé (dev/test)
    logger.info("SMS (console) -> %s : %s", phone, message)
    return {"ok": True, "channel": "console", "reason": "logged"}


def _send_twilio(phone: str, message: str) -> dict:
    sid = os.getenv("TWILIO_ACCOUNT_SID", "")
    token = os.getenv("TWILIO_AUTH_TOKEN", "")
    sender = os.getenv("TWILIO_FROM_NUMBER", "")
    if not (sid and token and sender):
        logger.warning("Twilio non configuré (TWILIO_ACCOUNT_SID / AUTH_TOKEN / FROM_NUMBER).")
        return {"ok": False, "channel": "twilio", "reason": "not_configured"}
    try:
        import requests
        resp = requests.post(
            f"https://api.twilio.com/2010-04-01/Accounts/{sid}/Messages.json",
            data={"From": sender, "To": phone, "Body": message},
            auth=(sid, token),
            timeout=15,
        )
        ok = resp.status_code in (200, 201)
        return {"ok": ok, "channel": "twilio",
                "reason": "ok" if ok else f"http_{resp.status_code}"}
    except Exception as e:
        logger.warning("Twilio: %s", e)
        return {"ok": False, "channel": "twilio", "reason": str(e)}


def _send_orange(phone: str, message: str) -> dict:
    """Orange SMS API (Côte d'Ivoire). Nécessite un token OAuth + numéro expéditeur."""
    token = os.getenv("ORANGE_SMS_TOKEN", "")
    sender = os.getenv("ORANGE_SMS_SENDER", "")
    if not (token and sender):
        logger.warning("Orange SMS non configuré (ORANGE_SMS_TOKEN / ORANGE_SMS_SENDER).")
        return {"ok": False, "channel": "orange", "reason": "not_configured"}
    try:
        import requests
        url = f"https://api.orange.com/smsmessaging/v1/outbound/{sender}/requests"
        resp = requests.post(
            url,
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
            json={"outboundSMSMessageRequest": {
                "address": f"tel:{phone}",
                "senderAddress": sender,
                "outboundSMSTextMessage": {"message": message},
            }},
            timeout=15,
        )
        ok = resp.status_code in (200, 201)
        return {"ok": ok, "channel": "orange",
                "reason": "ok" if ok else f"http_{resp.status_code}"}
    except Exception as e:
        logger.warning("Orange SMS: %s", e)
        return {"ok": False, "channel": "orange", "reason": str(e)}


def _send_email_code(email: str, code: str) -> dict:
    try:
        from django.conf import settings
        from django.core.mail import send_mail
        send_mail(
            subject="BABIFIX : Votre code de vérification",
            message=f"Votre code de vérification BABIFIX est : {code}\n\n"
                    f"Il expire dans 10 minutes. Ne le partagez avec personne.",
            from_email=getattr(settings, "DEFAULT_FROM_EMAIL", None),
            recipient_list=[email],
            fail_silently=False,
        )
        return {"ok": True, "channel": "email", "reason": "ok"}
    except Exception as e:
        logger.warning("Email code: %s", e)
        return {"ok": False, "channel": "email", "reason": str(e)}


def send_verification_code(
    code: str,
    *,
    phone: Optional[str] = None,
    email: Optional[str] = None,
    prefer: Optional[str] = None,
) -> dict:
    """
    Envoie un code de vérification par le meilleur canal disponible.

    Stratégie (gratuite par défaut) :
      1. Si prefer="sms"/"whatsapp" et un numéro + fournisseur sont prêts → SMS/WhatsApp.
      2. Sinon, si un e-mail est fourni → e-mail (gratuit, recommandé par défaut).
      3. Sinon → SMS via fournisseur configuré (console en dev).

    Le code n'est jamais renvoyé au client : il doit être stocké (haché) côté serveur.
    """
    message = f"BABIFIX : votre code de vérification est {code}. Il expire dans 10 min."

    want_sms = prefer in ("sms", "whatsapp") and phone
    provider_ready = _provider() != "console" or prefer == "whatsapp"

    if want_sms and provider_ready:
        res = send_sms(phone, message)
        if res.get("ok"):
            return res
        # repli e-mail si l'envoi SMS échoue
        if email:
            return _send_email_code(email, code)
        return res

    if email:
        return _send_email_code(email, code)

    # dernier recours : SMS (console en dev)
    if phone:
        return send_sms(phone, message)

    return {"ok": False, "channel": "none", "reason": "no_destination"}
