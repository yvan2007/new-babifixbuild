"""
Planifie les notifications push (FCM) après commit DB — client / prestataire.
"""

from __future__ import annotations

import threading
from typing import Any

from django.db import transaction

from .models import Message, Provider, UserProfile


def _schedule(
    user_ids: list[int | None],
    title: str,
    body: str,
    data: dict[str, Any] | None = None,
) -> None:
    ids = sorted({int(u) for u in user_ids if u})
    if not ids:
        return

    def _run() -> None:
        from .fcm_backend import send_push_to_user_ids

        send_push_to_user_ids(ids, title, body, data)

    transaction.on_commit(lambda: threading.Thread(target=_run, daemon=True).start())


def _all_client_user_ids() -> list[int]:
    return list(
        UserProfile.objects.filter(
            role=UserProfile.Role.CLIENT, active=True
        ).values_list("user_id", flat=True)
    )


def _schedule_all_clients_push(
    title: str, body: str, data: dict[str, Any] | None = None
) -> None:
    _schedule(_all_client_user_ids(), title, body, data)


def _schedule_clients_and_prestataires_push(
    title: str, body: str, data: dict[str, Any] | None = None
) -> None:
    ids = list(
        UserProfile.objects.filter(
            role__in=(UserProfile.Role.CLIENT, UserProfile.Role.PRESTATAIRE),
            active=True,
        ).values_list("user_id", flat=True)
    )
    _schedule(ids, title, body, data)


def _should_broadcast_provider_to_clients(
    instance: Provider, created: bool, update_fields: frozenset[str] | None
) -> bool:
    if instance.statut != Provider.Status.VALID:
        return False
    if created:
        return True
    if update_fields is not None and (
        "statut" in update_fields or "disponible" in update_fields
    ):
        return True
    return False


def _reservation_prestataire_user_ids(r) -> list[int | None]:
    ids: list[int | None] = []
    if r.prestataire_user_id:
        ids.append(r.prestataire_user_id)
    if r.assigned_provider_id:
        from .models import Provider

        p = Provider.objects.filter(pk=r.assigned_provider_id).only("user_id").first()
        if p and p.user_id:
            ids.append(p.user_id)
    return ids


def on_reservation_change(
    instance, created: bool, update_fields: frozenset[str] | None
) -> None:
    watch = {"statut", "cash_flow_status", "montant", "title", "prestataire", "client"}
    if not created and update_fields is not None and not (set(update_fields) & watch):
        return

    if created:
        uids = _reservation_prestataire_user_ids(instance)
        is_urgent = getattr(instance, "is_urgent", False)
        _schedule(
            uids,
            "🚨 BABIFIX — Demande urgente !" if is_urgent else "BABIFIX — Nouvelle réservation",
            f"Demande {instance.reference} — {instance.statut}",
            {
                "type": "reservation.created",
                "reference": instance.reference,
                "is_urgent": "true" if is_urgent else "false",
                "route": f"/prestataire/requests/{instance.reference}",
            },
        )
        return

    uids = [instance.client_user_id, instance.prestataire_user_id]
    uids.extend(_reservation_prestataire_user_ids(instance))
    _schedule(
        uids,
        "BABIFIX — Réservation",
        f"{instance.reference} — {instance.statut}",
        {
            "type": "reservation.updated",
            "reference": instance.reference,
            "statut": instance.statut,
            "cash_flow": instance.cash_flow_status or "",
            "route": f"/reservation/{instance.reference}",
        },
    )


def on_provider_change(
    instance, created: bool, update_fields: frozenset[str] | None
) -> None:
    from . import realtime

    if _should_broadcast_provider_to_clients(instance, created, update_fields):
        pub = realtime.serialize_provider_public(instance)
        try:
            # Broadcast disponibilitéchangée en temps réel
            if (
                not created
                and update_fields is not None
                and "disponible" in update_fields
            ):
                realtime.broadcast_client_event(
                    "provider.availability_changed",
                    {
                        "provider_id": instance.pk,
                        "disponible": instance.disponible,
                    },
                )
            else:
                realtime.broadcast_client_event("provider.approved", pub)
        except Exception:
            pass
        _schedule_all_clients_push(
            "BABIFIX — Nouveau prestataire",
            f"{instance.nom} — {instance.specialite}",
            {"type": "provider.approved", "provider_id": str(instance.pk)},
        )

    if not instance.user_id:
        return
    if not created and update_fields is not None and "statut" not in update_fields:
        return
    reason = (instance.refusal_reason or "").strip()
    if instance.statut == "Valide":
        title = "BABIFIX — Demande acceptée"
        body = "Votre dossier prestataire est validé. Accédez à votre tableau de bord."
    elif instance.statut == "Refuse":
        title = "BABIFIX — Demande refusée"
        body = (
            reason
            if reason
            else "Votre dossier a été refusé. Consultez le motif dans l’app."
        )
    else:
        title = "BABIFIX — Votre compte prestataire"
        body = f"Statut : {instance.statut}"

    data = {
        "type": "provider.updated",
        "provider_id": str(instance.pk),
        "statut": instance.statut,
        "refusal_reason": reason,
        "route": "/prestataire/profile",
    }
    _schedule([instance.user_id], title, body, data)

    try:
        realtime.broadcast_prestataire_user(
            instance.user_id,
            "provider.updated",
            {
                "id": instance.pk,
                "statut": instance.statut,
                "refusal_reason": reason,
                "specialite": instance.specialite,
            },
        )
    except Exception:
        pass


