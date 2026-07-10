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
MAX_AUDIO_BYTES = 15 * 1024 * 1024  # 15 MiB (note vocale ~2 min)
MAX_DIMENSION = 1600
ALLOWED_MIMES = {"image/jpeg", "image/png", "image/webp"}
# Note vocale (record ^6.x → conteneur m4a/aac). On tolère aussi les variantes
# et l'octet-stream (certains clients ne renseignent pas le content-type).
ALLOWED_AUDIO_MIMES = {
    "audio/mp4", "audio/aac", "audio/m4a", "audio/x-m4a",
    "audio/mpeg", "audio/mp3", "audio/ogg", "audio/wav", "audio/webm",
}

_MIME_TO_EXT = {
    "image/jpeg": "jpg",
    "image/jpg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
}

_AUDIO_MIME_TO_EXT = {
    "audio/mp4": "m4a",
    "audio/aac": "m4a",
    "audio/m4a": "m4a",
    "audio/x-m4a": "m4a",
    "audio/mpeg": "mp3",
    "audio/mp3": "mp3",
    "audio/ogg": "ogg",
    "audio/wav": "wav",
    "audio/webm": "webm",
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
    def _audio_storage():
        """Storage adapté à l'audio.

        Sur Cloudinary, le storage média par défaut upload en `resource_type=
        image` → il REFUSE les .m4a/.aac (d'où « Envoi de la note vocale
        échoué »). On force donc `RawMediaCloudinaryStorage` (resource_type=raw)
        pour l'audio. En local (FileSystemStorage), le défaut convient.
        """
        try:
            if getattr(settings, "CLOUDINARY_URL", ""):
                from cloudinary_storage.storage import RawMediaCloudinaryStorage
                return RawMediaCloudinaryStorage()
        except Exception:
            pass
        return default_storage

    @staticmethod
    def store_audio_bytes(content: bytes, ext: str, user_id: int) -> str:
        """Sauvegarde une note vocale telle quelle (pas de resize)."""
        if not content:
            raise MediaUploadError("empty_file")
        if len(content) > MAX_AUDIO_BYTES:
            raise MediaUploadError("file_too_large")
        ext = (ext or "m4a").lstrip(".").lower()[:5] or "m4a"
        now = timezone.now()
        rel_dir = os.path.join(
            "babifix_uploads", f"{now.year:04d}", f"{now.month:02d}",
            str(int(user_id) or 0),
        )
        digest = hashlib.sha1(content).hexdigest()[:12]
        filename = _safe_filename(f"vn{digest}", ext)
        rel_path = f"{rel_dir}/{filename}".replace("\\", "/")

        storage = MediaService._audio_storage()
        # _ensure_dir n'est utile qu'en FileSystem local (no-op sur Cloudinary).
        try:
            _ensure_dir(rel_dir)
        except Exception:
            pass
        saved = storage.save(rel_path, ContentFile(content))
        # storage.url() renvoie l'URL correcte (absolue Cloudinary /raw/, ou
        # /media/ en local). NE PAS reconstruire à la main pour Cloudinary.
        try:
            return storage.url(saved)
        except Exception:
            return f"{settings.MEDIA_URL.rstrip('/')}/{saved.lstrip('/')}"

    @staticmethod
    def store_upload(uploaded_file, user_id: int) -> str:
        """Pour les InMemoryUploadedFile/TemporaryUploadedFile Django.

        Accepte les images (redimensionnées) ET l'audio des notes vocales
        (stocké tel quel). Certains clients n'envoient pas de content-type
        fiable → on retombe sur l'extension du nom de fichier.
        """
        mime = (uploaded_file.content_type or "").lower()
        name = (getattr(uploaded_file, "name", "") or "").lower()

        # Audio (note vocale) ?
        is_audio = mime in ALLOWED_AUDIO_MIMES or name.endswith(
            (".m4a", ".aac", ".mp3", ".ogg", ".wav", ".webm")
        )
        if is_audio:
            content = uploaded_file.read()
            ext = _AUDIO_MIME_TO_EXT.get(mime)
            if not ext and "." in name:
                ext = name.rsplit(".", 1)[-1]
            return MediaService.store_audio_bytes(content, ext or "m4a", user_id)

        # Image
        if mime not in ALLOWED_MIMES:
            # Dernier recours : deviner via l'extension image du nom.
            if name.endswith((".jpg", ".jpeg")):
                mime = "image/jpeg"
            elif name.endswith(".png"):
                mime = "image/png"
            elif name.endswith(".webp"):
                mime = "image/webp"
            else:
                raise MediaUploadError("unsupported_mime")
        content = uploaded_file.read()
        if not content:
            raise MediaUploadError("empty_file")
        return MediaService.store_bytes(content, mime, user_id)
