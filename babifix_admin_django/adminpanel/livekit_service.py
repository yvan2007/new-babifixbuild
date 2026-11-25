"""LiveKit signaling : backend authoritative (Phase D).

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
    return _cfg("LIVEKIT_URL", "").strip()


def livekit_is_configured() -> bool:
    """True uniquement si URL + API key + API secret LiveKit sont definis."""
    return bool(
        livekit_url()
        and _cfg("LIVEKIT_API_KEY", "").strip()
        and _cfg("LIVEKIT_API_SECRET", "").strip()
    )


def _generate_server_admin_token(ttl_seconds: int = 120) -> Optional[str]:
    """Token HS256 avec droit roomAdmin pour fermer une room cote serveur."""
    api_key = _cfg("LIVEKIT_API_KEY", "").strip()
    api_secret = _cfg("LIVEKIT_API_SECRET", "").strip()
    if not api_key or not api_secret:
        return None
    now = int(time.time())
    header = {"alg": "HS256", "typ": "JWT"}
    payload = {
        "iss": api_key,
        "nbf": now - 10,
        "exp": now + ttl_seconds,
        "video": {"roomAdmin": True, "roomCreate": True},
    }
    h = _b64url(json.dumps(header, separators=(",", ":")).encode("utf-8"))
    p = _b64url(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    sig = hmac.new(
        api_secret.encode("utf-8"),
        f"{h}.{p}".encode("ascii"),
        hashlib.sha256,
    ).digest()
    return f"{h}.{p}.{_b64url(sig)}"


def delete_room_best_effort(room_name: str) -> bool:
    """Ferme la room LiveKit cote serveur (deconnecte immediatement tous les pairs)."""
    if not room_name or not livekit_is_configured():
        return False
    token = _generate_server_admin_token()
    if not token:
        return False
    base = livekit_url()
    if base.startswith("wss://"):
        http_base = "https://" + base[6:]
    elif base.startswith("ws://"):
        http_base = "http://" + base[5:]
    else:
        http_base = base
    endpoint = f"{http_base.rstrip('/')}/twirp/livekit.RoomService/DeleteRoom"
    try:
        import urllib.request

        req = urllib.request.Request(
            endpoint,
            data=json.dumps({"room": room_name}).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=4) as resp:
            return 200 <= resp.status < 300
    except Exception:
        return False


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
    api_key = _cfg("LIVEKIT_API_KEY", "")
    api_secret = _cfg("LIVEKIT_API_SECRET", "")
    if not api_key or not api_secret or not livekit_url():
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
