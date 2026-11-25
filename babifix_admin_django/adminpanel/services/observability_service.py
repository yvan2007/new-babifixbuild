"""Service centralise d observabilite, journalisation d erreurs exactes et masquage PII."""

from __future__ import annotations

import ctypes
import hashlib
import logging
import os
import re
import sys
import traceback
from datetime import timedelta
from typing import Any

from django.db import DatabaseError
from django.db.models import F
from django.utils import timezone

logger = logging.getLogger("babifix.observability")

# Cles sensibles a masquer systematiquement (Loi CI n 2013-450 + OWASP)
SENSITIVE_KEYS = {
    "password",
    "passwd",
    "pwd",
    "pin",
    "pin_code",
    "secret",
    "token",
    "access",
    "access_token",
    "refresh",
    "refresh_token",
    "jwt",
    "authorization",
    "cookie",
    "set-cookie",
    "x-api-key",
    "x-vitrine-signature",
    "api_key",
    "otp",
    "code_otp",
    "cvv",
    "card_number",
    "cni",
    "cni_recto_b64",
    "cni_verso_b64",
    "selfie_b64",
    "photo_portrait_b64",
    "casier_b64",
    "certificat_medical_b64",
    "signature_b64",
    "image_b64",
    "document_b64",
}

_JWT_RE = re.compile(r"eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.?[A-Za-z0-9_-]*")
_BEARER_RE = re.compile(r"(Bearer|Token)\s+[A-Za-z0-9\-._~+/]+=*", re.IGNORECASE)
_KV_SECRET_RE = re.compile(
    r'("?(?:password|passwd|pin|token|secret|authorization|otp|cni_[a-z_]*b64|selfie_b64)"?\s*[:=]\s*)"?([^",}\s]{3,})"?',
    re.IGNORECASE,
)
_LONG_B64_RE = re.compile(r"(data:image/[a-z+]+;base64,)?[A-Za-z0-9+/]{140,}={0,2}")

BOT_SCAN_PREFIXES = (
    "/wp-login.php",
    "/wp-admin",
    "/xmlrpc.php",
    "/.env",
    "/.git",
    "/phpmyadmin",
    "/admin.php",
    "/boaform",
)


def get_process_ram_mb() -> float:
    """Retourne la memoire RSS courante du processus Python en Mo (Windows + Linux)."""
    try:
        if sys.platform == "win32":
            class PROCESS_MEMORY_COUNTERS(ctypes.Structure):
                _fields_ = [
                    ("cb", ctypes.c_ulong),
                    ("PageFaultCount", ctypes.c_ulong),
                    ("PeakWorkingSetSize", ctypes.c_size_t),
                    ("WorkingSetSize", ctypes.c_size_t),
                    ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                    ("PagefileUsage", ctypes.c_size_t),
                    ("PeakPagefileUsage", ctypes.c_size_t),
                ]

            counters = PROCESS_MEMORY_COUNTERS()
            counters.cb = ctypes.sizeof(PROCESS_MEMORY_COUNTERS)
            handle = ctypes.windll.kernel32.GetCurrentProcess()
            ok = ctypes.windll.psapi.GetProcessMemoryInfo(
                handle, ctypes.byref(counters), counters.cb
            )
            if ok:
                return round(counters.WorkingSetSize / (1024 * 1024), 2)
        else:
            statm = "/proc/self/statm"
            if os.path.exists(statm):
                with open(statm, "r", encoding="utf-8") as fh:
                    parts = fh.read().strip().split()
                if len(parts) >= 2:
                    rss_pages = int(parts[1])
                    page_size = os.sysconf("SC_PAGE_SIZE")
                    return round((rss_pages * page_size) / (1024 * 1024), 2)
            import resource

            rss_kb = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
            return round(rss_kb / 1024.0, 2)
    except Exception:
        pass
    return 0.0


def redact_text(value: Any, max_len: int = 1500) -> str:
    """Masque tokens, mots de passe, PINs et blobs base64 dans toute chaine."""
    if value is None:
        return ""
    text = str(value)
    if not text:
        return ""
    text = _BEARER_RE.sub(r"\1 [MASQUE]", text)
    text = _JWT_RE.sub("[MASQUE_JWT]", text)
    text = _KV_SECRET_RE.sub(r'\1"[MASQUE]"', text)
    text = _LONG_B64_RE.sub("[MASQUE_B64]", text)
    if len(text) > max_len:
        return text[: max_len - 16] + " ...[TRONQUE]"
    return text


def redact_mapping(data: Any, depth: int = 0) -> Any:
    """Masque recursivement les cles sensibles d un dict/list."""
    if depth > 4:
        return "[TRONQUE]"
    if isinstance(data, dict):
        cleaned = {}
        for k, v in list(data.items())[:40]:
            key_str = str(k)
            key_norm = key_str.strip().lower().replace("-", "_")
            if key_norm in SENSITIVE_KEYS or any(
                frag in key_norm for frag in ("password", "passwd", "secret", "token", "pin", "_b64")
            ):
                cleaned[key_str[:64]] = "[MASQUE]"
            else:
                cleaned[key_str[:64]] = redact_mapping(v, depth + 1)
        return cleaned
    if isinstance(data, (list, tuple)):
        return [redact_mapping(item, depth + 1) for item in list(data)[:20]]
    if isinstance(data, str):
        return redact_text(data, max_len=300)
    return data


