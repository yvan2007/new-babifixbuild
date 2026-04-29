"""
Tâches Celery BABIFIX — expiration automatique et SLA réservations.

Beat schedule à configurer dans settings.py :
    CELERY_BEAT_SCHEDULE = {
        'expire-pending-reservations': {
            'task': 'adminpanel.tasks.expire_pending_reservations',
            'schedule': crontab(minute=0),  # toutes les heures
        },
        'auto-confirm-interventions': {
            'task': 'adminpanel.tasks.auto_confirm_interventions',
            'schedule': crontab(minute=30),  # toutes les heures à H+30
        },
        'expire-disputes': {
            'task': 'adminpanel.tasks.expire_stale_disputes',
            'schedule': crontab(hour=2, minute=0),  # chaque nuit à 2h
        },
    }
"""

import logging

from celery import shared_task
from django.utils import timezone

logger = logging.getLogger(__name__)

SLA_DEMANDE_HEURES = 72   # Annuler DEMANDE_ENVOYEE sans réponse après 72h
SLA_CONFIRM_HEURES = 48   # Auto-confirmer EN_ATTENTE_CLIENT après 48h


@shared_task(name="adminpanel.tasks.expire_pending_reservations")
def expire_pending_reservations():
    """
    Annule automatiquement les réservations DEMANDE_ENVOYEE sans réponse du
    prestataire après SLA_DEMANDE_HEURES (72h).
    """
    from adminpanel.models import Reservation

    cutoff = timezone.now() - timezone.timedelta(hours=SLA_DEMANDE_HEURES)
    qs = Reservation.objects.filter(
        statut="DEMANDE_ENVOYEE",
        created_at__lt=cutoff,
    )
    count = 0
    for resa in qs:
        try:
            resa.statut = "Annulee"
            resa.note_client = (
                f"[AUTO] Annulée automatiquement après {SLA_DEMANDE_HEURES}h sans réponse du prestataire."
            )
            resa.save(update_fields=["statut", "note_client"])
            _notify_sla_expiry(resa)
            count += 1
        except Exception as exc:
            logger.error("Erreur expiration réservation %s: %s", resa.reference, exc)

    logger.info("expire_pending_reservations: %d réservation(s) annulée(s)", count)
    return {"expired": count}


@shared_task(name="adminpanel.tasks.auto_confirm_interventions")
def auto_confirm_interventions():
    """
    Auto-confirme les réservations EN_ATTENTE_CLIENT (prestation terminée mais
    client silencieux) après SLA_CONFIRM_HEURES (48h).
    """
    from adminpanel.models import Reservation

    cutoff = timezone.now() - timezone.timedelta(hours=SLA_CONFIRM_HEURES)
    qs = Reservation.objects.filter(
        statut="En attente client",
        updated_at__lt=cutoff,
    )
    count = 0
    for resa in qs:
        try:
            resa.statut = "Terminee"
            resa.note_client = (
                f"[AUTO] Confirmée automatiquement après {SLA_CONFIRM_HEURES}h "
                "sans retour du client."
            )
            resa.save(update_fields=["statut", "note_client"])
            _notify_auto_confirm(resa)
            count += 1
        except Exception as exc:
            logger.error("Erreur auto-confirmation réservation %s: %s", resa.reference, exc)

    logger.info("auto_confirm_interventions: %d réservation(s) auto-confirmée(s)", count)
    return {"confirmed": count}


@shared_task(name="adminpanel.tasks.expire_premium_subscriptions")
def expire_premium_subscriptions():
    """Désactive les abonnements premium expirés (toutes les heures à H:15)."""
    try:
        from adminpanel.services.provider_subscription_service import ProviderSubscriptionService
        count = ProviderSubscriptionService.check_and_update_expired()
        logger.info("expire_premium_subscriptions: %d abonnement(s) désactivé(s)", count)
        return {"expired": count}
    except Exception as exc:
        logger.error("expire_premium_subscriptions erreur: %s", exc)
        return {"error": str(exc)}


@shared_task(name="adminpanel.tasks.expire_stale_disputes")
def expire_stale_disputes():
    """
    Délègue à DisputeService.auto_expire_disputes() pour clore les litiges
    en médiation depuis plus de 5 jours sans activité.
    """
    try:
        from adminpanel.services.dispute_service import DisputeService

        result = DisputeService.auto_expire_disputes()
        logger.info("expire_stale_disputes: %s", result)
        return result
    except Exception as exc:
        logger.error("expire_stale_disputes erreur: %s", exc)
        return {"error": str(exc)}


# ---------------------------------------------------------------------------
# Helpers internes
# ---------------------------------------------------------------------------

def _notify_sla_expiry(resa):
    """Notifie client et prestataire de l'expiration SLA."""
    try:
        from adminpanel.push_dispatch import _schedule

        if resa.client_user_id:
            _schedule(
                [resa.client_user_id],
                "BABIFIX — Réservation expirée",
                f"Votre demande {resa.reference} a été annulée : le prestataire n'a pas répondu dans les délais.",
                {"type": "reservation.expired", "reference": resa.reference},
            )
        if resa.prestataire_user_id:
            _schedule(
                [resa.prestataire_user_id],
                "BABIFIX — Demande expirée",
                f"La demande {resa.reference} a expiré (72h sans réponse de votre part).",
                {"type": "reservation.expired", "reference": resa.reference},
            )
    except Exception as exc:
        logger.warning("Erreur notification expiration %s: %s", resa.reference, exc)


def _notify_auto_confirm(resa):
    """Notifie client et prestataire de la confirmation automatique."""
    try:
        from adminpanel.push_dispatch import _schedule

        if resa.client_user_id:
            _schedule(
                [resa.client_user_id],
                "BABIFIX — Prestation confirmée",
                f"La prestation {resa.reference} a été confirmée automatiquement. Vous pouvez maintenant noter le prestataire.",
                {"type": "reservation.auto_confirmed", "reference": resa.reference},
            )
        if resa.prestataire_user_id:
            _schedule(
                [resa.prestataire_user_id],
                "BABIFIX — Prestation terminée",
                f"La prestation {resa.reference} est maintenant terminée (confirmée automatiquement).",
                {"type": "reservation.auto_confirmed", "reference": resa.reference},
            )
    except Exception as exc:
        logger.warning("Erreur notification auto-confirm %s: %s", resa.reference, exc)
