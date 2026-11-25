"""Endpoints Admin et ingestion telemetrie Vitrine pour l observabilite live."""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import time
from datetime import timedelta

from django.conf import settings
from django.contrib.auth.decorators import login_required
from django.db.models import Avg, Count, Max, Q
from django.http import JsonResponse
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_GET, require_POST

from .models import SystemEventLog
from .services.observability_service import (
    get_process_ram_mb,
    record_system_event,
    redact_mapping,
    redact_text,
)
from .throttle import check_rate_limit


def _vitrine_shared_secret() -> str:
    return (
        os.environ.get("VITRINE_TELEMETRY_SECRET", "").strip()
        or getattr(settings, "VITRINE_TELEMETRY_SECRET", "").strip()
    )


def _compute_vitrine_sig(secret: str, timestamp: str, body_bytes: bytes) -> str:
    msg = timestamp.encode("utf-8") + b"." + body_bytes
    return hmac.new(secret.encode("utf-8"), msg, hashlib.sha256).hexdigest()


@login_required(login_url="/admin/login/")
@require_GET
def api_admin_observability_list(request):
    """Retourne les KPIs temps reel + la liste filtree des incidents pour le Cockpit."""
    if not (request.user.is_staff or request.user.is_superuser):
        return JsonResponse({"error": "Acces refuse"}, status=403)

    source = (request.GET.get("source") or "").strip()
    level = (request.GET.get("level") or "").strip()
    status_filter = (request.GET.get("status") or "open").strip()
    q = (request.GET.get("q") or "").strip()
    try:
        limit = min(max(int(request.GET.get("limit", 60)), 1), 200)
    except ValueError:
        limit = 60

    qs = SystemEventLog.objects.all()
    if source:
        qs = qs.filter(source=source)
    if level:
        qs = qs.filter(level=level)
    if status_filter == "open":
        qs = qs.filter(resolved=False)
    elif status_filter == "resolved":
        qs = qs.filter(resolved=True)
    if q:
        qs = qs.filter(
            Q(endpoint__icontains=q)
            | Q(message__icontains=q)
            | Q(exception_type__icontains=q)
            | Q(source_file__icontains=q)
            | Q(user_label__icontains=q)
            | Q(request_id__icontains=q)
        )

    items = []
    for ev in qs.order_by("-last_seen_at", "-id")[:limit]:
        items.append(
            {
                "id": ev.id,
                "source": ev.source,
                "level": ev.level,
                "request_id": ev.request_id,
                "endpoint": ev.endpoint,
                "method": ev.method,
                "status_code": ev.status_code,
                "duration_ms": ev.duration_ms,
                "ram_mb": ev.ram_mb,
                "user_label": ev.user_label,
                "client_ip": ev.client_ip,
                "exception_type": ev.exception_type,
                "source_file": ev.source_file,
                "source_line": ev.source_line,
                "message": ev.message,
                "traceback_text": ev.traceback_text,
                "payload_redacted": ev.payload_redacted,
                "app_version": ev.app_version,
                "occurrence_count": ev.occurrence_count,
                "resolved": ev.resolved,
                "resolved_by": ev.resolved_by,
                "last_seen_at": ev.last_seen_at.isoformat() if ev.last_seen_at else None,
                "created_at": ev.created_at.isoformat() if ev.created_at else None,
            }
        )

    since_24h = timezone.now() - timedelta(hours=24)
    summary_24h = SystemEventLog.objects.filter(last_seen_at__gte=since_24h).aggregate(
        total=Count("id"),
        open_errors=Count("id", filter=Q(resolved=False, level__in=["critical", "error"])),
        slow_count=Count("id", filter=Q(level="slow")),
        mobile_count=Count("id", filter=Q(source__in=["mobile_client", "mobile_pro"])),
        vitrine_count=Count("id", filter=Q(source="vitrine")),
        avg_ms=Avg("duration_ms", filter=Q(duration_ms__isnull=False)),
        max_ms=Max("duration_ms"),
    )

    return JsonResponse(
        {
            "ok": True,
            "ram_mb": get_process_ram_mb(),
            "slow_threshold_ms": getattr(settings, "BABIFIX_SLOW_REQUEST_MS", 800),
            "summary_24h": {
                "total": summary_24h["total"] or 0,
                "open_errors": summary_24h["open_errors"] or 0,
                "slow_count": summary_24h["slow_count"] or 0,
                "mobile_count": summary_24h["mobile_count"] or 0,
                "vitrine_count": summary_24h["vitrine_count"] or 0,
                "avg_ms": round(summary_24h["avg_ms"] or 0.0, 1),
                "max_ms": round(summary_24h["max_ms"] or 0.0, 1),
            },
            "events": items,
        }
    )


