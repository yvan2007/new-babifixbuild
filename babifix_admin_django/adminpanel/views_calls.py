"""Endpoints d'appel LiveKit — Phase D.

Le backend est l'autorité de signalisation :
- POST /api/calls/initiate         (caller) → crée la room, FCM ring l'appelé, renvoie token
- POST /api/calls/<id>/answer      (callee) → marque ANSWERED, renvoie token
- POST /api/calls/<id>/reject      (callee) → marque REJECTED, notifie l'appelant
- POST /api/calls/<id>/end         (caller ou callee) → ENDED + durée
- GET  /api/calls/<id>             → état courant (polling éventuel)
- GET  /api/calls/history          → 30 derniers appels du user
"""

from __future__ import annotations

import json
import logging
from datetime import timedelta

from django.contrib.auth.models import User
from django.http import JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods

from .auth import require_api_auth
from .livekit_service import generate_access_token, livekit_url, new_room_name
from .models import Call, Conversation, Reservation
from .push_dispatch import _schedule

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _identity_for(user_id: int, role: str) -> str:
    return f"{role}_{user_id}"


def _user_display(user: User) -> str:
    return user.get_full_name() or user.username or f"user_{user.pk}"


def _serialize(call: Call) -> dict:
    return {
        "id": call.pk,
        "room_name": call.room_name,
        "kind": call.kind,
        "status": call.status,
        "caller_id": call.caller_id,
        "callee_id": call.callee_id,
        "caller_name": _user_display(call.caller),
        "callee_name": _user_display(call.callee),
        "reservation_reference": (
            call.reservation.reference if call.reservation else None
        ),
        "started_at": call.started_at.isoformat(),
        "answered_at": call.answered_at.isoformat() if call.answered_at else None,
        "ended_at": call.ended_at.isoformat() if call.ended_at else None,
        "duration_seconds": call.duration_seconds,
        "livekit_url": livekit_url(),
    }


# ---------------------------------------------------------------------------
# POST /api/livekit/token
# Génération de token LiveKit côté serveur uniquement.
#
# La clé secrète LiveKit ne doit JAMAIS être présente dans l'app mobile.
# L'app fournit juste un contexte d'autorisation (conversation_id ou
# reservation_reference) et le backend vérifie l'accès puis signe.
# ---------------------------------------------------------------------------
@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client", "prestataire", "admin"])
def api_livekit_token(request):
    """Body JSON (l'un des deux) :
       - conversation_id (int)        → room = "chat_conv_<id>"
       - reservation_reference (str)  → room = "res_<ref>"
       Optionnel : kind ("VOICE" | "VIDEO") pour ajuster les permissions
       (par défaut on autorise publish/subscribe audio + video).
    """
    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)

    uid = int(request.api_user_id)
    user = User.objects.filter(pk=uid).first()
    if not user:
        return JsonResponse({"error": "user_not_found"}, status=404)

    conversation_id = payload.get("conversation_id")
    reservation_reference = (payload.get("reservation_reference") or "").strip()

    room_name: str = ""
    role = "user"

    if conversation_id is not None:
        try:
            cid = int(conversation_id)
        except (TypeError, ValueError):
            return JsonResponse({"error": "invalid_conversation_id"}, status=400)
        conv = (
            Conversation.objects
            .select_related("reservation")
            .filter(pk=cid).first()
        )
        if not conv:
            return JsonResponse({"error": "conversation_not_found"}, status=404)
        res = conv.reservation
        if not res:
            return JsonResponse({"error": "conversation_orphan"}, status=400)
        is_client = res.client_user_id == uid
        is_prest = bool(
            res.assigned_provider
            and res.assigned_provider.user_id == uid
        )
        if not (is_client or is_prest):
            return JsonResponse({"error": "forbidden"}, status=403)
        room_name = f"chat_conv_{cid}"
        role = "client" if is_client else "prestataire"
    elif reservation_reference:
        res = Reservation.objects.filter(reference=reservation_reference).first()
        if not res:
            return JsonResponse({"error": "reservation_not_found"}, status=404)
        is_client = res.client_user_id == uid
        is_prest = bool(
            res.assigned_provider
            and res.assigned_provider.user_id == uid
        )
        if not (is_client or is_prest):
            return JsonResponse({"error": "forbidden"}, status=403)
        room_name = f"res_{reservation_reference}"
        role = "client" if is_client else "prestataire"
    else:
        return JsonResponse(
            {"error": "conversation_id_or_reservation_required"},
            status=400,
        )

    token = generate_access_token(
        identity=_identity_for(uid, role),
        name=_user_display(user),
        room_name=room_name,
        ttl_seconds=3600,
    )
    return JsonResponse({
        "token": token,
        "url": livekit_url(),
        "room": room_name,
        "identity": _identity_for(uid, role),
    })


