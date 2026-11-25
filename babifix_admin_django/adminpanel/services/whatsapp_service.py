"""Connecteur WhatsApp BABIFIX : liens wa.me gratuits + adaptateur Meta Cloud API optionnel.

Deux niveaux :
  1. Liens profonds `wa.me` (100 % gratuit, zero configuration, utilisable partout)
  2. Meta WhatsApp Cloud API v21.0 (inactif tant que WHATSAPP_CLOUD_TOKEN et
     WHATSAPP_PHONE_NUMBER_ID ne sont pas renseignes dans .env).
"""

from __future__ import annotations

import logging
import os
import re
from urllib.parse import quote

import requests
from django.conf import settings

logger = logging.getLogger(__name__)


def normalize_ci_phone(phone: str) -> str:
    """Normalise un numero ivoirien en chiffres internationaux sans '+' (ex: 2250700000000)."""
    digits = re.sub(r"\D+", "", str(phone or ""))
    if not digits:
        return ""
    if digits.startswith("00"):
        digits = digits[2:]
    if len(digits) == 10 and digits.startswith("0"):
        return f"225{digits}"
    if len(digits) == 8:
        return f"22507{digits}"
    return digits


def build_whatsapp_deeplink(phone: str, message: str = "") -> str:
    """Genere un lien WhatsApp 100 % gratuit (wa.me) avec message pre-rempli."""
    norm = normalize_ci_phone(phone)
    if not norm:
        return ""
    msg = (message or "").strip()
    if msg:
        return f"https://wa.me/{norm}?text={quote(msg)}"
    return f"https://wa.me/{norm}"


def whatsapp_cloud_configured() -> bool:
    token = (os.getenv("WHATSAPP_CLOUD_TOKEN") or getattr(settings, "WHATSAPP_CLOUD_TOKEN", "")).strip()
    phone_id = (
        os.getenv("WHATSAPP_PHONE_NUMBER_ID")
        or getattr(settings, "WHATSAPP_PHONE_NUMBER_ID", "")
    ).strip()
    return bool(token and phone_id)


def send_whatsapp_utility_template(
    phone: str,
    template_name: str,
    body_params: list[str] | None = None,
    *,
    lang_code: str = "fr",
) -> dict:
    """Envoie un template utilitaire via Meta WhatsApp Cloud API si configure.

    Sans cles dans .env : no-op silencieux retournant configured=False.
    """
    norm = normalize_ci_phone(phone)
    if not norm:
        return {"ok": False, "configured": whatsapp_cloud_configured(), "reason": "phone_missing"}
    if not whatsapp_cloud_configured():
        return {"ok": False, "configured": False, "reason": "whatsapp_cloud_not_configured"}

    token = (os.getenv("WHATSAPP_CLOUD_TOKEN") or getattr(settings, "WHATSAPP_CLOUD_TOKEN", "")).strip()
    phone_id = (
        os.getenv("WHATSAPP_PHONE_NUMBER_ID")
        or getattr(settings, "WHATSAPP_PHONE_NUMBER_ID", "")
    ).strip()
    url = f"https://graph.facebook.com/v21.0/{phone_id}/messages"
    components = []
    if body_params:
        components.append(
            {
                "type": "body",
                "parameters": [{"type": "text", "text": str(p)[:240]} for p in body_params],
            }
        )
    payload = {
        "messaging_product": "whatsapp",
        "to": norm,
        "type": "template",
        "template": {
            "name": template_name,
            "language": {"code": lang_code},
            "components": components,
        },
    }
    try:
        resp = requests.post(
            url,
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
            json=payload,
            timeout=10,
        )
        if 200 <= resp.status_code < 300:
            return {"ok": True, "configured": True, "status_code": resp.status_code}
        logger.warning("WhatsApp Cloud API HTTP %s: %s", resp.status_code, resp.text[:200])
        return {"ok": False, "configured": True, "status_code": resp.status_code}
    except Exception as exc:
        logger.warning("WhatsApp Cloud API error: %s", exc)
        return {"ok": False, "configured": True, "reason": str(exc)[:200]}
