"""LiveKit signaling — backend authoritative (Phase D).

Le backend :
- crée la room et génère les tokens (HS256, claim `video.room`).
- pousse un FCM data-message `type=call.incoming` à l'appelé pour faire
  sonner son téléphone, même app fermée.
- track l'appel dans `Call` (statut, durée).

Aucune clé LiveKit ne devrait être dans l'app cliente : on remplace la
génération côté Flutter par un appel à `/api/calls/initiate`.

Config (env / settings) :
- LIVEKIT_URL        ex. wss://babifix-xxxxx.livekit.cloud
- LIVEKIT_API_KEY
- LIVEKIT_API_SECRET
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import time
import uuid
from typing import Optional

from django.conf import settings


def _cfg(name: str, default: str = "") -> str:
    return os.getenv(name, getattr(settings, name, default))


def livekit_url() -> str:
    return _cfg("LIVEKIT_URL", "wss://babifix-h1giwqew.livekit.cloud")


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def generate_access_token(
    identity: str,
    name: str,
    room_name: str,
    can_publish: bool = True,
    can_subscribe: bool = True,
    ttl_seconds: int = 3600,
) -> Optional[str]:
    """Génère un JWT HS256 LiveKit. Retourne None si clés non configurées."""
    api_key = _cfg("LIVEKIT_API_KEY", "APIHmepmCSoou3K")
    api_secret = _cfg(
        "LIVEKIT_API_SECRET", "Cets7RORRaNS61Ie4dyCY0rE33lyzxTBrG7NYQifs6IA"
    )
    if not api_key or not api_secret:
        return None

    now = int(time.time())
    payload = {
        "iss": api_key,
        "sub": identity,
        "nbf": now - 30,
        "exp": now + ttl_seconds,
        "name": name,
        "video": {
            "room": room_name,
            "roomJoin": True,
            "roomCreate": True,
            "canPublish": can_publish,
            "canSubscribe": can_subscribe,
            "canPublishData": True,
        },
    }
    header = {"alg": "HS256", "typ": "JWT"}
    h = _b64url(json.dumps(header, separators=(",", ":")).encode("utf-8"))
    p = _b64url(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    signing_input = f"{h}.{p}".encode("ascii")
    sig = hmac.new(
        api_secret.encode("utf-8"),
        signing_input,
        hashlib.sha256,
    ).digest()
    return f"{h}.{p}.{_b64url(sig)}"


def new_room_name(prefix: str = "babifix") -> str:
    """Identifiant unique de room pour un nouvel appel."""
    return f"{prefix}_{uuid.uuid4().hex[:12]}"
