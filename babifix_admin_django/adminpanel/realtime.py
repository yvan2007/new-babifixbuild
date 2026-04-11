"""
Diffusion temps réel vers le panel admin (WebSocket / Django Channels).
"""
from __future__ import annotations

from typing import Any

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer

ADMIN_EVENTS_GROUP = 'babifix_admin_events'
"""Tous les apps client + prestataire connectés en WebSocket (JWT)."""
CLIENT_EVENTS_GROUP = 'babifix_client_events'


def prestataire_user_group(user_id: int) -> str:
    return f'babifix_prestataire_{int(user_id)}'


def broadcast_prestataire_user(
    user_id: int, event_type: str, payload: dict[str, Any] | None = None
) -> None:
    """Événement temps réel vers l’app prestataire (WebSocket JWT sur ce groupe)."""
    layer = get_channel_layer()
    if layer is None:
        return
    payload = payload or {}
    async_to_sync(layer.group_send)(
        prestataire_user_group(user_id),
        {
            'type': 'prestataire.notify',
            'event_type': event_type,
            'payload': payload,
        },
    )


def broadcast_client_event(event_type: str, payload: dict[str, Any] | None = None) -> None:
    """Prestataire approuvé, nouvelle actualité, etc. — apps Flutter client & prestataire."""
    layer = get_channel_layer()
    if layer is None:
        return
    payload = payload or {}
    async_to_sync(layer.group_send)(
        CLIENT_EVENTS_GROUP,
        {
            'type': 'client.notify',
            'event_type': event_type,
            'payload': payload,
        },
    )


def broadcast_admin_event(event_type: str, payload: dict[str, Any] | None = None) -> None:
    """
    Envoie un événement à tous les navigateurs connectés sur /ws/admin/events/
    (utilisateurs staff authentifiés uniquement, filtré dans le consumer).
    """
    layer = get_channel_layer()
    if layer is None:
        return
    payload = payload or {}
    async_to_sync(layer.group_send)(
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
    """Payload WebSocket / FCM — prestataire visible côté client."""
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
    return {'id': c.pk, 'nom': c.nom, 'actif': c.actif}


def serialize_notification(n) -> dict[str, Any]:
    return {'id': n.pk, 'title': n.title}
