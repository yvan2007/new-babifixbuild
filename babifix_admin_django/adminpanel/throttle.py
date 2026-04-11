"""
Rate limiting simple basé sur le cache Django.
Utilisé sur les endpoints sensibles (login, register, CinetPay initiate).
"""
import hashlib
from django.core.cache import cache
from django.conf import settings
from django.http import JsonResponse


def _get_client_ip(request) -> str:
    x_forwarded = request.META.get('HTTP_X_FORWARDED_FOR', '')
    if x_forwarded:
        return x_forwarded.split(',')[0].strip()
    return request.META.get('REMOTE_ADDR', '127.0.0.1')


def check_rate_limit(request, key_prefix: str, max_requests: int = 5, window: int = 60) -> bool:
    """
    Retourne True si la requête doit être bloquée (limite dépassée).
    Utilise le cache Django — compatible Redis et LocMemCache.
    """
    ip = _get_client_ip(request)
    cache_key = f'rl:{key_prefix}:{hashlib.md5(ip.encode()).hexdigest()}'
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
