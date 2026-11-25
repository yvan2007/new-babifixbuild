"""
Planifie les notifications push (FCM) après commit DB : client / prestataire.
"""

from __future__ import annotations

import threading
from typing import Any

from django.db import transaction

from .models import Message, Notification, Provider, UserProfile


def _create_db_notif(
    user_id: int | None,
    title: str,
    body: str,
    notif_type: str,
    reference: str = "",
    *,
    skip_fcm: bool = True,
    dedup_unread: bool = False,
) -> Notification | None:
    """Cree une Notification DB persistante (optionnellement dedoublonnee si non lue)."""
    clean_title = (_strip_brand(title) or title or "Notification").strip()[:200]
    clean_ref = (reference or "").strip()[:60]
    clean_body = (body or "").strip()
    try:
        if dedup_unread and clean_ref:
            existing = Notification.objects.filter(
                user_id=user_id,
                notif_type=notif_type,
                reference=clean_ref,
                lu=False,
            ).first()
            if existing is not None:
                existing.title = clean_title
                existing.body = clean_body
                existing.time = "A l instant"
                existing._skip_fcm = True
                existing.save(update_fields=["title", "body", "time"])
                return existing
        n = Notification(
            user_id=user_id,
            title=clean_title,
            body=clean_body,
            time="A l instant",
            notif_type=notif_type,
            reference=clean_ref,
            lu=False,
        )
        n._skip_fcm = skip_fcm
        n.save()
        return n
    except Exception:
        return None