def on_actualite_published(
    instance, created: bool, update_fields: frozenset[str] | None
) -> None:
    """Diffusion lorsque l’actualité est publiée (ou republiée avec changement)."""
    from . import realtime

    if not instance.publie:
        return
    if not created and update_fields is not None:
        if not ({"publie", "titre", "description"} & set(update_fields)):
            return
    payload = realtime.serialize_actualite(instance)
    try:
        realtime.broadcast_client_event("actualite.published", payload)
    except Exception:
        pass
    _schedule_clients_and_prestataires_push(
        "BABIFIX — Actualité",
        instance.titre[:120],
        {"type": "actualite.published", "actualite_id": str(instance.pk)},
    )


def on_chat_message_created(instance: Message) -> None:
    """Push + WebSocket : nouveau message (destinataire uniquement)."""
    from . import realtime

    conv = instance.conversation
    if conv.client_id == instance.sender_id:
        recipient_id = conv.prestataire_id
        peer_label = "Client"
    else:
        recipient_id = conv.client_id
        peer_label = "Prestataire"
    ref = ""
    try:
        if conv.reservation_id:
            from .models import Reservation

            r = (
                Reservation.objects.filter(pk=conv.reservation_id)
                .only("reference")
                .first()
            )
            if r:
                ref = r.reference
    except Exception:
        pass
    title = "BABIFIX — Nouveau message"
    body = (
        f"{peer_label} — réservation {ref}"
        if ref
        else f"Nouveau message de votre {peer_label.lower()}"
    )
    data = {
        "type": "chat.message",
        "conversation_id": str(conv.pk),
        "sender_id": str(instance.sender_id),
        "reservation_reference": ref,
        "route": f"/messages/{ref}" if ref else "/messages",
    }
    _schedule([recipient_id], title, body, data)
    try:
        realtime.broadcast_client_event(
            "chat.message",
            {
                "conversation_id": int(conv.pk),
                "sender_id": int(instance.sender_id),
                "reservation_reference": ref,
            },
        )
    except Exception:
        pass


def on_rating_change(instance, created: bool) -> None:
    if not created:
        return
    uid = None
    try:
        prov = instance.provider
        uid = prov.user_id if prov else None
    except Exception:
        pass
    if not uid:
        return
    _schedule(
        [uid],
        "BABIFIX — Nouvel avis",
        f"Note {instance.note}/5 sur une prestation",
        {
            "type": "rating.created",
            "reservation_id": str(instance.reservation_id),
            "route": "/prestataire/ratings",
        },
    )


def on_payment_change(
    instance, created: bool, update_fields: frozenset[str] | None
) -> None:
    watch = {"etat", "valide_par_admin", "montant", "type_paiement"}
    if not created and update_fields is not None and not (set(update_fields) & watch):
        return
    uids: list[int | None] = []
    if instance.reservation_id:
        from .models import Reservation

        res = (
            Reservation.objects.filter(pk=instance.reservation_id)
            .only("client_user_id", "prestataire_user_id")
            .first()
        )
        if res:
            uids.append(res.client_user_id)
            uids.append(res.prestataire_user_id)
    ref = instance.reservation.reference if instance.reservation_id else ""
    _schedule(
        uids,
        "BABIFIX — Paiement",
        f"{instance.reference} — {instance.etat}",
        {
            "type": "payment.updated",
            "reference": instance.reference,
            "reservation_reference": ref,
            "route": f"/reservation/{ref}" if ref else "/client/payments",
        },
    )
