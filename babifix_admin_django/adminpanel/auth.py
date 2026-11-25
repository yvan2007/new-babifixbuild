import logging
from functools import wraps
import time

from django.core import signing
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt


logger = logging.getLogger(__name__)

TOKEN_SALT = "babifix-api-token"
ACCESS_TOKEN_MAX_AGE_SECONDS = 7 * 24 * 3600  # 7 jours (session dev)
REFRESH_TOKEN_MAX_AGE_SECONDS = (
    30 * 24 * 3600
)  # 30 jours - refresh token

# Flag pour utiliser le nouveau systeme JWT (plus securise)
USE_JWT = True  # ✅ Migration vers PyJWT activee

# ✅ S2: Hasher reset tokens avec PasswordResetTokenGenerator
from django.contrib.auth.tokens import PasswordResetTokenGenerator
from six import text_type

class AppPasswordResetTokenGenerator(PasswordResetTokenGenerator):
    """Generator securise pour les tokens de reset mot de passe."""
    pass

password_token_generator = AppPasswordResetTokenGenerator()


def create_token(user_id, role):
    token_data = {
        "uid": user_id,
        "role": role,
        "iat": int(time.time()),
        "exp": int(time.time()) + ACCESS_TOKEN_MAX_AGE_SECONDS,
    }
    return signing.dumps(token_data, salt=TOKEN_SALT)


def verify_token(token):
    if not token or not isinstance(token, str):
        return None
    token = token.strip()

    # 1. Verification JWT si le jeton comporte des points '.'
    if token.count(".") >= 2:
        try:
            from .jwt_auth import verify_access_token
            p = verify_access_token(token)
            if p:
                if "uid" not in p and "user_id" in p:
                    p["uid"] = p["user_id"]
                return p
        except Exception as e:
            logger.debug("JWT verify failed: %s", e)

    # 2. Verification Django signing standard
    try:
        payload = signing.loads(
            token, salt=TOKEN_SALT, max_age=ACCESS_TOKEN_MAX_AGE_SECONDS
        )
        if "exp" in payload and payload["exp"] < int(time.time()):
            return None
        return payload
    except signing.BadSignature as e:
        logger.debug("Token verification failed: %s", e)
    except signing.SignatureExpired:
        logger.debug("Token has expired")
    except Exception as e:
        logger.debug("Token verification error: %s", e)

    # 3. Repli ultime JWT
    try:
        from .jwt_auth import verify_access_token
        p = verify_access_token(token)
        if p:
            if "uid" not in p and "user_id" in p:
                p["uid"] = p["user_id"]
            return p
    except Exception:
        pass
    return None


def create_refresh_token(user_id, role):
    """Create a refresh token with 7 days expiration."""
    refresh_data = {
        "uid": user_id,
        "role": role,
        "iat": int(time.time()),
        "exp": int(time.time()) + REFRESH_TOKEN_MAX_AGE_SECONDS,
        "type": "refresh",
    }
    return signing.dumps(refresh_data, salt=f"{TOKEN_SALT}-refresh")


def verify_refresh_token(token):
    """Verify refresh token and return payload if valid."""
    if not token or not isinstance(token, str):
        return None
    token = token.strip()

    # 1. Verification JWT refresh
    if token.count(".") >= 2:
        try:
            from .jwt_auth import verify_refresh_token as _jwt_verify_refresh
            p = _jwt_verify_refresh(token)
            if p:
                if "uid" not in p and "user_id" in p:
                    p["uid"] = p["user_id"]
                return p
        except Exception:
            pass

    # 2. Verification Django signing refresh
    try:
        payload = signing.loads(
            token, salt=f"{TOKEN_SALT}-refresh", max_age=REFRESH_TOKEN_MAX_AGE_SECONDS
        )
        if payload.get("type") != "refresh":
            return None
        if payload["exp"] < int(time.time()):
            return None
        return payload
    except Exception:
        return None


def _is_user_active_and_role_ok(uid, token_role: str | None) -> bool:
    """Vérifie en base que le compte existe, est actif et non désactivé."""
    try:
        from django.contrib.auth import get_user_model
        from .models import UserProfile

        uid_int = int(uid)
        User = get_user_model()
        user = User.objects.filter(pk=uid_int).only("id", "is_active", "is_staff", "is_superuser").first()
        if not user or not user.is_active:
            return False
        prof = UserProfile.objects.filter(user_id=uid_int).only("role", "active").first()
        if prof is not None and not prof.active:
            return False
        # Empêcher un token obsolète de conserver des droits admin si le rôle a été retiré
        if token_role == "admin":
            is_admin_now = bool(user.is_staff or user.is_superuser or (prof and prof.role in ("admin", "super_admin")))
            if not is_admin_now:
                return False
        return True
    except (TypeError, ValueError):
        return False