def _strip_brand(title: str) -> str:
    """Retire un préfixe de marque déjà présent pour éviter le doublon."""
    t = (title or "").lstrip()
    for prefix in (
        "BABIFIX PRO ·", "BABIFIX PRO :", "BABIFIX PRO -",
        "BABIFIX ·", "BABIFIX :", "BABIFIX -", "BABIFIX",
    ):
        if t.startswith(prefix):
            return t[len(prefix):].lstrip(" ·:-").strip()
    return t.strip()


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

        # Brander + cibler la BONNE app selon le RÔLE de chaque destinataire :
        #  - client      → « BABIFIX … »      + jetons app=client
        #  - prestataire → « BABIFIX PRO … »  + jetons app=pro
        #  - admin/autre → titre inchangé, tous les jetons
        roles = dict(
            UserProfile.objects.filter(user_id__in=ids).values_list("user_id", "role")
        )
        groups: dict[str | None, list[int]] = {}
        for uid in ids:
            role = roles.get(uid)
            if role == UserProfile.Role.PRESTATAIRE:
                key = "pro"
            elif role == UserProfile.Role.CLIENT:
                key = "client"
            else:
                key = None
            groups.setdefault(key, []).append(uid)

        base = _strip_brand(title)
        for app_key, group_ids in groups.items():
            if app_key == "pro":
                branded = f"BABIFIX PRO · {base}" if base else "BABIFIX PRO"
            elif app_key == "client":
                branded = f"BABIFIX · {base}" if base else "BABIFIX"
            else:
                branded = title  # admin / inconnu : on garde tel quel
            send_push_to_user_ids(group_ids, branded, body, data, app=app_key)

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
    # On ne notifie QUE sur un vrai changement de STATUT (pas sur les mises à
    # jour internes : cash_flow_status, montant_restant, etc.) → bien moins de
    # messages, plus professionnel.
    if not created and (update_fields is not None and "statut" not in update_fields):
        return

    if created:
        uids = _reservation_prestataire_user_ids(instance)
        is_urgent = getattr(instance, "is_urgent", False)
        notif_title = "Demande urgente !" if is_urgent else "Nouvelle demande client"
        zone_txt = (
            getattr(instance, "address_ville", "")
            or getattr(instance, "address_quartier", "")
            or getattr(instance, "address_label", "")
            or "Abidjan"
        )
        sujet_txt = getattr(instance, "title", "") or getattr(instance, "prestataire", "") or "Service"
        notif_body = f"Reservation {instance.reference} ({sujet_txt}) a {zone_txt}."
        _create_db_notif(
            None,
            f"Nouvelle demande client : {instance.reference}",
            notif_body,
            Notification.NotifType.RESERVATION,
            reference=instance.reference,
            skip_fcm=True,
            dedup_unread=True,
        )
        for uid in uids:
            _create_db_notif(
                uid,
                notif_title,
                notif_body,
                Notification.NotifType.RESERVATION,
                reference=instance.reference,
                skip_fcm=True,
            )
        _schedule(
            uids,
            "BABIFIX · Demande urgente !" if is_urgent else "BABIFIX · Nouvelle reservation",
            notif_body,
            {
                "type": "reservation.created",
                "reference": instance.reference,
                "is_urgent": "true" if is_urgent else "false",
                "route": f"/prestataire/requests/{instance.reference}",
            },
        )
        return

    ref = instance.reference
    client_uid = instance.client_user_id
    presta_uids = [
        u
        for u in ([instance.prestataire_user_id] + _reservation_prestataire_user_ids(instance))
        if u
    ]

    spec = {
        "DEVIS_ENVOYE": ("BABIFIX · Devis recu", f"Vous avez recu un devis pour {ref}.", "client"),
        "DEVIS_ACCEPTE": ("BABIFIX · Devis accepte", f"Le client a accepte votre devis ({ref}). Vous pouvez demarrer.", "presta"),
        "Confirmee": ("BABIFIX · Demande confirmee", f"La reservation {ref} est confirmee.", "client"),
        "INTERVENTION_EN_COURS": ("BABIFIX · Intervention demarree", f"L'intervention pour {ref} a commence.", "client"),
        "En attente client": ("BABIFIX · Prestation terminee", f"Confirmez la prestation {ref} pour finaliser.", "client"),
        "Terminee": ("BABIFIX · Prestation confirmee", f"Le client a confirme {ref}. Place au paiement.", "presta"),
        "Annulee": ("BABIFIX · Reservation annulee", f"La reservation {ref} a ete annulee.", "both"),
    }
    entry = spec.get(instance.statut)
    if not entry:
        return
    title, body, who = entry
    if who == "client":
        targets = [client_uid] if client_uid else []
    elif who == "presta":
        targets = presta_uids
    else:
        targets = ([client_uid] if client_uid else []) + presta_uids
    targets = sorted({int(u) for u in targets if u})
    if not targets:
        return
    for uid in targets:
        _create_db_notif(
            uid,
            title,
            body,
            Notification.NotifType.RESERVATION,
            reference=ref,
            skip_fcm=True,
        )
    _schedule(
        targets,
        title,
        body,
        {
            "type": "reservation.updated",
            "reference": instance.reference,
            "statut": instance.statut,
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
            "BABIFIX · Nouveau prestataire",
            f"{instance.nom} · {instance.specialite}",
            {"type": "provider.approved", "provider_id": str(instance.pk)},
        )

    if created:
        ville_txt = getattr(instance, "ville", "") or "Abidjan"
        _create_db_notif(
            None,
            f"Nouvelle demande prestataire : {instance.nom}",
            f"Metier : {instance.specialite or 'General'} · Ville : {ville_txt}",
            Notification.NotifType.VALIDATION,
            reference=f"PROV-{instance.pk}",
            skip_fcm=True,
            dedup_unread=True,
        )

    if not instance.user_id:
        return
    if not created and update_fields is not None and "statut" not in update_fields:
        return
    reason = (instance.refusal_reason or "").strip()
    if instance.statut == "Valide":
        title = "BABIFIX · Demande acceptee"
        body = "Votre dossier prestataire est valide. Accedez a votre tableau de bord."
    elif instance.statut == "Refuse":
        title = "BABIFIX · Demande refusee"
        body = (
            reason
            if reason
            else "Votre dossier a ete refuse. Consultez le motif dans l app."
        )
    else:
        title = "BABIFIX · Votre compte prestataire"
        body = f"Statut : {instance.statut}"

    if instance.statut in ("Valide", "Refuse"):
        _create_db_notif(
            instance.user_id,
            title,
            body,
            Notification.NotifType.VALIDATION,
            reference=f"PROV-{instance.pk}",
            skip_fcm=True,
        )

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


def on_dispute_change(
    instance, created: bool, update_fields: frozenset[str] | None
) -> None:
    """Notifie Admin + Client + Prestataire (DB + WS + FCM) sur litige."""
    from . import realtime

    if not created and update_fields is not None and "decision" not in update_fields:
        return

    res_ref = ""
    client_uid = None
    presta_uid = None
    try:
        if instance.reservation_id and instance.reservation:
            res_ref = instance.reservation.reference or ""
            client_uid = instance.reservation.client_user_id
            presta_uid = instance.reservation.prestataire_user_id
    except Exception:
        pass
    try:
        if not presta_uid and instance.prestataire:
            presta_uid = (
                Provider.objects.filter(nom=instance.prestataire)
                .values_list("user_id", flat=True)
                .first()
            )
    except Exception:
        pass

    dispute_ref = instance.reference or f"LIT-{instance.pk}"
    if created:
        title = f"Nouveau litige {dispute_ref}"
        body = f"{instance.motif[:140]}" + (f" ({res_ref})" if res_ref else "")
        _create_db_notif(
            None,
            f"Nouveau litige {dispute_ref}" + (f" : {res_ref}" if res_ref else ""),
            body,
            Notification.NotifType.DISPUTE,
            reference=dispute_ref,
            skip_fcm=True,
            dedup_unread=True,
        )
        ws_event = "dispute.created"
    else:
        title = f"Litige mis a jour ({dispute_ref})"
        body = f"Decision : {instance.decision}"
        _create_db_notif(
            None,
            title,
            body,
            Notification.NotifType.DISPUTE,
            reference=dispute_ref,
            skip_fcm=True,
        )
        ws_event = "dispute.updated"

    ws_payload = {
        "reference": dispute_ref,
        "reservation_reference": res_ref,
        "decision": instance.decision,
        "motif": (instance.motif or "")[:140],
    }
    targets = sorted({int(u) for u in (client_uid, presta_uid) if u})
    for uid in targets:
        _create_db_notif(
            uid,
            title,
            body,
            Notification.NotifType.DISPUTE,
            reference=dispute_ref,
            skip_fcm=True,
        )
    try:
        if client_uid:
            realtime.broadcast_client_user(client_uid, ws_event, ws_payload)
        if presta_uid:
            realtime.broadcast_prestataire_user(presta_uid, ws_event, ws_payload)
    except Exception:
        pass

    if targets:
        _schedule(
            targets,
            f"BABIFIX · {title}",
            body,
            {
                "type": ws_event,
                "reference": dispute_ref,
                "reservation_reference": res_ref,
                "is_urgent": "true" if created else "false",
                "route": f"/reservation/{res_ref}" if res_ref else "/litiges",
            },
        )


def on_metier_propose_created(instance) -> None:
    """Cree une alerte Admin lorsqu un nouveau metier est suggere."""
    _create_db_notif(
        None,
        f"Suggestion de metier : {instance.nom}",
        f"Proposition en attente ({instance.votes} vote(s)).",
        Notification.NotifType.GENERAL,
        reference=f"METIER-{instance.pk}",
        skip_fcm=True,
        dedup_unread=True,
    )


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
        "BABIFIX · Actualité",
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
    title = "BABIFIX · Nouveau message"
    body = (
        f"{peer_label} · réservation {ref}"
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
    if recipient_id:
        _create_db_notif(
            recipient_id,
            title,
            body,
            Notification.NotifType.MESSAGE,
            reference=ref or f"CONV-{conv.pk}",
            skip_fcm=True,
        )
    _schedule([recipient_id], title, body, data)
    try:
        ws_payload = {
            "conversation_id": int(conv.pk),
            "sender_id": int(instance.sender_id),
            "reservation_reference": ref,
        }
        if recipient_id:
            if conv.client_id == instance.sender_id:
                realtime.broadcast_prestataire_user(recipient_id, "chat.message", ws_payload)
            else:
                realtime.broadcast_client_user(recipient_id, "chat.message", ws_payload)
    except Exception:
        pass


def on_notification_created(instance) -> None:
    """Push FCM vers l'utilisateur ciblé (ou tous si global)."""
    ids: list[int | None] = []
    if instance.user_id:
        ids = [instance.user_id]
    elif (instance.notif_type or '') == 'broadcast':
        # Broadcast VOLONTAIRE (annonce admin « push à tous ») → utilisateurs actifs.
        ids = list(
            UserProfile.objects.filter(active=True).values_list('user_id', flat=True)
        )
    else:
        # Notification INTERNE admin (log d'activité : « Statut prestataire mis à
        # jour », etc.) sans destinataire → on NE blaste PAS tous les utilisateurs
        # par FCM. Avant : chaque client ET prestataire recevait ce message
        # générique pour toute action admin. On reste silencieux (panneau admin
        # seulement).
        return
    _schedule(
        ids,
        instance.title or 'BABIFIX · Notification',
        instance.body or '',
        {
            'type': 'notification',
            'notification_id': str(instance.pk),
            'title': instance.title or '',
            'body': instance.body or '',
            'notif_type': instance.notif_type or '',
        },
    )


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
        "BABIFIX · Nouvel avis",
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
    clean_uids = sorted({int(u) for u in uids if u})
    pay_title = f"Paiement {instance.reference}"
    pay_body = f"{instance.reference} · {instance.etat}"
    if created or (instance.etat in ("Confirme", "Valide", "Paye", "Libere")):
        _create_db_notif(
            None,
            pay_title,
            pay_body + (f" ({ref})" if ref else ""),
            Notification.NotifType.PAYMENT,
            reference=instance.reference,
            skip_fcm=True,
            dedup_unread=True,
        )
    for uid in clean_uids:
        _create_db_notif(
            uid,
            pay_title,
            pay_body,
            Notification.NotifType.PAYMENT,
            reference=instance.reference,
            skip_fcm=True,
        )
    _schedule(
        clean_uids,
        "BABIFIX · Paiement",
        pay_body,
        {
            "type": "payment.updated",
            "reference": instance.reference,
            "reservation_reference": ref,
            "route": f"/reservation/{ref}" if ref else "/client/payments",
        },
    )
