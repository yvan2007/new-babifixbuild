"""MediaService — upload sécurisé d'images BABIFIX (B7).

Remplace le stockage base64 inline par un vrai upload :
- multipart/form-data ou JSON {data_uri}
- validation type MIME + taille (<= 6 MiB par image)
- redimensionnement automatique (max 1600px côté long, qualité 85)
- nommage hashé pour cache long terme
- retourne une URL canonique relative au backend

Stockage : MEDIA_ROOT/babifix_uploads/{year}/{month}/{user_id}/{hash}.jpg
URL     : MEDIA_URL + babifix_uploads/...

Côté Flutter, le presta/client uploade chaque photo puis envoie les URLs
retournées dans `photos_avant` / `photos_apres` / `client_journal_note`.
"""

from __future__ import annotations

import base64
import hashlib
import io
import logging
import os
import re
import uuid
from typing import Optional

from django.conf import settings
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.utils import timezone

logger = logging.getLogger(__name__)

MAX_BYTES = 6 * 1024 * 1024  # 6 MiB
MAX_DIMENSION = 1600
ALLOWED_MIMES = {"image/jpeg", "image/png", "image/webp"}

_MIME_TO_EXT = {
    "image/jpeg": "jpg",
    "image/jpg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
}


class MediaUploadError(Exception):
    pass


def _ensure_dir(rel_path: str) -> str:
    abs_dir = os.path.join(settings.MEDIA_ROOT, rel_path)
    os.makedirs(abs_dir, exist_ok=True)
    return abs_dir


def _safe_filename(stem: str, ext: str) -> str:
    stem = re.sub(r"[^a-zA-Z0-9_-]", "", stem)[:24] or "img"
    return f"{stem}_{uuid.uuid4().hex[:10]}.{ext}"


def _resize_if_needed(content: bytes, mime: str) -> tuple[bytes, str]:
    """Redimensionne l'image si > MAX_DIMENSION côté long.

    Retourne (nouveaux_octets, nouveau_mime). Si Pillow n'est pas
    disponible, retourne l'original tel quel.
    """
    try:
        from PIL import Image  # type: ignore
    except Exception:
        return content, mime
    try:
        img = Image.open(io.BytesIO(content))
        img.load()
    except Exception as exc:
        logger.warning("Pillow open failed: %s", exc)
        return content, mime
    w, h = img.size
    if max(w, h) <= MAX_DIMENSION:
        return content, mime
    if w >= h:
        new_w = MAX_DIMENSION
        new_h = int(h * MAX_DIMENSION / w)
    else:
        new_h = MAX_DIMENSION
        new_w = int(w * MAX_DIMENSION / h)
    img = img.convert("RGB") if img.mode != "RGB" else img
    img = img.resize((new_w, new_h), Image.LANCZOS)
    out = io.BytesIO()
    img.save(out, format="JPEG", quality=85, optimize=True)
    return out.getvalue(), "image/jpeg"


def _decode_data_uri(uri: str) -> tuple[bytes, str]:
    """data:image/jpeg;base64,xxxx → (bytes, 'image/jpeg')."""
    if not uri.startswith("data:"):
        raise MediaUploadError("not_data_uri")
    head, _, b64 = uri.partition(",")
    m = re.match(r"data:([^;]+);base64$", head)
    if not m:
        raise MediaUploadError("invalid_data_uri_header")
    mime = m.group(1).lower()
    if mime not in ALLOWED_MIMES:
        raise MediaUploadError("unsupported_mime")
    try:
        return base64.b64decode(b64), mime
    except Exception:
        raise MediaUploadError("invalid_base64")


class MediaService:
    """Upload + stockage local (extensible plus tard vers S3/R2)."""

    @staticmethod
    def store_bytes(content: bytes, mime: str, user_id: int) -> str:
        """Sauvegarde des octets image. Retourne l'URL relative."""
        if mime not in ALLOWED_MIMES:
            raise MediaUploadError("unsupported_mime")
        if len(content) > MAX_BYTES:
            raise MediaUploadError("file_too_large")

        content, mime = _resize_if_needed(content, mime)
        ext = _MIME_TO_EXT.get(mime, "jpg")

        now = timezone.now()
        rel_dir = os.path.join(
            "babifix_uploads",
            f"{now.year:04d}",
            f"{now.month:02d}",
            str(int(user_id) or 0),
        )
        _ensure_dir(rel_dir)
        # Hash court : permet la déduplication si l'utilisateur uploade 2× la même
        digest = hashlib.sha1(content).hexdigest()[:12]
        filename = _safe_filename(digest, ext)
        rel_path = f"{rel_dir}/{filename}".replace("\\", "/")
        saved = default_storage.save(rel_path, ContentFile(content))
        return f"{settings.MEDIA_URL.rstrip('/')}/{saved.lstrip('/')}"

    @staticmethod
    def store_data_uri(uri: str, user_id: int) -> str:
        content, mime = _decode_data_uri(uri)
        return MediaService.store_bytes(content, mime, user_id)

    @staticmethod
    def store_upload(uploaded_file, user_id: int) -> str:
        """Pour les InMemoryUploadedFile/TemporaryUploadedFile Django."""
        mime = (uploaded_file.content_type or "").lower()
        if mime not in ALLOWED_MIMES:
            raise MediaUploadError("unsupported_mime")
        content = uploaded_file.read()
        if not content:
            raise MediaUploadError("empty_file")
        return MediaService.store_bytes(content, mime, user_id)
