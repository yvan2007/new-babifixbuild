"""
Signaux métier → diffusion WebSocket admin + emails transactionnels BABIFIX.
"""
import logging
from django.db.models.signals import post_delete, post_save
from django.dispatch import receiver

from . import push_dispatch, realtime
from .models import (
    Actualite,
    Category,
    Client,
    Dispute,
    Message,
    MetierPropose,
    Notification,
    Payment,
    Provider,
    Rating,
    Reservation,
    SiteContent,
    SystemSetting,
    UserProfile,
)


def _skip_signal_kwargs(**kwargs) -> bool:
    return bool(kwargs.get('raw'))


def _update_fields_frozen(**kwargs):
    uf = kwargs.get('update_fields')
    return frozenset(uf) if uf is not None else None


@receiver(post_save, sender=Message)
def on_message_saved(sender, instance, created, **kwargs):
    if _skip_signal_kwargs(**kwargs):
        return
    if created:
        push_dispatch.on_chat_message_created(instance)


@receiver(post_save, sender=Reservation)
def on_reservation_saved(sender, instance, created, **kwargs):
    if _skip_signal_kwargs(**kwargs):
        return
    uf = _update_fields_frozen(**kwargs)
    event = 'reservation.created' if created else 'reservation.updated'
    payload = realtime.serialize_reservation(instance)

    # 1) Toujours informer le panel admin (vue d'ensemble).
    realtime.broadcast_admin_event(event, payload)

    # 2) Push FCM (déjà géré pour des cas spécifiques).
    push_dispatch.on_reservation_change(instance, created, uf)

    # Ciblage intelligent : seul le destinataire réel de l'étape reçoit
    # une notification WebSocket ; l'initiateur reçoit un event silencieux
    # `reservations.sync` pour rafraîchir son écran sans doublon ni pop-up.
    statut_changed = uf is None or 'statut' in uf
    client_notif_statuts = {
        'DEVIS_ENVOYE',
        'Confirmee',
        'INTERVENTION_EN_COURS',
        'En attente client',
        'Annulee',
    }
    presta_notif_statuts = {
        'DEVIS_ACCEPTE',
        'Terminee',
        'Annulee',
    }
    if created:
        client_ws_event = 'reservations.sync'
        presta_ws_event = 'reservation.created'
    elif not statut_changed:
        client_ws_event = 'reservations.sync'
        presta_ws_event = 'reservations.sync'
    else:
        client_ws_event = (
            'reservation.updated'
            if instance.statut in client_notif_statuts
            else 'reservations.sync'
        )
        presta_ws_event = (
            'reservation.updated'
            if instance.statut in presta_notif_statuts
            else 'reservations.sync'
        )

    # 3) Temps réel CLIENT : pousser sur le groupe `babifix_client_<uid>`.
    client_uid = getattr(instance, 'client_user_id', None) or getattr(instance, 'client_id', None)
    if client_uid:
        try:
            realtime.broadcast_client_user(int(client_uid), client_ws_event, payload)
        except (TypeError, ValueError):
            pass

    # 4) Temps réel PRESTATAIRE : pousser sur `babifix_prestataire_<uid>`.
    prov_uid = (
        getattr(instance, 'prestataire_user_id', None)
        or (
            getattr(instance.assigned_provider, 'user_id', None)
            if getattr(instance, 'assigned_provider_id', None) and instance.assigned_provider
            else None
        )
    )
    if prov_uid:
        try:
            realtime.broadcast_prestataire_user(int(prov_uid), presta_ws_event, payload)
        except (TypeError, ValueError):
            pass

    # ── Emails : nouvelle réservation → prestataire ; mission terminée → client ──
    try:
        from .views_extra import email_new_reservation, email_mission_completed
        if created and instance.assigned_provider:
            email_new_reservation(instance.assigned_provider, instance)
        elif not created and instance.statut == Reservation.Status.DONE:
            uf = kwargs.get('update_fields')
            if uf is None or 'statut' in (uf or []):
                email_mission_completed(instance)
    except Exception as exc:
        _log.warning('Email signal reservation: %s', exc)


@receiver(post_delete, sender=Reservation)
def on_reservation_deleted(sender, instance, **kwargs):
    realtime.broadcast_admin_event(
        'reservation.deleted',
        {'reference': instance.reference, 'id': instance.pk},
    )


_log = logging.getLogger(__name__)


