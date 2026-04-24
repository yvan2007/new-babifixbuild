"""
Rate limiting simple basé sur le cache Django.
Utilisé sur les endpoints sensibles (login, register, CinetPay initiate).
"""
import hashlib
import json

from django.core.cache import cache
from django.http import JsonResponse


def _get_client_ip(request) -> str:
    x_forwarded = request.META.get('HTTP_X_FORWARDED_FOR', '')
    if x_forwarded:
        return x_forwarded.split(',')[0].strip()
    return request.META.get('REMOTE_ADDR', '127.0.0.1')


def _extract_subject_identifier(request) -> str:
    try:
        raw_body = request.body.decode('utf-8') if request.body else ''
        payload = json.loads(raw_body or '{}')
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError):
        return ''

    for key in ('username', 'email', 'phone_e164'):
        value = str(payload.get(key, '') or '').strip().lower()
        if value:
            return value
    return ''


def check_rate_limit(
    request,
    key_prefix: str,
    max_requests: int = 5,
    window: int = 60,
    subject_identifier: str = '',
) -> bool:
    """
    Retourne True si la requête doit être bloquée (limite dépassée).
    Utilise le cache Django — compatible Redis et LocMemCache.
    """
    ip = _get_client_ip(request)
    subject = (subject_identifier or _extract_subject_identifier(request)).strip()
    throttle_scope = f'{ip}:{subject}' if subject else ip
    cache_key = f'rl:{key_prefix}:{hashlib.md5(throttle_scope.encode()).hexdigest()}'
    current = cache.get(cache_key, 0)
    if current >= max_requests:
        return True
    if current == 0:
        cache.set(cache_key, 1, timeout=window)
    else:
        cache.incr(cache_key)
    return False


def rate_limited_response() -> JsonResponse:
    return JsonResponse(
        {
            'error': 'too_many_requests',
            'message': 'Trop de tentatives. Veuillez patienter quelques secondes.',
        },
        status=429,
    )
