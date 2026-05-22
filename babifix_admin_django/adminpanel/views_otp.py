"""
Vues pour la vérification téléphone via OTP Firebase.
"""
from __future__ import annotations

import json
import logging

from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from firebase_admin.auth import verify_id_token

from .auth import require_api_auth

logger = logging.getLogger(__name__)


@csrf_exempt
@require_api_auth(["client", "prestataire"])
def api_auth_verify_otp(request):
    """
    Vérifie le token Firebase obtenu après validation OTP côté Flutter.
    
    Flutter signe avec Firebase Auth, récupère un idToken,
    puis l'envoie ici. Le backend vérifie ce token et marque
    le téléphone comme vérifié.
    """
    if request.method != "POST":
        return JsonResponse({"error": "method_not_allowed"}, status=405)

    # Anti-brute-force : limiter les vérifications OTP.
    from .throttle import check_rate_limit, rate_limited_response
    if check_rate_limit(request, "verify_otp", max_requests=8, window=60):
        return rate_limited_response()

    try:
        body = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)

    firebase_token = (body.get("firebase_token") or "").strip()
    if not firebase_token:
        return JsonResponse({"error": "firebase_token_required"}, status=400)

    try:
        decoded = verify_id_token(firebase_token)
    except Exception as exc:
        logger.warning("OTP: echec verification Firebase token: %s", exc)
        return JsonResponse({"error": "invalid_firebase_token"}, status=401)

    phone_number = decoded.get("phone_number", "")
    if not phone_number:
        return JsonResponse({"error": "no_phone_in_token"}, status=400)

    uid = int(request.api_user_id)
    from .models import UserProfile

    updated = UserProfile.objects.filter(user_id=uid).update(
        phone_verified=True,
        phone_e164=phone_number,
    )

    if not updated:
        return JsonResponse({"error": "user_not_found"}, status=404)

    logger.info(
        "OTP: telephone %s verifie pour user_id=%s", phone_number, uid
    )

    return JsonResponse({
        "ok": True,
        "phone_number": phone_number,
    })


@csrf_exempt
@require_api_auth(["client", "prestataire"])
def api_auth_otp_status(request):
    """Retourne le statut de vérification du téléphone."""
    if request.method != "GET":
        return JsonResponse({"error": "method_not_allowed"}, status=405)

    uid = int(request.api_user_id)
    from .models import UserProfile

    try:
        profile = UserProfile.objects.get(user_id=uid)
    except UserProfile.DoesNotExist:
        return JsonResponse({"error": "user_not_found"}, status=404)

    return JsonResponse({
        "phone_verified": profile.phone_verified,
        "phone_e164": profile.phone_e164 or "",
    })
