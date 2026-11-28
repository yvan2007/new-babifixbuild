"""
Diffusion temps réel vers le panel admin (WebSocket / Django Channels).
"""
from __future__ import annotations

import logging
from typing import Any

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer

logger = logging.getLogger('adminpanel.realtime')

ADMIN_EVENTS_GROUP = 'babifix_admin_events'
"""Tous les apps client + prestataire connectés en WebSocket (JWT)."""
CLIENT_EVENTS_GROUP = 'babifix_client_events'


def _safe_group_send(group_name: str, message: dict[str, Any]) -> None:
    """Envoie sur un groupe Channels sans jamais propager une coupure Redis en HTTP 500."""
    try:
        layer = get_channel_layer()
        if layer is None:
            return
        async_to_sync(layer.group_send)(group_name, message)
    except Exception as exc:
        logger.warning('Broadcast Channels ignore (%s) : %s', group_name, exc)


def prestataire_user_group(user_id: int) -> str:
    return f'babifix_prestataire_{int(user_id)}'


def client_user_group(user_id: int) -> str:
    """Groupe WS dédié à UN client précis (pour ses réservations)."""
    return f'babifix_client_{int(user_id)}'


def broadcast_prestataire_user(
    user_id: int, event_type: str, payload: dict[str, Any] | None = None
) -> None:
    """Événement temps réel vers l’app prestataire (WebSocket JWT sur ce groupe)."""
    payload = payload or {}
    _safe_group_send(
        prestataire_user_group(user_id),
        {
            'type': 'prestataire.notify',
            'event_type': event_type,
            'payload': payload,
        },
    )


def broadcast_client_user(
    user_id: int, event_type: str, payload: dict[str, Any] | None = None
) -> None:
    """
    Événement temps réel vers UN client précis : par exemple sa réservation
    qui change de statut. Le client doit s'être connecté à
    `/ws/client/events/` (ClientEventsConsumer s'abonne automatiquement
    au groupe `babifix_client_<uid>` pour les events ciblés).
    """
    payload = payload or {}
    _safe_group_send(
        client_user_group(user_id),
        {
            'type': 'client.notify',
            'event_type': event_type,
            'payload': payload,
        },
    )


def broadcast_client_event(event_type: str, payload: dict[str, Any] | None = None) -> None:
    """Prestataire approuvé, nouvelle actualité, etc. : apps Flutter client & prestataire."""
    payload = payload or {}
    _safe_group_send(
        CLIENT_EVENTS_GROUP,
        {
            'type': 'client.notify',
            'event_type': event_type,
            'payload': payload,
        },
    )


def broadcast_chat_message(conv_id: int, message_payload: dict[str, Any]) -> None:
    """
    Broadcast un message chat à tous les WS connectés sur la conversation
    (client + prestataire). Appelé depuis le handler REST quand un message
    arrive via POST /api/messages/send pour que les apps reçoivent l'event
    temps réel et affichent une bannière toast + son.
    """
    _safe_group_send(
        f"chat_{conv_id}",
        {
            "type": "chat_message",
            "message": message_payload,
        },
    )


def broadcast_admin_event(event_type: str, payload: dict[str, Any] | None = None) -> None:
    """
    Envoie un événement à tous les navigateurs connectés sur /ws/admin/events/
    (utilisateurs staff authentifiés uniquement, filtré dans le consumer).
    """
    payload = payload or {}
    _safe_group_send(
        ADMIN_EVENTS_GROUP,
        {
            'type': 'admin.notify',
            'event_type': event_type,
            'payload': payload,
        },
    )


def serialize_reservation(r) -> dict[str, Any]:
    return {
        'id': r.pk,
        'reference': r.reference,
        'statut': r.statut,
        'client': r.client,
        'prestataire': r.prestataire,
        'payment_type': getattr(r, 'payment_type', ''),
        'mobile_money_operator': getattr(r, 'mobile_money_operator', '') or '',
        'cash_flow_status': getattr(r, 'cash_flow_status', '') or '',
    }


def serialize_provider(p) -> dict[str, Any]:
    return {
        'id': p.pk,
        'nom': p.nom,
        'statut': p.statut,
        'specialite': p.specialite,
    }


def serialize_provider_public(p) -> dict[str, Any]:
    """Payload WebSocket / FCM : prestataire visible côté client."""
    cat = getattr(p, 'category', None)
    return {
        'id': int(p.pk),
        'nom': p.nom,
        'specialite': p.specialite,
        'ville': p.ville,
        'statut': p.statut,
        'is_approved': bool(getattr(p, 'is_approved', False)),
        'tarif_horaire': float(p.tarif_horaire) if p.tarif_horaire is not None else None,
        'disponible': p.disponible,
        'average_rating': float(p.average_rating or 0),
        'rating_count': int(p.rating_count or 0),
        'photo_url': (p.photo_portrait_url or '').strip(),
        'category_id': int(cat.pk) if cat else None,
        'category_nom': cat.nom if cat else '',
        'category_icone_url': (cat.icone_url or '').strip() if cat else '',
    }


def serialize_actualite(a) -> dict[str, Any]:
    return {
        'id': int(a.pk),
        'titre': a.titre,
        'description': a.description,
        'publie': a.publie,
        'categorie_tag': a.categorie_tag,
        'icone_key': a.icone_key or '',
        'date_publication': a.date_publication.isoformat(),
    }


def serialize_dispute(d) -> dict[str, Any]:
    return {
        'id': d.pk,
        'reference': d.reference,
        'decision': d.decision,
        'priorite': d.priorite,
    }


def serialize_payment(p) -> dict[str, Any]:
    return {
        'id': p.pk,
        'reference': p.reference,
        'etat': p.etat,
        'valide_par_admin': p.valide_par_admin,
        'type_paiement': p.type_paiement,
    }


def serialize_category(c) -> dict[str, Any]:
    return {
        'id': c.pk,
        'nom': c.nom,
        'actif': c.actif,
        'regime_kyc': getattr(c, 'regime_kyc', 'STANDARD_TERRAIN'),
        'groupe': getattr(c, 'groupe', ''),
    }


def invalidate_categories_cache() -> None:
    """Invalidates the public categories cache so next request fetches fresh data."""
    try:
        from .perf_signals import invalidate_public_catalog_cache

        invalidate_public_catalog_cache()
    except Exception:
        pass


def invalidate_providers_cache() -> None:
    """Invalidates the public providers cache so next request fetches fresh data."""
    try:
        from .perf_signals import invalidate_public_catalog_cache

        invalidate_public_catalog_cache()
    except Exception:
        pass


def serialize_notification(n) -> dict[str, Any]:
    return {'id': n.pk, 'title': n.title}
