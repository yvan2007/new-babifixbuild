# JWT Authentication — BABIFIX
"""
Systeme d'authentification base sur PyJWT avec RS256.
Securise, scalable, avec refresh token rotation.

Usage:
    from adminpanel.jwt_auth import create_access_token, verify_access_token, create_refresh_token
    
    # Creation de tokens
    access_token = create_access_token(user_id, role)
    refresh_token = create_refresh_token(user_id, role)
    
    # Verification
    payload = verify_access_token(access_token)
    
    # Refresh
    new_access = refresh_access_token(refresh_token)
"""
import logging
import os
import time
from datetime import datetime, timedelta
from typing import Optional

import jwt
from django.conf import settings

logger = logging.getLogger(__name__)

# Configuration depuis settings ou variables d'environnement
JWT_SECRET_KEY = getattr(
    settings, "JWT_SECRET_KEY", os.environ.get("JWT_SECRET_KEY", "change-me-in-production")
)
JWT_PUBLIC_KEY = getattr(
    settings, "JWT_PUBLIC_KEY", os.environ.get("JWT_PUBLIC_KEY", "")
)
JWT_ALGORITHM = "HS256"  # HS256 pour simple, RS256 pour production avec cle publique
ACCESS_TOKEN_EXPIRE_MINUTES = 15
REFRESH_TOKEN_EXPIRE_DAYS = 7
TOKEN_ISSUER = "babifix-api"
TOKEN_AUDIENCE = "babifix-client"

# Blacklist for revoke tokens (use Redis in production)
_token_blacklist = set()


def _load_private_key():
    """Load private key from settings or environment."""
    key = getattr(settings, "JWT_PRIVATE_KEY", None)
    if not key:
        key_path = os.environ.get("JWT_PRIVATE_KEY_PATH")
        if key_path and os.path.exists(key_path):
            with open(key_path, "r") as f:
                key = f.read()
    return key


def _load_public_key():
    """Load public key from settings or environment."""
    key = getattr(settings, "JWT_PUBLIC_KEY", None)
    if not key:
        key_path = os.environ.get("JWT_PUBLIC_KEY_PATH")
        if key_path and os.path.exists(key_path):
            with open(key_path, "r") as f:
                key = f.read()
    return key


def create_access_token(user_id: int, role: str, additional_claims: Optional[dict] = None) -> str:
    """
    Cree un access token JWT.
    
    Args:
        user_id: ID de l'utilisateur
        role: Role (client, prestataire, admin)
        additional_claims: Claims supplementaires optionnels
        
    Returns:
        Token JWT encode
    """
    now = datetime.utcnow()
    exp = now + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    
    payload = {
        "sub": str(user_id),
        "role": role,
        "iat": int(now.timestamp()),
        "exp": int(exp.timestamp()),
        "iss": TOKEN_ISSUER,
        "aud": TOKEN_AUDIENCE,
        "type": "access",
        "jti": f"{user_id}_{int(now.timestamp())}",  # Unique token ID
    }
    
    if additional_claims:
        payload.update(additional_claims)
    
    private_key = _load_private_key()
    if private_key:
        return jwt.encode(payload, private_key, algorithm="RS256")
    else:
        return jwt.encode(payload, JWT_SECRET_KEY, algorithm=JWT_ALGORITHM)


def create_refresh_token(user_id: int, role: str) -> str:
    """
    Cree un refresh token JWT.
    
    Args:
        user_id: ID de l'utilisateur
        role: Role
        
    Returns:
        Refresh token JWT
    """
    now = datetime.utcnow()
    exp = now + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    
    payload = {
        "sub": str(user_id),
        "role": role,
        "iat": int(now.timestamp()),
        "exp": int(exp.timestamp()),
        "iss": TOKEN_ISSUER,
        "aud": TOKEN_AUDIENCE,
        "type": "refresh",
        "jti": f"refresh_{user_id}_{int(now.timestamp())}",
    }
    
    private_key = _load_private_key()
    if private_key:
        return jwt.encode(payload, private_key, algorithm="RS256")
    else:
        return jwt.encode(payload, JWT_SECRET_KEY, algorithm=JWT_ALGORITHM)


def verify_access_token(token: str) -> Optional[dict]:
    """
    Verifie un access token.
    
    Args:
        token: JWT a verifier
        
    Returns:
        Payload decode ou None si invalide
    """
    try:
        # Check blacklist first
        decoded = jwt.decode(token, options={"verify_signature": False})
        jti = decoded.get("jti")
        if jti in _token_blacklist:
            logger.warning(f"Token revoked: {jti}")
            return None
        
        # Verify with appropriate key
        public_key = _load_public_key()
        if public_key:
            payload = jwt.decode(token, public_key, algorithms=["RS256", "HS256"], options={
                "require": ["sub", "role", "type", "exp"],
                "verify_aud": False,
            })
        else:
            payload = jwt.decode(token, JWT_SECRET_KEY, algorithms=["HS256"], options={
                "require": ["sub", "role", "type", "exp"],
                "verify_aud": False,
            })
        
        # Verify type
        if payload.get("type") != "access":
            return None
        
        # Check expiration
        exp = payload.get("exp", 0)
        if exp < int(time.time()):
            return None
        
        return payload
        
    except jwt.ExpiredSignatureError:
        logger.debug("Token expired")
        return None
    except jwt.InvalidTokenError as e:
        logger.warning(f"Invalid token: {e}")
        return None