def build_client_ip(request) -> str:
    """Extrait l IP client sans confiance aveugle."""
    xff = (request.META.get("HTTP_X_FORWARDED_FOR") or "").split(",")[0].strip()
    raw_ip = xff or str(request.META.get("REMOTE_ADDR") or "")
    return raw_ip[:64]


def extract_exception_origin(exc: BaseException | None) -> tuple[str, int | None, str]:
    """Retourne (fichier, ligne, traceback_tronque) pour localiser le bug exact."""
    if exc is None:
        return "", None, ""
    tb = exc.__traceback__
    frames = traceback.extract_tb(tb) if tb else []
    chosen = None
    for frame in reversed(frames):
        norm = frame.filename.replace("\\", "/")
        if "/adminpanel/" in norm or "/vitrine/" in norm or "/babifix_" in norm:
            chosen = frame
            break
    if chosen is None and frames:
        chosen = frames[-1]
    source_file = ""
    source_line = None
    if chosen is not None:
        parts = chosen.filename.replace("\\", "/").split("/")
        source_file = "/".join(parts[-3:])[:255]
        source_line = chosen.lineno
    tb_text = "".join(traceback.format_exception(type(exc), exc, tb))
    return source_file, source_line, redact_text(tb_text, max_len=4000)


def is_noise_bot_404(path: str, status_code: int) -> bool:
    """Evite d encombrer la DB avec les scans automatiques evident de bots."""
    if status_code != 404:
        return False
    low = (path or "").lower()
    return any(low.startswith(prefix) for prefix in BOT_SCAN_PREFIXES)


def compute_fingerprint(
    source: str,
    level: str,
    endpoint: str,
    status_code: int | None,
    exception_type: str,
    message: str,
) -> str:
    """Empreinte deterministe pour regrouper les incidents identiques sur 60s."""
    raw = f"{source}|{level}|{endpoint[:180]}|{status_code}|{exception_type[:80]}|{message[:120]}"
    return hashlib.sha256(raw.encode("utf-8", errors="ignore")).hexdigest()


def record_system_event(
    *,
    source: str,
    level: str,
    message: str,
    endpoint: str = "",
    method: str = "",
    status_code: int | None = None,
    duration_ms: float | None = None,
    request_id: str = "",
    user=None,
    user_label: str = "",
    client_ip: str = "",
    user_agent: str = "",
    exception_type: str = "",
    source_file: str = "",
    source_line: int | None = None,
    traceback_text: str = "",
    payload_redacted: str = "",
    app_version: str = "",
    ram_mb: float | None = None,
    dedup_window_seconds: int = 60,
) -> None:
    """Enregistre un incident exact dans SystemEventLog avec deduplication 60s et zero echec fatal."""
    from adminpanel.models import SystemEventLog

    try:
        clean_endpoint = redact_text(endpoint, max_len=255)
        clean_msg = redact_text(message, max_len=1000)
        clean_tb = redact_text(traceback_text, max_len=4000)
        clean_payload = redact_text(payload_redacted, max_len=1500)
        clean_ua = redact_text(user_agent, max_len=240)
        fp = compute_fingerprint(
            source, level, clean_endpoint, status_code, exception_type, clean_msg
        )

        resolved_label = user_label
        resolved_user_id = None
        if user is not None and getattr(user, "is_authenticated", False):
            resolved_user_id = getattr(user, "id", None)
            if not resolved_label:
                username = getattr(user, "username", "") or getattr(user, "email", "")
                role = "staff" if getattr(user, "is_staff", False) else "user"
                resolved_label = f"{username} ({role})"[:120]

        now = timezone.now()
        if dedup_window_seconds > 0:
            recent = (
                SystemEventLog.objects.filter(
                    fingerprint=fp,
                    resolved=False,
                    last_seen_at__gte=now - timedelta(seconds=dedup_window_seconds),
                )
                .order_by("-id")
                .first()
            )
            if recent is not None:
                SystemEventLog.objects.filter(pk=recent.pk).update(
                    occurrence_count=F("occurrence_count") + 1,
                    last_seen_at=now,
                    duration_ms=duration_ms if duration_ms is not None else recent.duration_ms,
                    ram_mb=ram_mb if ram_mb is not None else recent.ram_mb,
                )
                return

        SystemEventLog.objects.create(
            source=source[:24],
            level=level[:16],
            request_id=request_id[:48],
            endpoint=clean_endpoint,
            method=method[:12],
            status_code=status_code,
            duration_ms=round(float(duration_ms), 2) if duration_ms is not None else None,
            ram_mb=round(float(ram_mb), 2) if ram_mb is not None else get_process_ram_mb(),
            user_id=resolved_user_id,
            user_label=resolved_label[:120],
            client_ip=client_ip[:64],
            user_agent=clean_ua,
            exception_type=exception_type[:120],
            source_file=source_file[:255],
            source_line=source_line,
            message=clean_msg,
            traceback_text=clean_tb,
            payload_redacted=clean_payload,
            app_version=app_version[:48],
            fingerprint=fp,
            last_seen_at=now,
        )
    except DatabaseError as db_err:
        logger.warning("Observability DB fallback: %s | endpoint=%s", db_err, endpoint)
    except Exception as exc:
        logger.warning("Observability record failed cleanly: %s", exc)
