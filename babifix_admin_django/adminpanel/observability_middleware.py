"""Middleware d observabilite BABIFIX : latence exacte, erreurs HTTP/exceptions et RAM."""

from __future__ import annotations

import json
import time
import uuid

from django.conf import settings

from adminpanel.services.observability_service import (
    build_client_ip,
    extract_exception_origin,
    get_process_ram_mb,
    is_noise_bot_404,
    record_system_event,
    redact_mapping,
    redact_text,
)

SKIP_PREFIXES = ("/static/", "/media/", "/favicon.ico")


def _extract_redacted_payload(request) -> str:
    """Extrait query params et extrait JSON/POST entierement masques pour diagnostic."""
    parts = []
    try:
        if request.GET:
            qp = redact_mapping(dict(request.GET.items()))
            parts.append(f"GET={json.dumps(qp, ensure_ascii=False)}")
    except Exception:
        pass
    try:
        ctype = (request.META.get("CONTENT_TYPE") or "").lower()
        if request.method in ("POST", "PUT", "PATCH") and "multipart/form-data" not in ctype:
            raw = getattr(request, "body", b"") or b""
            if raw and len(raw) <= 8192:
                text = raw.decode("utf-8", errors="ignore").strip()
                if "application/json" in ctype and text.startswith("{"):
                    parsed = json.loads(text)
                    cleaned = redact_mapping(parsed)
                    parts.append(f"JSON={json.dumps(cleaned, ensure_ascii=False)}")
                elif text:
                    parts.append(f"BODY={redact_text(text, max_len=500)}")
    except Exception:
        pass
    return " | ".join(parts)


class BabifixObservabilityMiddleware:
    """Capture erreurs exactes (fichier:ligne), 4xx/5xx et requetes lentes >= 800ms."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        path = request.path or "/"
        if path.startswith(SKIP_PREFIXES):
            return self.get_response(request)

        req_id = uuid.uuid4().hex[:16]
        request.babifix_request_id = req_id
        request._babifix_exc_logged = False
        start = time.perf_counter()

        response = self.get_response(request)

        duration_ms = (time.perf_counter() - start) * 1000.0
        status_code = getattr(response, "status_code", 200)
        try:
            response["X-Request-ID"] = req_id
            response["X-Response-Time-Ms"] = f"{duration_ms:.1f}"
        except Exception:
            pass

        slow_threshold = float(getattr(settings, "BABIFIX_SLOW_REQUEST_MS", 800))
        is_slow = duration_ms >= slow_threshold and not path.startswith("/api/health")

        if status_code >= 500 and not getattr(request, "_babifix_exc_logged", False):
            record_system_event(
                source="backend",
                level="error",
                message=f"Reponse HTTP {status_code} sur {request.method} {path}",
                endpoint=path,
                method=request.method,
                status_code=status_code,
                duration_ms=duration_ms,
                request_id=req_id,
                user=getattr(request, "user", None),
                client_ip=build_client_ip(request),
                user_agent=request.META.get("HTTP_USER_AGENT", ""),
                payload_redacted=_extract_redacted_payload(request),
                ram_mb=get_process_ram_mb(),
            )
        elif 400 <= status_code < 500:
            if not is_noise_bot_404(path, status_code) and status_code != 429:
                level = "warning"
                dedup = 300 if status_code == 404 else 60
                record_system_event(
                    source="backend",
                    level=level,
                    message=f"Requete client rejetee HTTP {status_code} sur {request.method} {path}",
                    endpoint=path,
                    method=request.method,
                    status_code=status_code,
                    duration_ms=duration_ms,
                    request_id=req_id,
                    user=getattr(request, "user", None),
                    client_ip=build_client_ip(request),
                    user_agent=request.META.get("HTTP_USER_AGENT", ""),
                    payload_redacted=_extract_redacted_payload(request),
                    dedup_window_seconds=dedup,
                )
        elif is_slow:
            record_system_event(
                source="backend",
                level="slow",
                message=f"Latence elevee ({duration_ms:.0f} ms >= {slow_threshold:.0f} ms) sur {request.method} {path}",
                endpoint=path,
                method=request.method,
                status_code=status_code,
                duration_ms=duration_ms,
                request_id=req_id,
                user=getattr(request, "user", None),
                client_ip=build_client_ip(request),
                user_agent=request.META.get("HTTP_USER_AGENT", ""),
                ram_mb=get_process_ram_mb(),
            )

        return response

    def process_exception(self, request, exception):
        path = getattr(request, "path", "/") or "/"
        request._babifix_exc_logged = True
        src_file, src_line, tb_text = extract_exception_origin(exception)
        req_id = getattr(request, "babifix_request_id", uuid.uuid4().hex[:16])
        record_system_event(
            source="backend",
            level="critical",
            message=f"{type(exception).__name__}: {exception}",
            endpoint=path,
            method=getattr(request, "method", ""),
            status_code=500,
            request_id=req_id,
            user=getattr(request, "user", None),
            client_ip=build_client_ip(request),
            user_agent=request.META.get("HTTP_USER_AGENT", ""),
            exception_type=type(exception).__name__,
            source_file=src_file,
            source_line=src_line,
            traceback_text=tb_text,
            payload_redacted=_extract_redacted_payload(request),
            ram_mb=get_process_ram_mb(),
        )
        return None
