"""Middleware d observabilite Vitrine : latence, erreurs exactes et envoi signe vers Admin."""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import threading
import time
import traceback
import urllib.request
import uuid

from django.conf import settings

SKIP_PREFIXES = ("/static/", "/media/", "/favicon.ico", "/robots.txt", "/healthz")
BOT_SCAN_PREFIXES = (
    "/wp-login.php",
    "/wp-admin",
    "/xmlrpc.php",
    "/.env",
    "/.git",
    "/phpmyadmin",
)


def _admin_telemetry_url() -> str:
    base = (
        os.getenv("BABIFIX_ADMIN_API_BASE", "").strip()
        or "http://127.0.0.1:8011"
    ).rstrip("/")
    return f"{base}/api/telemetry/vitrine/"


def _telemetry_secret() -> str:
    return (
        os.getenv("VITRINE_TELEMETRY_SECRET", "").strip()
        or getattr(settings, "VITRINE_TELEMETRY_SECRET", "").strip()
    )


def _extract_origin(exc: BaseException | None) -> tuple[str, int | None, str]:
    if exc is None:
        return "", None, ""
    frames = traceback.extract_tb(exc.__traceback__) if exc.__traceback__ else []
    chosen = None
    for frame in reversed(frames):
        norm = frame.filename.replace("\\", "/")
        if "/vitrine/" in norm or "/babifix_vitrine_django/" in norm:
            chosen = frame
            break
    if chosen is None and frames:
        chosen = frames[-1]
    src_file = "/".join(chosen.filename.replace("\\", "/").split("/")[-3:])[:255] if chosen else ""
    src_line = chosen.lineno if chosen else None
    tb_text = "".join(traceback.format_exception(type(exc), exc, exc.__traceback__))[:4000]
    return src_file, src_line, tb_text


def _dispatch_telemetry_async(payload: dict) -> None:
    secret = _telemetry_secret()
    if not secret:
        return
    url = _admin_telemetry_url()
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    ts = str(int(time.time()))
    sig = hmac.new(secret.encode("utf-8"), ts.encode("utf-8") + b"." + body, hashlib.sha256).hexdigest()

    def _send():
        try:
            req = urllib.request.Request(
                url,
                data=body,
                method="POST",
                headers={
                    "Content-Type": "application/json",
                    "X-Vitrine-Timestamp": ts,
                    "X-Vitrine-Signature": sig,
                },
            )
            with urllib.request.urlopen(req, timeout=1.5):
                pass
        except Exception:
            pass

    threading.Thread(target=_send, daemon=True).start()


class BabifixVitrineObservabilityMiddleware:
    """Mesure les temps de reponse Vitrine et signale erreurs/latences au Cockpit Admin."""

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
        low_path = path.lower()
        is_bot = status_code == 404 and any(low_path.startswith(p) for p in BOT_SCAN_PREFIXES)

        if status_code >= 500 and not getattr(request, "_babifix_exc_logged", False):
            _dispatch_telemetry_async(
                {
                    "level": "error",
                    "endpoint": path,
                    "method": request.method,
                    "status_code": status_code,
                    "duration_ms": round(duration_ms, 1),
                    "request_id": req_id,
                    "message": f"Vitrine HTTP {status_code} sur {request.method} {path}",
                    "user_agent": request.META.get("HTTP_USER_AGENT", "")[:200],
                }
            )
        elif 400 <= status_code < 500 and not is_bot and status_code != 429:
            _dispatch_telemetry_async(
                {
                    "level": "warning",
                    "endpoint": path,
                    "method": request.method,
                    "status_code": status_code,
                    "duration_ms": round(duration_ms, 1),
                    "request_id": req_id,
                    "message": f"Vitrine requete rejetee HTTP {status_code} sur {path}",
                    "user_agent": request.META.get("HTTP_USER_AGENT", "")[:200],
                }
            )
        elif duration_ms >= slow_threshold:
            _dispatch_telemetry_async(
                {
                    "level": "slow",
                    "endpoint": path,
                    "method": request.method,
                    "status_code": status_code,
                    "duration_ms": round(duration_ms, 1),
                    "request_id": req_id,
                    "message": f"Vitrine latence elevee ({duration_ms:.0f} ms) sur {path}",
                }
            )

        return response

    def process_exception(self, request, exception):
        request._babifix_exc_logged = True
        src_file, src_line, tb_text = _extract_origin(exception)
        req_id = getattr(request, "babifix_request_id", uuid.uuid4().hex[:16])
        _dispatch_telemetry_async(
            {
                "level": "critical",
                "endpoint": getattr(request, "path", "/"),
                "method": getattr(request, "method", "GET"),
                "status_code": 500,
                "request_id": req_id,
                "exception_type": type(exception).__name__,
                "source_file": src_file,
                "source_line": src_line,
                "message": f"{type(exception).__name__}: {exception}",
                "traceback_text": tb_text,
                "user_agent": request.META.get("HTTP_USER_AGENT", "")[:200],
            }
        )
        return None
