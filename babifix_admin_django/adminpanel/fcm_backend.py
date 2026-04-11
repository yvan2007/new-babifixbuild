"""
Envoi des notifications FCM via Firebase Admin SDK (HTTP v1).
Sans fichier de compte de service : aucun envoi (no-op silencieux).
"""
from __future__ import annotations

import logging
import os
from typing import Any

logger = logging.getLogger(__name__)

_app_initialized = False


def _ensure_firebase_app() -> bool:
    global _app_initialized
    if _app_initialized:
        return True
    path = (
        os.getenv('FIREBASE_CREDENTIALS_JSON_PATH')
        or os.getenv('GOOGLE_APPLICATION_CREDENTIALS')
        or ''
    ).strip()
    if not path or not os.path.isfile(path):
        return False
    try:
        import firebase_admin
        from firebase_admin import credentials

        cred = credentials.Certificate(path)
        try:
            firebase_admin.get_app()
        except ValueError:
            firebase_admin.initialize_app(cred)
        _app_initialized = True
        return True
    except Exception as e:
        logger.warning('FCM: impossible d’initialiser Firebase (%s)', e)
        return False


def send_push_to_user_ids(
    user_ids: list[int],
    title: str,
    body: str,
    data: dict[str, Any] | None = None,
) -> None:
    """Envoie une notification à tous les appareils enregistrés pour ces utilisateurs."""
    if not user_ids or not _ensure_firebase_app():
        return
    from firebase_admin import messaging

    from .models import DeviceToken

    tokens = list(
        DeviceToken.objects.filter(user_id__in=user_ids).values_list('token', flat=True).distinct()
    )
    if not tokens:
        return

    data = data or {}
    data_str = {k: str(v) for k, v in data.items() if v is not None}

    messages = [
        messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data=data_str,
            token=t,
        )
        for t in tokens
    ]
    try:
        batch = messaging.send_each(messages)
    except Exception as e:
        logger.warning('FCM send_each: %s', e)
        return

    dead: list[str] = []
    for idx, resp in enumerate(batch.responses):
        if resp.success:
            continue
        exc = resp.exception
        if exc is None:
            continue
        code = getattr(exc, 'code', '') or ''
        msg = str(exc).lower()
        if 'unregistered' in msg or 'not-registered' in msg or code == 'NOT_FOUND':
            if idx < len(tokens):
                dead.append(tokens[idx])
    if dead:
        DeviceToken.objects.filter(token__in=dead).delete()