def enforce_session_csrf(request) -> JsonResponse | None:
    """Applique la validation CSRF aux appels cookie-session (ignorée si auth Bearer JWT)."""
    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        return None
    if request.method in ("GET", "HEAD", "OPTIONS", "TRACE"):
        return None
    from django.middleware.csrf import CsrfViewMiddleware

    reason = CsrfViewMiddleware(lambda r: None).process_view(request, None, (), {})
    if reason is not None:
        return reason
    return None


def require_api_auth(roles=None):
    allowed = set(roles or [])

    def decorator(view_func):
        @csrf_exempt
        @wraps(view_func)
        def wrapper(request, *args, **kwargs):
            auth_header = request.headers.get("Authorization", "")
            if not auth_header.startswith("Bearer "):
                return JsonResponse({"error": "missing_token"}, status=401)
            token = auth_header.split(" ", 1)[1].strip()
            payload = verify_token(token)
            if not payload:
                return JsonResponse(
                    {"error": "invalid_token", "code": "token_expired"}, status=401
                )
            role = payload.get("role")
            if allowed and role not in allowed:
                return JsonResponse({"error": "forbidden_role"}, status=403)
            raw_uid = payload.get("uid") or payload.get("user_id") or payload.get("sub")
            try:
                uid_val = int(raw_uid) if raw_uid is not None else None
            except (ValueError, TypeError):
                return JsonResponse({"error": "invalid_token"}, status=401)
            if not _is_user_active_and_role_ok(uid_val, role):
                return JsonResponse({"error": "account_disabled"}, status=403)
            request.api_user_id = uid_val
            request.api_role = role
            return view_func(request, *args, **kwargs)

        return wrapper

    return decorator


def require_api_auth_or_refresh(roles=None):
    """Decorator that accepts both access tokens and refresh tokens."""
    allowed = set(roles or [])

    def decorator(view_func):
        @csrf_exempt
        @wraps(view_func)
        def wrapper(request, *args, **kwargs):
            auth_header = request.headers.get("Authorization", "")
            if not auth_header.startswith("Bearer "):
                return JsonResponse({"error": "missing_token"}, status=401)
            token = auth_header.split(" ", 1)[1].strip()

            payload = verify_token(token)
            token_type = "access"
            if not payload:
                payload = verify_refresh_token(token)
                token_type = "refresh"
            if not payload:
                return JsonResponse({"error": "invalid_token"}, status=401)

            role = payload.get("role")
            if allowed and role not in allowed:
                return JsonResponse({"error": "forbidden_role"}, status=403)
            raw_uid = payload.get("uid") or payload.get("user_id") or payload.get("sub")
            try:
                uid_val = int(raw_uid) if raw_uid is not None else None
            except (ValueError, TypeError):
                return JsonResponse({"error": "invalid_token"}, status=401)
            if not _is_user_active_and_role_ok(uid_val, role):
                return JsonResponse({"error": "account_disabled"}, status=403)
            request.api_user_id = uid_val
            request.api_role = role
            request.token_type = token_type
            return view_func(request, *args, **kwargs)

        return wrapper

    return decorator


def require_api_auth_or_refresh(roles=None):
    """Decorator that accepts both access tokens and refresh tokens."""
    allowed = set(roles or [])

    def decorator(view_func):
        @wraps(view_func)
        def wrapper(request, *args, **kwargs):
            auth_header = request.headers.get("Authorization", "")
            if not auth_header.startswith("Bearer "):
                return JsonResponse({"error": "missing_token"}, status=401)
            token = auth_header.split(" ", 1)[1].strip()

            # Try access token first
            payload = verify_token(token)
            if payload:
                role = payload.get("role")
                if allowed and role not in allowed:
                    return JsonResponse({"error": "forbidden_role"}, status=403)
                request.api_user_id = payload.get("uid") or payload.get("user_id")
                request.api_role = role
                request.token_type = "access"
                return view_func(request, *args, **kwargs)

            # Try refresh token
            payload = verify_refresh_token(token)
            if payload:
                role = payload.get("role")
                if allowed and role not in allowed:
                    return JsonResponse({"error": "forbidden_role"}, status=403)
                request.api_user_id = payload.get("uid") or payload.get("user_id")
                request.api_role = role
                request.token_type = "refresh"
                return view_func(request, *args, **kwargs)

            return JsonResponse({"error": "invalid_token"}, status=401)

        return wrapper

    return decorator