@receiver(post_save, sender=Provider)
def on_provider_saved(sender, instance, created, **kwargs):
    if _skip_signal_kwargs(**kwargs):
        return
    event = 'provider.created' if created else 'provider.updated'
    realtime.broadcast_admin_event(event, realtime.serialize_provider(instance))
    # Broadcast to client apps for real-time provider list sync
    realtime.broadcast_client_event('providers.updated', {})
    realtime.invalidate_providers_cache()
    # Invalide AUSSI le cache des catégories : la vue client ne montre que les
    # catégories ayant ≥1 presta validé. Sans ça, après validation d'un presta
    # dans une nouvelle catégorie, le presta s'affichait mais PAS sa catégorie
    # (liste catégories figée ~5 min par le cache Redis).
    try:
        from django.core.cache import cache
        cache.delete('babifix:public:categories:client')
        cache.delete('babifix:public:categories:all')
    except Exception:
        pass
    push_dispatch.on_provider_change(instance, created, _update_fields_frozen(**kwargs))

    # ── Emails transactionnels sur changement de statut ──────────────────────
    if not created:
        uf = kwargs.get('update_fields')
        statut_changed = uf is None or 'statut' in (uf or [])
        if statut_changed:
            try:
                from .views_extra import email_provider_accepted, email_provider_refused
                if instance.statut == Provider.Status.VALID:
                    email_provider_accepted(instance)
                elif instance.statut == Provider.Status.REFUSED:
                    email_provider_refused(instance, instance.refusal_reason)
            except Exception as exc:
                _log.warning('Email signal provider: %s', exc)


@receiver(post_save, sender=Actualite)
def on_actualite_saved(sender, instance, created, **kwargs):
    if _skip_signal_kwargs(**kwargs):
        return
    event = 'actualite.created' if created else 'actualite.updated'
    realtime.broadcast_admin_event(event, realtime.serialize_actualite(instance))
    # Broadcast to client apps so they see new news immediately
    realtime.broadcast_client_event('actualite.updated', {})
    push_dispatch.on_actualite_published(instance, created, _update_fields_frozen(**kwargs))

    # Création d'une Notification en DB pour chaque utilisateur ciblé
    # → l'app les lit via /api/notifications et les affiche dans la cloche
    # + déclenche une bannière toast avec son si l'app est ouverte (signaux WS).
    try:
        if instance.publie and created:
            from .models import UserProfile
            cible = (getattr(instance, 'cible', '') or '').lower()
            roles = []
            if cible in ('client', ''):
                roles.append(UserProfile.Role.CLIENT)
            if cible in ('prestataire', 'presta', ''):
                roles.append(UserProfile.Role.PRESTATAIRE)
            if cible == 'all' or not cible:
                roles = [UserProfile.Role.CLIENT, UserProfile.Role.PRESTATAIRE]

            user_ids = list(
                UserProfile.objects.filter(role__in=roles, active=True)
                .values_list('user_id', flat=True)
            )
            titre_court = f"📢 {instance.titre[:80]}"
            body_court = (instance.description or '')[:200]
            notifs = [
                Notification(
                    user_id=uid,
                    title=titre_court,
                    body=body_court,
                    notif_type='actualite',
                    reference=f'ACT-{instance.pk}',
                )
                for uid in user_ids if uid
            ]
            if notifs:
                Notification.objects.bulk_create(notifs, batch_size=200, ignore_conflicts=True)
                _log.info('Actualité %s : %d notifications créées', instance.pk, len(notifs))
    except Exception as exc:
        _log.warning('Création notifications actualité: %s', exc)


## NOTE : l'envoi FCM des Notifications est centralisé plus bas dans
## `on_notification_saved` : un seul handler, filtré sur `created`, qui
## délègue à `push_dispatch.on_notification_created` (gère user ciblé ET
## broadcast global). Ce stub est volontairement conservé sans receiver
## pour garder un point d'entrée si on veut un jour ré-introduire un
## traitement spécialisé.


@receiver(post_delete, sender=Provider)
def on_provider_deleted(sender, instance, **kwargs):
    realtime.broadcast_admin_event(
        'provider.deleted',
        {'id': instance.pk, 'nom': instance.nom},
    )
    # Broadcast to client apps for real-time provider list sync
    realtime.broadcast_client_event('providers.updated', {})
    realtime.invalidate_providers_cache()


@receiver(post_save, sender=Dispute)
def on_dispute_saved(sender, instance, created, **kwargs):
    if _skip_signal_kwargs(**kwargs):
        return
    event = 'dispute.created' if created else 'dispute.updated'
    realtime.broadcast_admin_event(event, realtime.serialize_dispute(instance))
    push_dispatch.on_dispute_change(instance, created, _update_fields_frozen(**kwargs))


@receiver(post_delete, sender=Dispute)
def on_dispute_deleted(sender, instance, **kwargs):
    realtime.broadcast_admin_event(
        'dispute.deleted',
        {'reference': instance.reference, 'id': instance.pk},
    )


@receiver(post_save, sender=Payment)
def on_payment_saved(sender, instance, created, **kwargs):
    if _skip_signal_kwargs(**kwargs):
        return
    event = 'payment.created' if created else 'payment.updated'
    realtime.broadcast_admin_event(event, realtime.serialize_payment(instance))
    push_dispatch.on_payment_change(instance, created, _update_fields_frozen(**kwargs))