# ---------------------------------------------------------------------------
# POST /api/calls/initiate
# ---------------------------------------------------------------------------
@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client", "prestataire"])
def api_call_initiate(request):
    """Démarre un appel. Body JSON :
       - reservation_reference (str)  ← requis : restreint à un binôme client/presta
       - kind                 : "VOICE" | "VIDEO"  (défaut VOICE)
    """
    try:
        payload = json.loads(request.body.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return JsonResponse({"error": "invalid_json"}, status=400)

    reference = str(payload.get("reservation_reference") or "").strip()
    if not reference:
        return JsonResponse({"error": "reservation_required"}, status=400)

    kind_raw = str(payload.get("kind", "VOICE")).upper()
    kind = Call.Kind.VIDEO if kind_raw == "VIDEO" else Call.Kind.VOICE

    res = Reservation.objects.filter(reference=reference).first()
    if not res:
        return JsonResponse({"error": "reservation_not_found"}, status=404)

    uid = int(request.api_user_id)
    is_client = res.client_user_id == uid
    is_prest = bool(
        res.assigned_provider
        and res.assigned_provider.user_id
        and res.assigned_provider.user_id == uid
    )
    if not (is_client or is_prest):
        return JsonResponse({"error": "forbidden"}, status=403)

    callee_id = (
        res.assigned_provider.user_id
        if is_client
        else res.client_user_id
    )
    if not callee_id:
        return JsonResponse({"error": "no_callee"}, status=400)

    caller = User.objects.filter(pk=uid).first()
    callee = User.objects.filter(pk=callee_id).first()
    if not (caller and callee):
        return JsonResponse({"error": "user_not_found"}, status=404)

    # Anti-spam : empêcher 2 appels RINGING actifs entre les mêmes parties
    active = Call.objects.filter(
        caller=caller, callee=callee, status=Call.Status.RINGING
    ).first()
    if active and (timezone.now() - active.started_at) < timedelta(seconds=60):
        # Renvoyer l'appel actif (le client peut juste rejoindre la même room)
        token = generate_access_token(
            identity=_identity_for(caller.pk, "client" if is_client else "prestataire"),
            name=_user_display(caller),
            room_name=active.room_name,
        )
        return JsonResponse({
            "call": _serialize(active),
            "token": token,
            "resumed": True,
        })

    room = new_room_name()
    call = Call.objects.create(
        reservation=res,
        caller=caller,
        callee=callee,
        room_name=room,
        kind=kind,
        status=Call.Status.RINGING,
    )

    # Token pour l'appelant
    caller_role = "client" if is_client else "prestataire"
    token = generate_access_token(
        identity=_identity_for(caller.pk, caller_role),
        name=_user_display(caller),
        room_name=room,
    )

    # FCM ring au destinataire
    _schedule(
        [callee_id],
        f"Appel {'vidéo' if kind == Call.Kind.VIDEO else 'audio'} entrant",
        f"{_user_display(caller)} vous appelle (réservation {res.reference})",
        {
            "type": "call.incoming",
            "call_id": str(call.pk),
            "room_name": room,
            "kind": kind,
            "caller_id": str(caller.pk),
            "caller_name": _user_display(caller),
            "reservation_reference": res.reference,
            # High priority pour Android — sonnerie même app fermée
            "android_channel_id": "babifix_calls",
            "priority": "high",
        },
    )

    logger.info(
        "Call %s initiated by %s → %s (room=%s, kind=%s)",
        call.pk,
        caller.pk,
        callee.pk,
        room,
        kind,
    )
    return JsonResponse({"call": _serialize(call), "token": token})


# ---------------------------------------------------------------------------
# POST /api/calls/<id>/answer
# ---------------------------------------------------------------------------
@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client", "prestataire"])
def api_call_answer(request, call_id):
    call = Call.objects.filter(pk=call_id).first()
    if not call:
        return JsonResponse({"error": "not_found"}, status=404)

    uid = int(request.api_user_id)
    if call.callee_id != uid:
        return JsonResponse({"error": "forbidden"}, status=403)

    if call.status != Call.Status.RINGING:
        return JsonResponse(
            {"error": "invalid_state", "status": call.status}, status=409
        )

    call.status = Call.Status.ANSWERED
    call.answered_at = timezone.now()
    call.save(update_fields=["status", "answered_at"])

    role = "client" if call.callee.babifix_reservations_as_client.exists() else "prestataire"
    # On affecte une identity stable basée sur le rôle vis-à-vis de la réservation
    callee_role = (
        "client"
        if (call.reservation and call.reservation.client_user_id == uid)
        else "prestataire"
    )
    token = generate_access_token(
        identity=_identity_for(uid, callee_role),
        name=_user_display(call.callee),
        room_name=call.room_name,
    )

    _schedule(
        [call.caller_id],
        "Appel accepté",
        f"{_user_display(call.callee)} a décroché",
        {
            "type": "call.answered",
            "call_id": str(call.pk),
            "room_name": call.room_name,
        },
    )

    return JsonResponse({"call": _serialize(call), "token": token})


# ---------------------------------------------------------------------------
# POST /api/calls/<id>/reject
# ---------------------------------------------------------------------------
@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client", "prestataire"])
def api_call_reject(request, call_id):
    call = Call.objects.filter(pk=call_id).first()
    if not call:
        return JsonResponse({"error": "not_found"}, status=404)

    uid = int(request.api_user_id)
    if call.callee_id != uid:
        return JsonResponse({"error": "forbidden"}, status=403)

    if call.status != Call.Status.RINGING:
        return JsonResponse(
            {"error": "invalid_state", "status": call.status}, status=409
        )

    call.status = Call.Status.REJECTED
    call.ended_at = timezone.now()
    call.save(update_fields=["status", "ended_at"])

    _schedule(
        [call.caller_id],
        "Appel refusé",
        f"{_user_display(call.callee)} n'a pas pris l'appel.",
        {"type": "call.rejected", "call_id": str(call.pk)},
    )

    return JsonResponse({"call": _serialize(call)})


# ---------------------------------------------------------------------------
# POST /api/calls/<id>/end
# ---------------------------------------------------------------------------
@csrf_exempt
@require_http_methods(["POST"])
@require_api_auth(["client", "prestataire"])
def api_call_end(request, call_id):
    call = Call.objects.filter(pk=call_id).first()
    if not call:
        return JsonResponse({"error": "not_found"}, status=404)

    uid = int(request.api_user_id)
    if uid not in (call.caller_id, call.callee_id):
        return JsonResponse({"error": "forbidden"}, status=403)

    if call.status in {Call.Status.ENDED, Call.Status.REJECTED, Call.Status.MISSED}:
        return JsonResponse({"call": _serialize(call)})

    now = timezone.now()
    call.ended_at = now
    # Si l'appel n'avait jamais été décroché et c'est le caller qui raccroche → CANCELLED.
    # Si c'est le callee et statut RINGING → REJECTED.
    if call.status == Call.Status.RINGING:
        if uid == call.caller_id:
            call.status = Call.Status.CANCELLED
        else:
            call.status = Call.Status.REJECTED
    else:
        call.status = Call.Status.ENDED
        if call.answered_at:
            call.duration_seconds = int((now - call.answered_at).total_seconds())

    call.save(update_fields=["status", "ended_at", "duration_seconds"])

    other_id = call.callee_id if uid == call.caller_id else call.caller_id
    _schedule(
        [other_id],
        "Appel terminé",
        f"L'appel s'est terminé ({call.duration_seconds}s).",
        {
            "type": "call.ended",
            "call_id": str(call.pk),
            "duration_seconds": str(call.duration_seconds),
        },
    )
    return JsonResponse({"call": _serialize(call)})


# ---------------------------------------------------------------------------
# GET /api/calls/<id>
# ---------------------------------------------------------------------------
@csrf_exempt
@require_http_methods(["GET"])
@require_api_auth(["client", "prestataire", "admin"])
def api_call_detail(request, call_id):
    call = Call.objects.filter(pk=call_id).first()
    if not call:
        return JsonResponse({"error": "not_found"}, status=404)

    uid = int(request.api_user_id)
    if request.api_role != "admin" and uid not in (call.caller_id, call.callee_id):
        return JsonResponse({"error": "forbidden"}, status=403)

    return JsonResponse({"call": _serialize(call)})


# ---------------------------------------------------------------------------
# GET /api/calls/history
# ---------------------------------------------------------------------------
@csrf_exempt
@require_http_methods(["GET"])
@require_api_auth(["client", "prestataire"])
def api_call_history(request):
    uid = int(request.api_user_id)
    from django.db.models import Q

    qs = (
        Call.objects.filter(Q(caller_id=uid) | Q(callee_id=uid))
        .select_related("caller", "callee", "reservation")
        .order_by("-started_at")[:30]
    )
    return JsonResponse({"calls": [_serialize(c) for c in qs]})
