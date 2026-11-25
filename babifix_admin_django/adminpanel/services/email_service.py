"""
Service centralise d'envoi d'e-mails transactionnels et de formatage FR BABIFIX.

Principes :
  - Formatage francais deterministe (sans dependance a locale OS).
  - Extraction plain-text propre (supprime <style> et <script> avant strippage).
  - Attachement automatique inline du logo officiel (`cid:babifix_logo`).
  - Journalisation des echecs SMTP dans SystemEventLog.
"""
from __future__ import annotations

import html as _html
import logging
import os
import re
import threading
from datetime import datetime
from decimal import Decimal
from email.mime.image import MIMEImage
from typing import Any

from django.conf import settings
from django.core.mail import EmailMultiAlternatives
from django.template.loader import render_to_string
from django.utils import timezone

logger = logging.getLogger("adminpanel.email")

FRENCH_MONTHS = {
    1: "janvier",
    2: "février",
    3: "mars",
    4: "avril",
    5: "mai",
    6: "juin",
    7: "juillet",
    8: "août",
    9: "septembre",
    10: "octobre",
    11: "novembre",
    12: "décembre",
}


def format_french_date(dt: datetime | None = None, *, with_time: bool = True) -> str:
    """Formate une date en francais lisible ('21 novembre 2026 a 10:05')."""
    if dt is None:
        dt = timezone.now()
    if timezone.is_aware(dt):
        dt = timezone.localtime(dt)
    mois = FRENCH_MONTHS.get(dt.month, str(dt.month))
    base = f"{dt.day} {mois} {dt.year}"
    if with_time:
        return f"{base} à {dt.strftime('%H:%M')}"
    return base


def format_fcfa(amount: Any) -> str:
    """Formate un montant numerique avec espace fine/normale pour FCFA."""
    try:
        val = int(round(float(Decimal(str(amount or 0)))))
    except Exception:
        val = 0
    return f"{val:,}".replace(",", " ")


def find_logo_path() -> str | None:
    """Localise logo_babifix.png en dev comme en prod (STATIC_ROOT)."""
    rel = os.path.join("adminpanel", "logo_babifix.png")
    candidates: list[str] = []
    static_root = getattr(settings, "STATIC_ROOT", None)
    if static_root:
        candidates.append(os.path.join(str(static_root), rel))
    base = getattr(settings, "BASE_DIR", None)
    if base:
        candidates.append(os.path.join(str(base), "static", rel))
        candidates.append(os.path.join(str(base), "adminpanel", "static", rel))
        candidates.append(os.path.join(str(base), "..", "LOGO BABIFIX.png"))
    for p in candidates:
        try:
            if p and os.path.isfile(p):
                return p
        except Exception:
            continue
    return None


def html_to_plain_text(html_content: str) -> str:
    """Convertit un HTML d'email en texte brut propre sans balises CSS/JS."""
    cleaned = re.sub(r"<style[^>]*>.*?</style>", "", html_content or "", flags=re.IGNORECASE | re.DOTALL)
    cleaned = re.sub(r"<script[^>]*>.*?</script>", "", cleaned, flags=re.IGNORECASE | re.DOTALL)
    cleaned = re.sub(r"<(br|tr|p|div|li|h[1-6])[^>]*>", "\n", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"<[^>]+>", "", cleaned)
    cleaned = _html.unescape(cleaned)
    cleaned = re.sub(r"[ \t]+", " ", cleaned)
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)
    return cleaned.strip()


def _record_email_failure(to_email: str, subject: str, err: Exception) -> None:
    logger.warning("Email non envoye (%s | %s) : %s", to_email, subject, err)
    try:
        from adminpanel.services.observability_service import record_system_event

        record_system_event(
            event_type="email.send_failed",
            category="email",
            severity="warning",
            source="email_service",
            message=f"Echec envoi email vers {to_email} ({subject[:80]})",
            payload={"to": to_email, "subject": subject[:120], "error": str(err)[:300]},
        )
    except Exception:
        pass


def send_babifix_html_email(
    *,
    to_email: str,
    subject: str,
    html_content: str | None = None,
    template_name: str | None = None,
    context: dict[str, Any] | None = None,
    attachments: list[tuple[str, bytes, str]] | None = None,
    async_send: bool = True,
    attach_logo: bool = True,
) -> bool:
    """Rend et envoie un email HTML BABIFIX propre avec logo inline CID."""
    if not to_email or "@" not in str(to_email):
        return False

    body_html = html_content
    if not body_html and template_name:
        tpl_path = template_name if template_name.startswith("emails/") else f"emails/{template_name}"
        try:
            body_html = render_to_string(tpl_path, context or {})
        except Exception as exc:
            _record_email_failure(to_email, subject, exc)
            return False

    if not body_html:
        return False

    plain_text = html_to_plain_text(body_html)
    from_email = getattr(settings, "DEFAULT_FROM_EMAIL", "BABIFIX <contact@babifix.ci>")
    _attachments = list(attachments or [])

    def _deliver() -> bool:
        try:
            msg = EmailMultiAlternatives(
                subject=subject,
                body=plain_text or subject,
                from_email=from_email,
                to=[to_email],
            )
            msg.attach_alternative(body_html, "text/html")

            if attach_logo and "cid:babifix_logo" in body_html:
                logo_path = find_logo_path()
                if logo_path:
                    try:
                        with open(logo_path, "rb") as f_img:
                            img_part = MIMEImage(f_img.read())
                            img_part.add_header("Content-ID", "<babifix_logo>")
                            img_part.add_header("Content-Disposition", "inline", filename="logo_babifix.png")
                            msg.attach(img_part)
                    except Exception:
                        pass

            for filename, content, mimetype in _attachments:
                msg.attach(filename, content, mimetype)

            msg.send(fail_silently=False)
            logger.info("Email envoye a %s : %s", to_email, subject)
            return True
        except Exception as exc:
            _record_email_failure(to_email, subject, exc)
            return False

    if async_send:
        threading.Thread(target=_deliver, daemon=True).start()
        return True
    return _deliver()