@receiver(post_delete, sender=Payment)
def on_payment_deleted(sender, instance, **kwargs):
    realtime.broadcast_admin_event(
        'payment.deleted',
        {'reference': instance.reference, 'id': instance.pk},
    )


@receiver(post_save, sender=Category)
def on_category_saved(sender, instance, created, **kwargs):
    if _skip_signal_kwargs(**kwargs):
        return
    event = 'category.created' if created else 'category.updated'
    realtime.broadcast_admin_event(event, realtime.serialize_category(instance))
    # Broadcast to client/prestataire apps for real-time sync
    realtime.broadcast_client_event('categories.updated', {})
    # Invalidate public categories cache
    realtime.invalidate_categories_cache()


@receiver(post_delete, sender=Category)
def on_category_deleted(sender, instance, **kwargs):
    realtime.broadcast_admin_event(
        'category.deleted',
        {'id': instance.pk, 'nom': instance.nom},
    )
    # Broadcast to client/prestataire apps for real-time sync
    realtime.broadcast_client_event('categories.updated', {})
    # Invalidate public categories cache
    realtime.invalidate_categories_cache()


@receiver(post_save, sender=Notification)
def on_notification_saved(sender, instance, created, **kwargs):
    if _skip_signal_kwargs(**kwargs):
        return
    event = 'notification.created' if created else 'notification.updated'
    payload = realtime.serialize_notification(instance)
    if instance.user_id is None:
        realtime.broadcast_admin_event(event, payload)
    else:
        try:
            role = (
                UserProfile.objects.filter(user_id=instance.user_id)
                .values_list('role', flat=True)
                .first()
            )
            if role == UserProfile.Role.PRESTATAIRE:
                realtime.broadcast_prestataire_user(instance.user_id, event, payload)
            elif role == UserProfile.Role.CLIENT:
                realtime.broadcast_client_user(instance.user_id, event, payload)
        except Exception:
            pass
    # Push FCM seulement a la creation si _skip_fcm n est pas active.
    if created and not getattr(instance, '_skip_fcm', False):
        push_dispatch.on_notification_created(instance)


@receiver(post_delete, sender=Notification)
def on_notification_deleted(sender, instance, **kwargs):
    realtime.broadcast_admin_event(
        'notification.deleted',
        {'id': instance.pk},
    )


@receiver(post_save, sender=Client)
def on_client_saved(sender, instance, created, **kwargs):
    if _skip_signal_kwargs(**kwargs):
        return
    event = 'client.created' if created else 'client.updated'
    realtime.broadcast_admin_event(
        event,
        {'id': instance.pk, 'nom': instance.nom, 'email': instance.email},
    )


@receiver(post_delete, sender=Client)
def on_client_deleted(sender, instance, **kwargs):
    realtime.broadcast_admin_event(
        'client.deleted',
        {'id': instance.pk, 'nom': instance.nom},
    )


@receiver(post_save, sender=SystemSetting)
def on_system_setting_saved(sender, instance, created, **kwargs):
    if _skip_signal_kwargs(**kwargs):
        return
    realtime.broadcast_admin_event(
        'settings.updated',
        {'id': instance.pk},
    )


@receiver(post_save, sender=SiteContent)
def on_site_content_saved(sender, instance, created, **kwargs):
    if _skip_signal_kwargs(**kwargs):
        return
    event = 'sitecontent.created' if created else 'sitecontent.updated'
    realtime.broadcast_admin_event(event, {'key': instance.key})


@receiver(post_delete, sender=SiteContent)
def on_site_content_deleted(sender, instance, **kwargs):
    realtime.broadcast_admin_event('sitecontent.deleted', {'key': instance.key})


@receiver(post_save, sender=Rating)
def on_rating_saved(sender, instance, created, **kwargs):
    if _skip_signal_kwargs(**kwargs):
        return
    event = 'rating.created' if created else 'rating.updated'
    realtime.broadcast_admin_event(
        event,
        {
            'id': instance.pk,
            'note': instance.note,
            'provider_id': instance.provider_id,
            'reservation_id': instance.reservation_id,
        },
    )
    push_dispatch.on_rating_change(instance, created)
    _update_provider_rating(instance.provider)


def _update_provider_rating(provider):
    """Recalcule et met a jour la note moyenne du prestataire."""
    from django.db.models import Avg
    avg = provider.ratings.aggregate(avg=Avg('note'))['avg'] or 0.0
    count = provider.ratings.count()
    provider.average_rating = round(avg, 2)
    provider.rating_count = count
    provider.save(update_fields=['average_rating', 'rating_count'])


@receiver(post_save, sender=MetierPropose)
def on_metier_propose_saved(sender, instance, created, **kwargs):
    if _skip_signal_kwargs(**kwargs):
        return
    if created:
        realtime.broadcast_admin_event(
            'metier_propose.created',
            {'id': instance.pk, 'nom': instance.nom, 'votes': instance.votes},
        )
        push_dispatch.on_metier_propose_created(instance)
