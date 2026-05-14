"""Endpoints de santé / diagnostic config BABIFIX.

GET /api/admin/health/config

Retourne un JSON indiquant pour chaque intégration si elle est :
- "ok" (présente, format plausible)
- "missing" (manquante)
- "placeholder" (valeur par défaut/dev, non utilisable en prod)

Les valeurs sensibles ne sont JAMAIS exposées : on ne retourne que des
empreintes courtes (prefix + suffix + longueur).
"""

from __future__ import annotations

import os

from django.conf import settings
from django.http import JsonResponse
from django.views.decorators.http import require_GET

from .auth import require_api_auth


def _fingerprint(value: str | None, *, sensitive: bool = True) -> dict:
    if value is None or value == "":
        return {"status": "missing"}
    lower = value.lower()
    placeholders = ("your-", "replace", "changez", "change_for_prod",
                    "change-for-prod", "votre_", "votre-")
    if any(p in lower for p in placeholders):
        return {"status": "placeholder", "hint": "valeur par défaut non utilisable"}
    if sensitive and len(value) > 12:
        return {
            "status": "ok",
            "length": len(value),
            "prefix": value[:4],
            "suffix": value[-4:],
        }
    return {"status": "ok", "value": value}


@require_GET
@require_api_auth(["admin"])
def api_admin_health_config(request):
    env = os.environ

    geniuspay = {
        "public_key": _fingerprint(env.get("GENIUSPAY_PUBLIC_KEY")),
        "secret_key": _fingerprint(env.get("GENIUSPAY_SECRET_KEY")),
        "api_url": _fingerprint(env.get("GENIUSPAY_API_URL"), sensitive=False),
        "webhook_url": _fingerprint(env.get("GENIUSPAY_WEBHOOK_URL"), sensitive=False),
    }
    # Détecte le mode (live vs sandbox) sans révéler la clé
    pk = env.get("GENIUSPAY_PUBLIC_KEY", "")
    if pk.startswith("pk_live_"):
        geniuspay["mode"] = "LIVE"
    elif pk.startswith("pk_test_"):
        geniuspay["mode"] = "TEST"
    else:
        geniuspay["mode"] = "unknown"

    livekit = {
        "url": _fingerprint(env.get("LIVEKIT_URL"), sensitive=False),
        "api_key": _fingerprint(env.get("LIVEKIT_API_KEY")),
        "api_secret": _fingerprint(env.get("LIVEKIT_API_SECRET")),
    }

    fb_path = env.get("GOOGLE_APPLICATION_CREDENTIALS") or env.get(
        "FIREBASE_CREDENTIALS_JSON_PATH"
    )
    firebase = {
        "project_id": _fingerprint(env.get("FIREBASE_PROJECT_ID"), sensitive=False),
        "messaging_sender_id": _fingerprint(
            env.get("FIREBASE_MESSAGING_SENDER_ID"), sensitive=False
        ),
        "credentials_file": (
            {"status": "ok", "path": fb_path, "size": os.path.getsize(fb_path)}
            if fb_path and os.path.exists(fb_path)
            else {"status": "missing", "path": fb_path or ""}
        ),
    }

    email = {
        "host": _fingerprint(env.get("EMAIL_HOST"), sensitive=False),
        "user": _fingerprint(env.get("EMAIL_HOST_USER"), sensitive=False),
        "password": _fingerprint(env.get("EMAIL_HOST_PASSWORD")),
        "default_from": _fingerprint(env.get("DEFAULT_FROM_EMAIL"), sensitive=False),
    }

    db = {
        "engine": settings.DATABASES["default"].get("ENGINE", ""),
        "name": settings.DATABASES["default"].get("NAME", ""),
        "host": settings.DATABASES["default"].get("HOST", ""),
    }

    security = {
        "django_secret_ok": _fingerprint(env.get("DJANGO_SECRET_KEY"))["status"]
        == "ok",
        "jwt_secret_ok": _fingerprint(env.get("JWT_SECRET_KEY"))["status"] == "ok",
        "debug": settings.DEBUG,
        "allowed_hosts": settings.ALLOWED_HOSTS,
    }

    # Verdict global : prêt pour la prod ?
    blockers = []
    if security["debug"]:
        blockers.append("DEBUG=True")
    if not security["django_secret_ok"]:
        blockers.append("DJANGO_SECRET_KEY placeholder")
    for k, v in geniuspay.items():
        if isinstance(v, dict) and v.get("status") in ("missing", "placeholder"):
            blockers.append(f"geniuspay.{k}")
    for k, v in livekit.items():
        if v.get("status") in ("missing", "placeholder"):
            blockers.append(f"livekit.{k}")
    if firebase["credentials_file"]["status"] != "ok":
        blockers.append("firebase.credentials_file")

    return JsonResponse({
        "production_ready": len(blockers) == 0,
        "blockers": blockers,
        "geniuspay": geniuspay,
        "livekit": livekit,
        "firebase": firebase,
        "email": email,
        "database": db,
        "security": security,
    })
