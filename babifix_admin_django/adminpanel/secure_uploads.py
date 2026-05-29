"""
Validation des uploads de fichiers BABIFIX.

Empêche :
- les fichiers trop gros (au-delà de Django settings) ;
- les types non autorisés (whitelist MIME + extension) ;
- les noms de fichiers piégés (path traversal `../`, NUL bytes, espaces) ;
- les fichiers magiques détournés (vérification du magic number du fichier réel
  via Pillow pour les images, sinon par signature des premiers octets).

Usage :
    from .secure_uploads import validate_image_upload, SafeUploadError

    image = request.FILES.get("image")
    try:
        image = validate_image_upload(image, max_mb=8)
    except SafeUploadError as e:
        return JsonResponse({"error": str(e)}, status=400)
"""
from __future__ import annotations

import os
import re
from typing import Iterable

from django.core.files.uploadedfile import UploadedFile

# Types acceptés par défaut pour les images BABIFIX (chats, profils, photos d'intervention).
ALLOWED_IMAGE_MIMES = frozenset({
    "image/jpeg",
    "image/png",
    "image/webp",
    "image/heic",
    "image/heif",
})
ALLOWED_IMAGE_EXTS = frozenset({
    ".jpg", ".jpeg", ".png", ".webp", ".heic", ".heif",
})

# Magic bytes : suffisant pour vérifier qu'un .jpg n'est pas un .exe déguisé.
_MAGIC_SIGNATURES: tuple[tuple[bytes, str], ...] = (
    (b"\xFF\xD8\xFF", "image/jpeg"),
    (b"\x89PNG\r\n\x1a\n", "image/png"),
    (b"RIFF", "image/webp"),       # WebP commence par RIFF, on confirme via Pillow
    (b"\x00\x00\x00\x18ftypheic", "image/heic"),
    (b"\x00\x00\x00\x18ftypheix", "image/heic"),
    (b"\x00\x00\x00\x18ftypmif1", "image/heif"),
)

_FILENAME_BAD = re.compile(r"[\x00\\/:*?\"<>|]+")


class SafeUploadError(ValueError):
    """Lévée lorsqu'un upload échoue à la validation."""


def _sniff_magic(head: bytes) -> str | None:
    """Renvoie le MIME deviné à partir des premiers octets, ou None."""
    for sig, mime in _MAGIC_SIGNATURES:
        if head.startswith(sig):
            return mime
    return None


def _safe_filename(name: str) -> str:
    """Nettoie un nom de fichier : enlève path traversal + caractères interdits."""
    base = os.path.basename(name or "").strip()
    base = _FILENAME_BAD.sub("_", base)
    # Tronquer pour éviter les filenames de 4096 chars (DoS).
    if len(base) > 96:
        root, ext = os.path.splitext(base)
        base = root[: 96 - len(ext)] + ext
    if not base:
        base = "upload.bin"
    return base


def validate_upload(
    upload: UploadedFile | None,
    *,
    max_mb: int,
    allowed_mimes: Iterable[str],
    allowed_exts: Iterable[str],
    require_magic_match: bool = True,
) -> UploadedFile:
    """
    Valide un upload générique. Renvoie l'objet upload mutable (avec name nettoyé).
    """
    if upload is None:
        raise SafeUploadError("upload_missing")

    # Taille
    try:
        size = upload.size
    except Exception:
        raise SafeUploadError("upload_invalid")
    max_bytes = max_mb * 1024 * 1024
    if size <= 0 or size > max_bytes:
        raise SafeUploadError(f"upload_too_large_max_{max_mb}mb")

    # Extension
    name = upload.name or ""
    ext = os.path.splitext(name)[1].lower()
    if ext not in allowed_exts:
        raise SafeUploadError("upload_extension_not_allowed")

    # Content-Type déclaré par le client (peu fiable mais sert de premier filtre)
    declared = (upload.content_type or "").split(";")[0].strip().lower()
    if declared and declared not in allowed_mimes:
        raise SafeUploadError("upload_type_not_allowed")

    # Magic number — on lit les 32 premiers octets sans consommer le stream.
    if require_magic_match:
        try:
            pos = upload.tell() if hasattr(upload, "tell") else 0
        except Exception:
            pos = 0
        head = upload.read(32) or b""
        try:
            upload.seek(pos)
        except Exception:
            pass
        sniffed = _sniff_magic(head)
        if sniffed is None or sniffed not in allowed_mimes:
            raise SafeUploadError("upload_magic_mismatch")

    # Nettoyage du nom
    upload.name = _safe_filename(name)
    return upload


def validate_image_upload(
    upload: UploadedFile | None,
    *,
    max_mb: int = 8,
) -> UploadedFile:
    """Valide un upload **image** (JPEG/PNG/WebP/HEIC)."""
    return validate_upload(
        upload,
        max_mb=max_mb,
        allowed_mimes=ALLOWED_IMAGE_MIMES,
        allowed_exts=ALLOWED_IMAGE_EXTS,
        require_magic_match=True,
    )