def verify_refresh_token(token: str) -> Optional[dict]:
    """
    Verifie un refresh token.
    
    Args:
        token: Refresh JWT a verifier
        
    Returns:
        Payload decode ou None
    """
    try:
        public_key = _load_public_key()
        if public_key:
            payload = jwt.decode(token, public_key, algorithms=["RS256", "HS256"], options={
                "require": ["sub", "role", "type", "exp"],
                "verify_aud": False,
            })
        else:
            payload = jwt.decode(token, JWT_SECRET_KEY, algorithms=["HS256"], options={
                "require": ["sub", "role", "type", "exp"],
                "verify_aud": False,
            })
        
        if payload.get("type") != "refresh":
            return None
        
        exp = payload.get("exp", 0)
        if exp < int(time.time()):
            return None
        
        return payload
        
    except jwt.InvalidTokenError:
        return None


def refresh_access_token(refresh_token: str) -> Optional[tuple[str, str]]:
    """
    Refresh un access token avec un refresh token.
    
    Args:
        refresh_token: Le refresh token valide
        
    Returns:
        Tuple (new_access_token, new_refresh_token) ou None
    """
    payload = verify_refresh_token(refresh_token)
    if not payload:
        return None
    
    user_id = payload.get("sub")
    role = payload.get("role")
    
    if not user_id or not role:
        return None
    
    # Revoke old refresh token
    jti = payload.get("jti")
    if jti:
        _token_blacklist.add(jti)
    
    # Create new tokens
    new_access = create_access_token(int(user_id), role)
    new_refresh = create_refresh_token(int(user_id), role)
    
    return new_access, new_refresh


def revoke_token(token: str) -> bool:
    """
    Revoque un token (l'ajoute a la blacklist).
    
    Args:
        token: Token a revoker
        
    Returns:
        True si revolue
    """
    try:
        decoded = jwt.decode(token, options={"verify_signature": False})
        jti = decoded.get("jti")
        if jti:
            _token_blacklist.add(jti)
            logger.info(f"Token revoked: {jti}")
            return True
    except jwt.InvalidTokenError:
        pass
    return False


def is_token_revoked(token: str) -> bool:
    """Check if a token is revoked."""
    try:
        decoded = jwt.decode(token, options={"verify_signature": False})
        jti = decoded.get("jti")
        return jti in _token_blacklist
    except jwt.InvalidTokenError:
        return True


def require_jwt_auth(roles: Optional[list] = None):
    """
    Decorator for JWT authentication.
    
    Usage:
        @require_jwt_auth(roles=["client", "prestataire"])
        def my_view(request):
            ...
    """
    from functools import wraps
    from django.http import JsonResponse
    from django.views.decorators.csrf import csrf_exempt
    
    allowed_roles = set(roles or [])
    
    def decorator(view_func):
        @csrf_exempt
        @wraps(view_func)
        def wrapper(request, *args, **kwargs):
            auth_header = request.headers.get("Authorization", "")
            if not auth_header.startswith("Bearer "):
                return JsonResponse({"error": "missing_token"}, status=401)
            
            token = auth_header.split(" ", 1)[1].strip()
            payload = verify_access_token(token)
            
            if not payload:
                return JsonResponse(
                    {"error": "invalid_token", "code": "token_expired_or_revoked"},
                    status=401
                )
            
            role = payload.get("role")
            if allowed_roles and role not in allowed_roles:
                return JsonResponse({"error": "forbidden_role"}, status=403)
            
            request.api_user_id = int(payload.get("sub"))
            request.api_role = role
            request.token_payload = payload
            
            return view_func(request, *args, **kwargs)
        
        return wrapper
    
    return decorator


def require_jwt_auth_or_refresh(roles: Optional[list] = None):
    """
    Decorator that accepts both access and refresh tokens.
    """
    from functools import wraps
    from django.http import JsonResponse
    
    allowed_roles = set(roles or [])
    
    def decorator(view_func):
        @wraps(view_func)
        def wrapper(request, *args, **kwargs):
            auth_header = request.headers.get("Authorization", "")
            if not auth_header.startswith("Bearer "):
                return JsonResponse({"error": "missing_token"}, status=401)
            
            token = auth_header.split(" ", 1)[1].strip()
            
            # Try access token first
            payload = verify_access_token(token)
            token_type = "access"
            
            # Try refresh token if access failed
            if not payload:
                payload = verify_refresh_token(token)
                token_type = "refresh"
            
            if not payload:
                return JsonResponse({"error": "invalid_token"}, status=401)
            
            role = payload.get("role")
            if allowed_roles and role not in allowed_roles:
                return JsonResponse({"error": "forbidden_role"}, status=403)
            
            request.api_user_id = int(payload.get("sub"))
            request.api_role = role
            request.token_type = token_type
            request.token_payload = payload
            
            return view_func(request, *args, **kwargs)
        
        return wrapper
    
    return decorator