@login_required(login_url="/admin/login/")
@require_POST
def api_admin_observability_resolve(request, pk: int):
    """Marque un incident (ou tous ses doublons ouverts) comme resolu."""
    if not (request.user.is_staff or request.user.is_superuser):
        return JsonResponse({"error": "Acces refuse"}, status=403)
    ev = get_object_or_404(SystemEventLog, pk=pk)
    ev.resolved = True
    ev.resolved_by = request.user.username[:120]
    ev.resolved_at = timezone.now()
    ev.save(update_fields=["resolved", "resolved_by", "resolved_at"])
    return JsonResponse({"ok": True, "id": ev.id, "resolved": True})


@login_required(login_url="/admin/login/")
@require_POST
def api_admin_observability_purge(request):
    """Purge les incidents resolus ou anciens (> 30 jours) pour maitriser la taille DB."""
    if not (request.user.is_staff or request.user.is_superuser):
        return JsonResponse({"error": "Acces refuse"}, status=403)
    mode = (request.POST.get("mode") or "").strip()
    if mode == "resolved":
        deleted, _ = SystemEventLog.objects.filter(resolved=True).delete()
    else:
        cutoff = timezone.now() - timedelta(days=30)
        deleted, _ = SystemEventLog.objects.filter(last_seen_at__lt=cutoff).delete()
    return JsonResponse({"ok": True, "deleted": deleted})


@csrf_exempt
@require_POST
def api_vitrine_telemetry_ingest(request):
    """Recoie de facon signee HMAC-SHA256 les erreurs et latences du site Vitrine."""
    if check_rate_limit(request, "vitrine_telemetry", max_requests=120, window=60):
        return JsonResponse({"error": "Trop de requetes"}, status=429)

    secret = _vitrine_shared_secret()
    if not secret:
        return JsonResponse({"error": "Telemetrie Vitrine non configuree"}, status=503)

    ts = (request.META.get("HTTP_X_VITRINE_TIMESTAMP") or "").strip()
    sig = (request.META.get("HTTP_X_VITRINE_SIGNATURE") or "").strip()
    try:
        ts_int = int(ts)
    except ValueError:
        return JsonResponse({"error": "Timestamp invalide"}, status=403)

    if abs(int(time.time()) - ts_int) > 120:
        return JsonResponse({"error": "Signature expiree"}, status=403)

    body = request.body or b""
    expected = _compute_vitrine_sig(secret, ts, body)
    if not hmac.compare_digest(expected, sig):
        return JsonResponse({"error": "Signature invalide"}, status=403)

    try:
        data = json.loads(body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "JSON invalide"}, status=400)

    level = str(data.get("level") or "error").lower()
    if level not in {"critical", "error", "slow", "warning"}:
        level = "error"

    record_system_event(
        source="vitrine",
        level=level,
        message=str(data.get("message") or "Erreur Vitrine"),
        endpoint=str(data.get("endpoint") or "/"),
        method=str(data.get("method") or "GET"),
        status_code=data.get("status_code"),
        duration_ms=data.get("duration_ms"),
        request_id=str(data.get("request_id") or ""),
        user_label=str(data.get("user_label") or "visiteur vitrine"),
        client_ip=str(data.get("client_ip") or ""),
        user_agent=str(data.get("user_agent") or ""),
        exception_type=str(data.get("exception_type") or ""),
        source_file=str(data.get("source_file") or ""),
        source_line=data.get("source_line"),
        traceback_text=str(data.get("traceback_text") or ""),
        payload_redacted=json.dumps(redact_mapping(data.get("payload") or {}), ensure_ascii=False)
        if isinstance(data.get("payload"), dict)
        else redact_text(data.get("payload") or ""),
        ram_mb=data.get("ram_mb"),
    )
    return JsonResponse({"ok": True})
