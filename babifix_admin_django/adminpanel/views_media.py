"""POST /api/media/upload — upload sécurisé d'images BABIFIX (B7).

Deux modes acceptés :
1. multipart/form-data, champ `file` (un seul fichier par requête)
2. application/json, body `{"data_uri": "data:image/jpeg;base64,..."}`
   (rétro-compatibilité avec les apps qui envoient encore du data URI).

Réponse : `{"url": "/media/babifix_uploads/.../xxx.jpg"}`.

Limites :
- 6 MiB max par image
- types autorisés : jpeg / png / webp
- redimensionnement auto à 1600 px côté long
- 50 uploads / minute / utilisateur (rate limit)
"""

from __future__ import annotations

import json
import logging

from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods

from .auth import require_api_auth
from .services.media_service import MediaService, MediaUploadError
from .throttle import check_rate_limit, rate_limited_response

logger = logging.getLogger(__name__)


@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client", "prestataire", "admin"])
def api_media_upload(request):
    if check_rate_limit(request, "media_upload", max_requests=50, window=60):
        return rate_limited_response()

    uid = int(request.api_user_id)

    # Mode 1 : multipart
    upload = request.FILES.get("file")
    if upload:
        try:
            url = MediaService.store_upload(upload, uid)
        except MediaUploadError as e:
            return JsonResponse({"error": str(e)}, status=400)
        except Exception as exc:
            logger.exception("Media upload (multipart) failed: %s", exc)
            return JsonResponse({"error": "upload_failed"}, status=500)
        return JsonResponse({"url": url})

    # Mode 2 : data URI
    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)
    uri = (payload.get("data_uri") or "").strip()
    if not uri:
        return JsonResponse(
            {"error": "missing_file", "detail": "Fournir `file` (multipart) ou `data_uri` (JSON)."},
            status=400,
        )
    try:
        url = MediaService.store_data_uri(uri, uid)
    except MediaUploadError as e:
        return JsonResponse({"error": str(e)}, status=400)
    except Exception as exc:
        logger.exception("Media upload (data uri) failed: %s", exc)
        return JsonResponse({"error": "upload_failed"}, status=500)
    return JsonResponse({"url": url})
