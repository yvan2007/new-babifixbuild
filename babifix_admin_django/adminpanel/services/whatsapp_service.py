"""
WhatsApp Business API — Notifications BABIFIX
Configurer via .env :
  WHATSAPP_API_TOKEN=...
  WHATSAPP_PHONE_NUMBER_ID=...
  WHATSAPP_API_VERSION=v19.0   (optionnel)

Utilise l'API officielle Meta Cloud API.
Si non configuré → les envois sont silencieusement ignorés (fallback FCM).
"""

import json
import logging
import os
import urllib.request
import urllib.error

logger = logging.getLogger(__name__)

_TOKEN = os.getenv("WHATSAPP_API_TOKEN", "")
_PHONE_NUMBER_ID = os.getenv("WHATSAPP_PHONE_NUMBER_ID", "")
_API_VERSION = os.getenv("WHATSAPP_API_VERSION", "v19.0")
_BASE_URL = f"https://graph.facebook.com/{_API_VERSION}/{_PHONE_NUMBER_ID}/messages"


def _is_configured() -> bool:
    return bool(_TOKEN and _PHONE_NUMBER_ID)


def _send_whatsapp(to_phone: str, payload: dict) -> bool:
    """Envoi bas niveau via Meta Cloud API."""
    if not _is_configured():
        logger.debug("WhatsApp non configuré — message ignoré vers %s", to_phone)
        return False

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        _BASE_URL,
        data=data,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {_TOKEN}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            resp_data = json.loads(resp.read().decode("utf-8"))
            logger.info("WhatsApp envoyé à %s: %s", to_phone, resp_data.get("messages", [{}])[0].get("id", ""))
            return True
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        logger.warning("WhatsApp HTTP %s vers %s: %s", e.code, to_phone, body)
        return False
    except Exception as exc:
        logger.warning("WhatsApp erreur vers %s: %s", to_phone, exc)
        return False


def send_text(to_phone: str, message: str) -> bool:
    """Envoie un message texte simple."""
    # Normaliser le numéro (supprimer + et espaces)
    phone = to_phone.replace("+", "").replace(" ", "").replace("-", "")
    if not phone.startswith("225"):
        phone = "225" + phone.lstrip("0")

    payload = {
        "messaging_product": "whatsapp",
        "to": phone,
        "type": "text",
        "text": {"body": message},
    }
    return _send_whatsapp(phone, payload)


def send_reservation_confirmation(to_phone: str, nom_client: str, reference: str, prestataire: str) -> bool:
    """Template : confirmation de réservation."""
    msg = (
        f"✅ *BABIFIX* — Réservation confirmée !\n\n"
        f"Bonjour {nom_client},\n"
        f"Votre demande *{reference}* a été envoyée à {prestataire}.\n"
        f"Vous serez notifié dès qu'un devis est disponible."
    )
    return send_text(to_phone, msg)


def send_devis_available(to_phone: str, nom_client: str, reference: str, montant: float, prestataire: str) -> bool:
    """Template : nouveau devis disponible."""
    msg = (
        f"📋 *BABIFIX* — Devis disponible !\n\n"
        f"Bonjour {nom_client},\n"
        f"{prestataire} vous a envoyé un devis de *{montant:,.0f} FCFA*\n"
        f"pour la demande {reference}.\n\n"
        f"Ouvrez l'app BABIFIX pour consulter et accepter."
    )
    return send_text(to_phone, msg)


def send_payment_received(to_phone: str, nom_prestataire: str, reference: str, montant_net: float) -> bool:
    """Template : paiement reçu (prestataire)."""
    msg = (
        f"💰 *BABIFIX* — Paiement reçu !\n\n"
        f"Bonjour {nom_prestataire},\n"
        f"Le paiement pour la mission *{reference}* est confirmé.\n"
        f"*{montant_net:,.0f} FCFA* ont été crédités sur votre wallet BABIFIX.\n\n"
        f"Consultez votre wallet dans l'app pour demander un retrait."
    )
    return send_text(to_phone, msg)


def send_withdrawal_done(to_phone: str, nom_prestataire: str, montant: float, operator: str) -> bool:
    """Template : retrait effectué."""
    msg = (
        f"🏦 *BABIFIX* — Retrait effectué !\n\n"
        f"Bonjour {nom_prestataire},\n"
        f"Votre retrait de *{montant:,.0f} FCFA* via {operator.upper()} "
        f"a été traité avec succès."
    )
    return send_text(to_phone, msg)


def send_referral_bonus(to_phone: str, nom: str, bonus: int, code: str) -> bool:
    """Template : bonus parrainage."""
    msg = (
        f"🎁 *BABIFIX* — Bonus parrainage !\n\n"
        f"Bonjour {nom},\n"
        f"Votre filleul a rejoint BABIFIX avec votre code *{code}*.\n"
        f"*{bonus:,} FCFA* ont été crédités sur votre compte !"
    )
    return send_text(to_phone, msg)


def send_urgent_request(to_phone: str, nom_prestataire: str, reference: str, adresse: str) -> bool:
    """Template : nouvelle demande urgente (prestataire)."""
    msg = (
        f"🚨 *BABIFIX URGENT* — Nouvelle demande !\n\n"
        f"Bonjour {nom_prestataire},\n"
        f"Une demande *urgente* ({reference}) vous attend.\n"
        f"📍 {adresse}\n\n"
        f"Ouvrez l'app BABIFIX immédiatement pour accepter."
    )
    return send_text(to_phone, msg)


def notify_user_if_opted_in(user, message: str, template_fn=None, **kwargs) -> bool:
    """
    Envoie un WhatsApp à l'utilisateur seulement si whatsapp_opt_in=True.
    Utilise le numéro phone_e164 du profil.
    """
    try:
        from adminpanel.models import UserProfile
        profile = UserProfile.objects.get(user=user)
        if not profile.whatsapp_opt_in:
            return False
        phone = profile.phone_e164 or ""
        if not phone:
            return False
        if template_fn:
            return template_fn(phone, **kwargs)
        return send_text(phone, message)
    except Exception as exc:
        logger.warning("WhatsApp opt-in check failed: %s", exc)
        return False
