"""ConversationService — fil unique par réservation (Phase C).

But : garantir qu'une réservation entre un client et un prestataire a UNE
seule conversation, et exposer des helpers pour y injecter :

- des cartes devis figées (`Message.Kind.DEVIS_CARD`) qui apparaissent
  comme un bloc dans le fil et restent référencées pour l'historique ;
- des événements système (`Message.Kind.SYSTEM`) à chaque étape du
  cycle (intervention démarrée, terminée, paiement reçu, confirmation…).

L'unicité de la conversation est garantie au niveau base via la
contrainte `OneToOneField` sur `Conversation.reservation`. Ce service est
le point d'entrée unique pour éviter de dupliquer la logique de création
dans toutes les vues.
"""

from __future__ import annotations

import logging
from typing import Optional

from django.db import IntegrityError, transaction

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Conversation
# ---------------------------------------------------------------------------
def get_or_create_conversation_for_reservation(reservation) -> Optional[object]:
    """Retourne (ou crée) l'unique conversation associée à une réservation.

    Requiert que la réservation ait à la fois un `client_user_id` et un
    `prestataire_user_id` (sinon retourne None).

    Sûr en concurrence : si une autre requête crée la conversation entre
    le SELECT et l'INSERT, on la récupère via le retry.
    """
    from adminpanel.models import Conversation

    if not reservation:
        return None

    client_user_id = getattr(reservation, "client_user_id", None)
    prestataire_user_id = getattr(reservation, "prestataire_user_id", None)
    if not prestataire_user_id and reservation.assigned_provider_id:
        # Fallback : récupérer via le Provider lié.
        prestataire_user_id = getattr(
            reservation.assigned_provider, "user_id", None
        )

    if not (client_user_id and prestataire_user_id):
        return None

    conv = Conversation.objects.filter(reservation=reservation).first()
    if conv:
        return conv

    try:
        with transaction.atomic():
            conv = Conversation.objects.create(
                client_id=client_user_id,
                prestataire_id=prestataire_user_id,
                reservation=reservation,
            )
        return conv
    except IntegrityError:
        # Race : une autre requête vient de la créer, on la relit.
        return Conversation.objects.filter(reservation=reservation).first()


# ---------------------------------------------------------------------------
# Injection devis & événements système
# ---------------------------------------------------------------------------
def _system_sender(reservation):
    """Le 'sender' d'un message système : on prend l'admin si possible,
    sinon le prestataire (le client ne doit jamais en être l'auteur)."""
    from django.contrib.auth.models import User

    admin = User.objects.filter(is_staff=True, is_active=True).first()
    if admin:
        return admin
    if reservation.prestataire_user_id:
        return User.objects.filter(pk=reservation.prestataire_user_id).first()
    return User.objects.filter(pk=reservation.client_user_id).first()


def post_devis_card(reservation, devis) -> Optional[object]:
    """Injecte (ou met à jour) une carte devis figée dans le fil.

    Idempotent : si une carte devis pour ce devis existe déjà, on ne la
    réinjecte pas (on conserve la trace originale).
    """
    from adminpanel.models import LigneDevis, Message

    conv = get_or_create_conversation_for_reservation(reservation)
    if conv is None:
        logger.warning(
            "post_devis_card: impossible de créer la conversation pour %s",
            reservation.reference,
        )
        return None

    # Anti-doublon : déjà publiée pour ce devis ?
    existing = Message.objects.filter(
        conversation=conv,
        kind=Message.Kind.DEVIS_CARD,
        payload_json__devis_id=devis.id,
    ).first()
    if existing:
        return existing

    lignes = [
        {
            "id": l.id,
            "type_ligne": l.type_ligne,
            "description": l.description,
            "quantite": l.quantite,
            "prix_unitaire": float(l.prix_unitaire),
            "total": float(l.total),
        }
        for l in LigneDevis.objects.filter(devis=devis)
    ]
    payload = {
        "devis_id": devis.id,
        "devis_reference": devis.reference,
        "diagnostic": devis.diagnostic,
        "date_proposee": (
            devis.date_proposee.isoformat() if devis.date_proposee else None
        ),
        "heure_debut": (
            devis.heure_debut.isoformat() if devis.heure_debut else None
        ),
        "heure_fin": devis.heure_fin.isoformat() if devis.heure_fin else None,
        "sous_total": float(devis.sous_total),
        "commission_rate": devis.commission_rate,
        "commission_montant": float(devis.commission_montant),
        "total_ttc": float(devis.total_ttc),
        "net_prestataire": float(devis.net_prestataire),
        "statut": devis.statut,
        "validite_jours": devis.validite_jours,
        "note_prestataire": devis.note_prestataire,
        "lignes": lignes,
    }
    sender = _system_sender(reservation)
    body = (
        f"Devis {devis.reference} accepté — total {int(devis.total_ttc)} F CFA."
    )
    return Message.objects.create(
        conversation=conv,
        sender=sender,
        body=body,
        kind=Message.Kind.DEVIS_CARD,
        payload_json=payload,
    )


def post_system_event(
    reservation,
    event_type: str,
    body: str,
    extra: Optional[dict] = None,
) -> Optional[object]:
    """Injecte un événement système dans le fil.

    `event_type` est libre mais on suggère :
    `intervention.started`, `intervention.finished`,
    `payment.received`, `funds.released`, `client.confirmed`.
    """
    from adminpanel.models import Message

    conv = get_or_create_conversation_for_reservation(reservation)
    if conv is None:
        return None

    payload = {"event_type": event_type, "reference": reservation.reference}
    if extra:
        payload.update(extra)

    sender = _system_sender(reservation)
    return Message.objects.create(
        conversation=conv,
        sender=sender,
        body=body[:5000],
        kind=Message.Kind.SYSTEM,
        payload_json=payload,
    )
