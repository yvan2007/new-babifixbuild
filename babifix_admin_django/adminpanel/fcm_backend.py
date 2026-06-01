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


def firebase_status() -> dict:
    """Diagnostic : pourquoi les push partent ou non (sans rien envoyer)."""
    path = (
        os.getenv('FIREBASE_CREDENTIALS_JSON_PATH')
        or os.getenv('GOOGLE_APPLICATION_CREDENTIALS')
        or ''
    ).strip()
    try:
        import firebase_admin  # noqa: F401
        sdk = True
    except Exception:
        sdk = False
    return {
        'sdk_installed': sdk,
        'credentials_env_set': bool(path),
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
    if not path or not os.path.isfile(path):
        if not _warned_no_creds:
            _warned_no_creds = True
            logger.warning(
                'FCM DÉSACTIVÉ : aucun fichier de compte de service Firebase. '
                'Définissez FIREBASE_CREDENTIALS_JSON_PATH (ou GOOGLE_APPLICATION_CREDENTIALS) '
                'vers le JSON telecharge depuis Firebase Console -> Parametres -> '
                'Comptes de service -> Generer une nouvelle cle privee. '
                'Chemin actuel : %r',
                path or '(non défini)',
            )
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
        logger.info('FCM activé (Firebase initialisé depuis %s)', path)
        return True
    except Exception as e:
        logger.warning('FCM: impossible d’initialiser Firebase (%s)', e)
        return False


def send_push_to_user_ids(
    user_ids: list[int],
    title: str,
    body: str,
    data: dict[str, Any] | None = None,
) -> dict:
    """Envoie une notification à tous les appareils enregistrés pour ces utilisateurs.

    Retourne un résumé : {ready, tokens, sent, failed, reason}.
    """
    if not user_ids:
        return {'ready': False, 'tokens': 0, 'sent': 0, 'failed': 0, 'reason': 'no_user_ids'}
    if not _ensure_firebase_app():
        return {'ready': False, 'tokens': 0, 'sent': 0, 'failed': 0, 'reason': 'firebase_not_configured'}
    from firebase_admin import messaging

    from .models import DeviceToken

    tokens = list(
        DeviceToken.objects.filter(user_id__in=user_ids).values_list('token', flat=True).distinct()
    )
    if not tokens:
        logger.info('FCM: aucun appareil enregistré pour les utilisateurs %s', user_ids)
        return {'ready': True, 'tokens': 0, 'sent': 0, 'failed': 0, 'reason': 'no_tokens'}

    data = data or {}
    data['title'] = str(title)
    data['body'] = str(body)
    data_str = {k: str(v) for k, v in data.items() if v is not None}

    # Canal Android partagé avec les apps Flutter (cf. babifix_fcm.dart).
    # Uniquement data payload — pas de notification section, pour que
    # `onMessage` / `onBackgroundMessage` soient toujours déclenchés.
    android_cfg = messaging.AndroidConfig(
        priority='high',
        notification=messaging.AndroidNotification(
            channel_id='babifix_notifications',
            sound='notification_soft',
            default_sound=False,
        ),
    )
    apns_cfg = messaging.APNSConfig(
        payload=messaging.APNSPayload(
            aps=messaging.Aps(
                alert=messaging.ApsAlert(title=title, body=body),
                sound='notification_soft.mp3',
            ),
        ),
    )

    messages = [
        messaging.Message(
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
