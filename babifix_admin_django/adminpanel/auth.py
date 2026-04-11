from functools import wraps
import time

from django.core import signing
from django.http import JsonResponse


TOKEN_SALT = 'babifix-api-token'
TOKEN_MAX_AGE_SECONDS = 3600  # 1 hour - tokens expire after 1 hour


def create_token(user_id, role):
    token_data = {
        'uid': user_id,
        'role': role,
        'iat': int(time.time()),
        'exp': int(time.time()) + TOKEN_MAX_AGE_SECONDS,
    }
    return signing.dumps(token_data, salt=TOKEN_SALT)


def verify_token(token):
    try:
        payload = signing.loads(token, salt=TOKEN_SALT, max_age=TOKEN_MAX_AGE_SECONDS)
        
        # Additional validation of expiration
        if 'exp' in payload:
            if payload['exp'] < int(time.time()):
                return None
        
        return payload
    except signing.BadSignature as e:
        print(f'Token verification failed: {e}')
        return None
    except signing.SignatureExpired:
        print('Token has expired')
        return None
    except Exception as e:
        print(f'Token verification error: {e}')
        return None


def create_refresh_token(user_id, role):
    """Create a refresh token with 7 days expiration."""
    refresh_data = {
        'uid': user_id,
        'role': role,
        'iat': int(time.time()),
        'exp': int(time.time()) + (7 * 24 * 3600),  # 7 days
        'type': 'refresh',
    }
    return signing.dumps(refresh_data, salt=f'{TOKEN_SALT}-refresh')


def verify_refresh_token(token):
    """Verify refresh token and return payload if valid."""
    try:
        payload = signing.loads(token, salt=f'{TOKEN_SALT}-refresh', max_age=7 * 24 * 3600)
        if payload.get('type') != 'refresh':
            return None
        if payload['exp'] < int(time.time()):
            return None
        return payload
    except Exception:
        return None


def require_api_auth(roles=None):
    allowed = set(roles or [])

    def decorator(view_func):
        @wraps(view_func)
        def wrapper(request, *args, **kwargs):
            auth_header = request.headers.get('Authorization', '')
            if not auth_header.startswith('Bearer '):
                return JsonResponse({'error': 'missing_token'}, status=401)
            token = auth_header.split(' ', 1)[1].strip()
            payload = verify_token(token)
            if not payload:
                return JsonResponse({'error': 'invalid_token', 'code': 'token_expired'}, status=401)
            role = payload.get('role')
            if allowed and role not in allowed:
                return JsonResponse({'error': 'forbidden_role'}, status=403)
            request.api_user_id = payload.get('uid') or payload.get('user_id')
            request.api_role = role
            return view_func(request, *args, **kwargs)

        return wrapper

    return decorator


def require_api_auth_or_refresh(roles=None):
    """Decorator that accepts both access tokens and refresh tokens."""
    allowed = set(roles or [])

    def decorator(view_func):
        @wraps(view_func)
        def wrapper(request, *args, **kwargs):
            auth_header = request.headers.get('Authorization', '')
            if not auth_header.startswith('Bearer '):
                return JsonResponse({'error': 'missing_token'}, status=401)
            token = auth_header.split(' ', 1)[1].strip()
            
            # Try access token first
            payload = verify_token(token)
            if payload:
                role = payload.get('role')
                if allowed and role not in allowed:
                    return JsonResponse({'error': 'forbidden_role'}, status=403)
                request.api_user_id = payload.get('uid') or payload.get('user_id')
                request.api_role = role
                request.token_type = 'access'
                return view_func(request, *args, **kwargs)
            
            # Try refresh token
            payload = verify_refresh_token(token)
            if payload:
                role = payload.get('role')
                if allowed and role not in allowed:
                    return JsonResponse({'error': 'forbidden_role'}, status=403)
                request.api_user_id = payload.get('uid') or payload.get('user_id')
                request.api_role = role
                request.token_type = 'refresh'
                return view_func(request, *args, **kwargs)
            
            return JsonResponse({'error': 'invalid_token'}, status=401)

        return wrapper

    return decorator
