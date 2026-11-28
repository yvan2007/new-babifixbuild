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


_warned_no_creds = False


def _load_firebase_json_env() -> dict[str, Any] | None:
    """Charge FIREBASE_CREDENTIALS_JSON (JSON brut ou base64) si fourni en env Render."""
    import base64
    import json

    raw = (os.getenv('FIREBASE_CREDENTIALS_JSON') or '').strip()
    if not raw:
        return None
    if not raw.startswith('{'):
        try:
            raw = base64.b64decode(raw).decode('utf-8')
        except Exception:
            return None
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, dict) and parsed.get('private_key'):
            return parsed
    except Exception:
        return None
    return None


def firebase_status() -> dict:
    """Diagnostic : pourquoi les push partent ou non (sans rien envoyer)."""
    path = (
        os.getenv('FIREBASE_CREDENTIALS_JSON_PATH')
        or os.getenv('GOOGLE_APPLICATION_CREDENTIALS')
        or ''
    ).strip()
    json_env_ok = _load_firebase_json_env() is not None
    try:
        import firebase_admin  # noqa: F401
        sdk = True
    except Exception:
        sdk = False
    return {
        'sdk_installed': sdk,
        'credentials_env_set': bool(path) or json_env_ok,
        'credentials_json_env_set': json_env_ok,
        'credentials_file_exists': bool(path) and os.path.isfile(path),
        'credentials_path': path,
        'ready': _ensure_firebase_app(),
    }


def _ensure_firebase_app() -> bool:
    global _app_initialized, _warned_no_creds
    if _app_initialized:
        return True
    path = (
        os.getenv('FIREBASE_CREDENTIALS_JSON_PATH')
        or os.getenv('GOOGLE_APPLICATION_CREDENTIALS')
        or ''
    ).strip()
    json_dict = None if (path and os.path.isfile(path)) else _load_firebase_json_env()
    if not (path and os.path.isfile(path)) and json_dict is None:
        if not _warned_no_creds:
            _warned_no_creds = True
            logger.warning(
                'FCM DÉSACTIVÉ : aucun compte de service Firebase. '
                'Définissez FIREBASE_CREDENTIALS_JSON_PATH ou FIREBASE_CREDENTIALS_JSON '
                'depuis Firebase Console -> Parametres -> Comptes de service. '
                'Chemin actuel : %r',
                path or '(non défini)',
            )
        return False
    try:
        import firebase_admin
        from firebase_admin import credentials

        cred = credentials.Certificate(json_dict if json_dict is not None else path)
        try:
            firebase_admin.get_app()
        except ValueError:
            firebase_admin.initialize_app(cred)
        _app_initialized = True
        logger.info('FCM activé (Firebase initialisé)')
        return True
    except Exception as e:
        logger.warning('FCM: impossible d’initialiser Firebase (%s)', e)
        return False


def send_push_to_user_ids(
    user_ids: list[int],
    title: str,
    body: str,
    data: dict[str, Any] | None = None,
    app: str | None = None,
) -> dict:
    """Envoie une notification aux appareils enregistrés pour ces utilisateurs.

    Si ``app`` est fourni ('client' ou 'pro'), on ne cible QUE les jetons de
    cette application : pour qu'un push « client » n'atterrisse pas sur l'app
    prestataire (et inversement).

    Retourne un résumé : {ready, tokens, sent, failed, reason}.
    """
    if not user_ids:
        return {'ready': False, 'tokens': 0, 'sent': 0, 'failed': 0, 'reason': 'no_user_ids'}
    if not _ensure_firebase_app():
        return {'ready': False, 'tokens': 0, 'sent': 0, 'failed': 0, 'reason': 'firebase_not_configured'}
    from firebase_admin import messaging

    from .models import DeviceToken

    qs = DeviceToken.objects.filter(user_id__in=user_ids)
    if app in {'client', 'pro'}:
        qs = qs.filter(app=app)
    tokens = list(qs.values_list('token', flat=True).distinct())
    if not tokens:
        logger.info('FCM: aucun appareil enregistré pour les utilisateurs %s', user_ids)
        return {'ready': True, 'tokens': 0, 'sent': 0, 'failed': 0, 'reason': 'no_tokens'}

    data = data or {}
    data['title'] = str(title)
    data['body'] = str(body)
    data_str = {k: str(v) for k, v in data.items() if v is not None}

    from datetime import timedelta

    channel_id = str(data_str.get('android_channel_id') or 'babifix_notifications').strip()
    is_call = data_str.get('type') == 'call.incoming'
    android_kwargs: dict[str, Any] = {
        'priority': 'high',
        'notification': messaging.AndroidNotification(
            channel_id=channel_id,
            sound='notification_soft',
            default_sound=False,
        ),
    }
    if is_call:
        android_kwargs['ttl'] = timedelta(seconds=60)
    android_cfg = messaging.AndroidConfig(**android_kwargs)
    apns_cfg = messaging.APNSConfig(
        headers={
            'apns-push-type': 'alert',
            'apns-priority': '10',
        },
        payload=messaging.APNSPayload(
            aps=messaging.Aps(
                alert=messaging.ApsAlert(title=str(title), body=str(body)),
                sound='notification_soft.mp3',
                badge=1,
                mutable_content=True,
                content_available=True,
            ),
        ),
    )

    messages = [
        messaging.Message(
            notification=messaging.Notification(
                title=str(title),
                body=str(body),
            ),
            android=android_cfg,
            apns=apns_cfg,
            data=data_str,
            token=t,
        )
        for t in tokens
    ]
    try:
        batch = messaging.send_each(messages)
    except Exception as e:
        logger.warning('FCM send_each: %s', e)
        return {'ready': True, 'tokens': len(tokens), 'sent': 0, 'failed': len(tokens), 'reason': f'send_error: {e}'}

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

    sent = batch.success_count
    failed = batch.failure_count
    logger.info('FCM: %s envoyé(s), %s échec(s) sur %s token(s)', sent, failed, len(tokens))
    return {
        'ready': True,
        'tokens': len(tokens),
        'sent': sent,
        'failed': failed,
        'dead_removed': len(dead),
        'reason': 'ok',
    }
