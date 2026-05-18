"""seed_full_demo — Démo complète liée : devis + chat + appels + notifs + paiement.

Crée un scénario complet et cohérent autour des 5 demandes DEMO-REQ-* :
- Devis structuré (lignes) sur chaque demande applicable
- Conversation unique par demande, avec messages USER + DEVIS_CARD + SYSTEM
- Historique d'appels Call (1 audio, 1 vidéo, 1 manqué)
- Paiements mobile complétés sur les 2 demandes les plus avancées
- Notifications variées

Idempotent : ne crée que ce qui manque.
"""

from decimal import Decimal
from datetime import timedelta

from django.contrib.auth.models import User
from django.core.management.base import BaseCommand
from django.utils import timezone

from adminpanel.models import (
    Call, Conversation, Devis, LigneDevis, Message, Notification,
    Payment, PlatformRevenue, Provider, Reservation,
)
from adminpanel.services.conversation_service import (
    get_or_create_conversation_for_reservation,
    post_devis_card, post_system_event,
)


class Command(BaseCommand):
    help = "Démo complète : devis + chat + appels + notifs sur les demandes existantes."

    def handle(self, *args, **opts):
        prestas = list(Provider.objects.filter(user__isnull=False)[:5])
        if not prestas:
            self.stdout.write(self.style.ERROR("Aucun prestataire avec user — lance d'abord seed_demo_data."))
            return

        # On prend les 5 demandes démo
        refs = ["DEMO-REQ-001", "DEMO-REQ-002", "DEMO-REQ-003",
                "DEMO-REQ-004", "DEMO-REQ-005"]
        reservations = list(Reservation.objects.filter(reference__in=refs).order_by("reference"))
        if not reservations:
            self.stdout.write(self.style.ERROR("Pas de DEMO-REQ-* — lance seed_demo_data."))
            return

        clients_pool = list(User.objects.filter(is_staff=False).exclude(
            username__in=["prestataire_demo", "admin_demo"]
        )[:5])
        if len(clients_pool) < 1:
            self.stdout.write(self.style.ERROR("Aucun user client."))
            return

        stats = {"devis": 0, "convs": 0, "msgs": 0, "calls": 0, "payments": 0}

        for i, res in enumerate(reservations):
            presta = prestas[i % len(prestas)]
            client = clients_pool[i % len(clients_pool)]

            # Lier la résa au prestataire et au client si manquant
            updates = []
            if not res.assigned_provider:
                res.assigned_provider = presta
                updates.append("assigned_provider")
            if not res.prestataire_user_id:
                res.prestataire_user = presta.user
                updates.append("prestataire_user")
            if not res.client_user_id:
                res.client_user = client
                updates.append("client_user")
            if updates:
                res.save(update_fields=updates)

            # Devis si statut >= DEVIS_ENVOYE et pas encore créé
            advanced = res.statut in {
                "DEVIS_ENVOYE", "DEVIS_ACCEPTE",
                "INTERVENTION_EN_COURS", "En cours",
                "Terminee", "Confirmee",
            }
            devis = Devis.objects.filter(reservation=res).order_by("-id").first()
            if advanced and not devis:
                devis = Devis.objects.create(
                    reservation=res,
                    prestataire=presta,
                    diagnostic="Diagnostic complet réalisé sur place : pièce à remplacer + main d'œuvre estimée.",
                    commission_rate=18,
                    statut=Devis.Statut.ENVOYE,
                    note_prestataire="Intervention possible sous 48h. Garantie 6 mois.",
                    validite_jours=7,
                )
                LigneDevis.objects.create(
                    devis=devis, type_ligne="FOURNITURE",
                    description="Pièce de rechange",
                    quantite=Decimal("1"), prix_unitaire=Decimal("8000"),
                    unite="u", marque="Standard",
                )
                LigneDevis.objects.create(
                    devis=devis, type_ligne="MAIN_OEUVRE",
                    description="Pose et test",
                    quantite=Decimal("2"), prix_unitaire=Decimal("4000"),
                    unite="h",
                )
                LigneDevis.objects.create(
                    devis=devis, type_ligne="DEPLACEMENT",
                    description="Déplacement urbain Abidjan",
                    quantite=Decimal("1"), prix_unitaire=Decimal("2000"),
                    unite="forfait",
                )
                devis.save()  # recalcule totaux
                stats["devis"] += 1
                # Passer en ACCEPTE si la résa est déjà avancée
                if res.statut in {"DEVIS_ACCEPTE", "INTERVENTION_EN_COURS",
                                  "En cours", "Terminee", "Confirmee"}:
                    devis.statut = Devis.Statut.ACCEPTE
                    devis.save()
                    res.montant = devis.total_ttc
                    res.save(update_fields=["montant"])
            devis = Devis.objects.filter(reservation=res).order_by("-id").first()

            # Conversation + messages
            conv = get_or_create_conversation_for_reservation(res)
            if conv:
                if Message.objects.filter(conversation=conv).count() == 0:
                    # Message USER initial du client
                    Message.objects.create(
                        conversation=conv,
                        sender=client,
                        body="Bonjour, est-ce que vous pouvez intervenir cette semaine ?",
                        kind=Message.Kind.USER,
                    )
                    # Réponse presta
                    Message.objects.create(
                        conversation=conv,
                        sender=presta.user,
                        body="Bonjour, oui je suis disponible jeudi après-midi.",
                        kind=Message.Kind.USER,
                    )
                    # Carte devis figée si on a un devis
                    if devis and devis.statut in [
                        Devis.Statut.ENVOYE, Devis.Statut.ACCEPTE
                    ]:
                        post_devis_card(res, devis)
                    # Event système si statut avancé
                    if res.statut in {"INTERVENTION_EN_COURS", "En cours"}:
                        post_system_event(
                            res, "intervention.started",
                            f"Intervention démarrée par {presta.nom}.",
                            extra={"provider_name": presta.nom},
                        )
                    if res.statut in {"Terminee", "Confirmee"}:
                        post_system_event(
                            res, "intervention.finished",
                            f"Travaux terminés par {presta.nom}.",
                        )
                    if res.statut in {"Confirmee"}:
                        post_system_event(
                            res, "client.confirmed",
                            "Le client a confirmé les travaux.",
                        )
                    stats["msgs"] += Message.objects.filter(conversation=conv).count()
                stats["convs"] += 1

            # Paiement mobile complété sur les 2 dernières demandes
            if devis and res.statut in {"INTERVENTION_EN_COURS", "Terminee",
                                          "Confirmee", "En cours"}:
                if not Payment.objects.filter(reservation=res).exists():
                    p = Payment.objects.create(
                        reference=f"PAY-DEMO-{res.reference}",
                        client=str(client.username)[:120],
                        prestataire=presta.nom,
                        montant=str(int(devis.total_ttc)),
                        commission=str(int(devis.commission_montant)),
                        etat=Payment.State.COMPLETE,
                        reservation=res,
                        type_paiement=Payment.TypePaiement.MOBILE_MONEY,
                        valide_par_admin=True,
                    )
                    res.acompte_valide = True
                    res.montant_verse = devis.total_ttc
                    res.save(update_fields=["acompte_valide", "montant_verse"])
                    stats["payments"] += 1

        # Appels d'historique entre client_demo et prestataire_demo
        if Call.objects.count() == 0:
            client = User.objects.filter(username="client_demo").first()
            presta_user = User.objects.filter(username="horzonzh").first()
            if client and presta_user:
                now = timezone.now()
                c1 = Call.objects.create(
                    caller=client, callee=presta_user,
                    reservation=reservations[2] if len(reservations) >= 3 else None,
                    room_name=f"babifix_demo_call1",
                    kind=Call.Kind.VOICE, status=Call.Status.ENDED,
                    answered_at=now - timedelta(hours=3),
                    ended_at=now - timedelta(hours=3, minutes=-5),
                    duration_seconds=312,
                )
                Call.objects.filter(pk=c1.pk).update(
                    started_at=now - timedelta(hours=3, minutes=1)
                )
                c2 = Call.objects.create(
                    caller=presta_user, callee=client,
                    reservation=reservations[3] if len(reservations) >= 4 else None,
                    room_name=f"babifix_demo_call2",
                    kind=Call.Kind.VIDEO, status=Call.Status.MISSED,
                )
                Call.objects.filter(pk=c2.pk).update(
                    started_at=now - timedelta(days=1)
                )
                c3 = Call.objects.create(
                    caller=client, callee=presta_user,
                    reservation=reservations[4] if len(reservations) >= 5 else None,
                    room_name=f"babifix_demo_call3",
                    kind=Call.Kind.VOICE, status=Call.Status.REJECTED,
                )
                Call.objects.filter(pk=c3.pk).update(
                    started_at=now - timedelta(days=2)
                )
                stats["calls"] += 3

        # Notifications
        if Notification.objects.count() < 50:
            client_demo = User.objects.filter(username="client_demo").first()
            if client_demo:
                for i, t in enumerate([
                    "Bienvenue sur BABIFIX !",
                    "Nouveau devis reçu",
                    "Travaux confirmés",
                ]):
                    Notification.objects.create(
                        title=t, body=f"Message démo n°{i+1}",
                        user=client_demo,
                    )

        self.stdout.write(self.style.SUCCESS(
            f"OK demo : devis={stats['devis']} convs={stats['convs']} "
            f"msgs={stats['msgs']} calls={stats['calls']} "
            f"payments={stats['payments']}"
        ))
