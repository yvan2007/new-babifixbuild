import os

from django.conf import settings

from .public_api import fetch_admin_public_categories, fetch_admin_public_config


def site_globals(request):
    """Variables disponibles dans tous les templates vitrine (avec config & categories mises en cache)."""
    raw_phone = os.getenv("BABIFIX_SUPPORT_PHONE", "").strip()
    raw_wa = os.getenv("BABIFIX_WHATSAPP_NUMBER", "").strip().lstrip("+").replace(" ", "")
    whatsapp_url = (
        f"https://wa.me/{raw_wa}?text=Bonjour%20BABIFIX%2C%20j%27ai%20une%20question."
        if raw_wa
        else ""
    )
    cats_payload = fetch_admin_public_categories()
    raw_cats = cats_payload.get("categories") if isinstance(cats_payload, dict) else []
    footer_cats = [
        {
            "id": c.get("id"),
            "nom": c.get("nom", ""),
            "short_nom": (c.get("nom") or "").split("&")[0].strip(),
        }
        for c in (raw_cats or [])[:5]
        if isinstance(c, dict)
    ]
    def _safe_social_url(env_key, default_url):
        raw = os.getenv(env_key, default_url).strip()
        return raw if raw.startswith(("https://", "http://")) else default_url

    return {
        "ga_id": getattr(settings, "GA_MEASUREMENT_ID", ""),
        "support_email": os.getenv("BABIFIX_SUPPORT_EMAIL", "contact@babifix.ci").strip(),
        "support_phone": raw_phone,
        "whatsapp_url": whatsapp_url,
        "social_urls": {
            "tiktok": _safe_social_url("BABIFIX_TIKTOK_URL", "https://www.tiktok.com/@babifix.ci"),
            "facebook": _safe_social_url("BABIFIX_FACEBOOK_URL", "https://www.facebook.com/babifix.ci"),
            "instagram": _safe_social_url("BABIFIX_INSTAGRAM_URL", "https://www.instagram.com/babifix.ci"),
            "linkedin": _safe_social_url("BABIFIX_LINKEDIN_URL", "https://www.linkedin.com/company/babifix"),
        },
        "platform_cfg": fetch_admin_public_config(),
        "footer_categories": footer_cats,
    }
