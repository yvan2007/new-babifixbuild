"""process_timeouts — Job de surveillance des délais BABIFIX.

À lancer périodiquement (cron / Render Cron Job toutes les 30 minutes) :

    python manage.py process_timeouts

Traite trois timeouts :

1. **C6 — Devis expirés** : `Devis(statut=ENVOYE)` dont la date de
   création + `validite_jours` est dépassée → passe en `EXPIRE`. La
   réservation revient à `DEMANDE_ENVOYEE` pour permettre un nouveau
   devis. Notif client + presta.

2. **C2 — Intervention non démarrée** : `Reservation(statut=DEVIS_ACCEPTE,
   acompte_valide=True)` depuis plus de 72h sans bouton "Démarrer" cliqué
   → relance push au prestataire. Au-delà de 7 jours sans démarrer, on
   propose au client d'ouvrir un litige (notif).

3. **C3 — Client n'a pas confirmé** : `Reservation(statut=Terminee)`
   depuis plus de 7 jours sans confirmation → on libère
   automatiquement les fonds (présomption d'acceptation), notif client
   pour transparence.

Options :

    --dry-run    affiche ce qui serait fait sans rien modifier.
    --verbose    log détaillé.
"""

from __future__ import annotations

import logging
from datetime import timedelta

from django.core.management.base import BaseCommand
from django.utils import timezone


logger = logging.getLogger(__name__)


class Command(BaseCommand):
    help = "Traite les expirations de devis et les timeouts d'intervention/confirmation."

    def add_arguments(self, parser):
        parser.add_argument("--dry-run", action="store_true", default=False)
        parser.add_argument("--verbose", action="store_true", default=False)

    def handle(self, *args, **opts):
        from adminpanel.models import Devis, Reservation
        from adminpanel.push_dispatch import _schedule
        from adminpanel.services.escrow_service import EscrowService

        dry = bool(opts.get("dry_run"))
        verbose = bool(opts.get("verbose"))
        now = timezone.now()
        stats = {"devis_expired": 0, "intervention_reminded": 0,
                 "intervention_dispute_offered": 0, "auto_confirmed": 0}

        # ---------------------------------------------------------------
        # 1. Devis expirés
        # ---------------------------------------------------------------
        envoyes = Devis.objects.filter(statut=Devis.Statut.ENVOYE)
        for d in envoyes.iterator():
            expire_at = d.created_at + timedelta(days=int(d.validite_jours or 7))
            if expire_at <= now:
                if dry:
                    self.stdout.write(f"  [DRY] expire DEV {d.reference}")
                else:
                    d.statut = Devis.Statut.EXPIRE
                    d.save(update_fields=["statut"])
                    res = d.reservation
                    if (
                        res
                        and res.statut == Reservation.Status.DEVIS_ENVOYE
                    ):
                        res.statut = Reservation.Status.DEMANDE_ENVOYEE
                        res.save(update_fields=["statut"])
                    try:
                        recipients = []
                        if res:
                            if res.client_user_id:
                                recipients.append(res.client_user_id)
                            if (
                                res.assigned_provider
                                and res.assigned_provider.user_id
                            ):
                                recipients.append(
                                    res.assigned_provider.user_id
                                )
                        if recipients:
                            _schedule(
                                recipients,
                                "Devis expiré",
                                (
                                    f"Le devis {d.reference} a expiré "
                                    f"(validité {d.validite_jours} jours)."
                                ),
                                {
                                    "type": "devis.expired",
                                    "reference": res.reference if res else "",
                                    "devis_reference": d.reference,
                                },
                            )
                    except Exception as exc:
                        logger.warning("notif expire failed: %s", exc)
                stats["devis_expired"] += 1
                if verbose:
                    self.stdout.write(f"  expired DEV {d.reference}")

        # ---------------------------------------------------------------
        # 2. Intervention non démarrée
        # ---------------------------------------------------------------
        # Best-effort : on ne sait pas exactement quand l'acompte a été
        # versé, on s'appuie sur cash_client_declared_at puis updated_at.
        stuck = Reservation.objects.filter(
            statut=Reservation.Status.DEVIS_ACCEPTE,
            acompte_valide=True,
        )
        for r in stuck.iterator():
            ref_date = r.cash_client_declared_at or r.updated_at
            if not ref_date:
                continue
            age_hours = (now - ref_date).total_seconds() / 3600
            if age_hours >= 24 * 7:
                # Plus d'une semaine sans démarrer → proposer litige
                if dry:
                    self.stdout.write(
                        f"  [DRY] dispute offer for {r.reference} ({age_hours:.0f}h)"
                    )
                else:
                    try:
                        if r.client_user_id:
                            _schedule(
                                [r.client_user_id],
                                "Intervention non démarrée",
                                (
                                    f"Le prestataire n'a pas démarré "
                                    f"{r.reference} depuis 7 jours. "
                                    "Vous pouvez ouvrir un litige."
                                ),
                                {
                                    "type": "intervention.stuck",
                                    "reference": r.reference,
                                },
                            )
                    except Exception:
                        pass
                stats["intervention_dispute_offered"] += 1
            elif age_hours >= 72:
                # Plus de 72h → relance le prestataire
                if dry:
                    self.stdout.write(
                        f"  [DRY] remind presta {r.reference} ({age_hours:.0f}h)"
                    )
                else:
                    try:
                        if (
                            r.assigned_provider
                            and r.assigned_provider.user_id
                        ):
                            _schedule(
                                [r.assigned_provider.user_id],
                                "Relance : intervention à démarrer",
                                (
                                    f"L'acompte est versé pour {r.reference} "
                                    "depuis plus de 3 jours. Démarrez "
                                    "l'intervention rapidement."
                                ),
                                {
                                    "type": "intervention.reminder",
                                    "reference": r.reference,
                                },
                            )
                    except Exception:
                        pass
                stats["intervention_reminded"] += 1

        # ---------------------------------------------------------------
        # 3. Confirmation client absente → auto-confirmation J+7
        # ---------------------------------------------------------------
        terminee = Reservation.objects.filter(statut="Terminee").exclude(
            prestation_terminee_at__isnull=True
        )
        for r in terminee.iterator():
            if r.client_confirme_prestation_at:
                continue
            # SÉCURITÉ : ne JAMAIS auto-confirmer/verser une réservation en litige.
            if getattr(r, "dispute_ouverte", False):
                continue
            age_hours = (now - r.prestation_terminee_at).total_seconds() / 3600
            if age_hours < 24 * 7:
                continue
            if dry:
                self.stdout.write(f"  [DRY] auto-confirm {r.reference}")
                stats["auto_confirmed"] += 1
                continue
            r.client_confirme_prestation_at = now
            r.statut = Reservation.Status.CONFIRMED
            r.save(update_fields=["client_confirme_prestation_at", "statut"])
            try:
                EscrowService.release_funds(r)
            except Exception as exc:
                logger.warning("auto-release failed for %s: %s", r.reference, exc)
            try:
                recipients = []
                if r.client_user_id:
                    recipients.append(r.client_user_id)
                if r.assigned_provider and r.assigned_provider.user_id:
                    recipients.append(r.assigned_provider.user_id)
                if recipients:
                    _schedule(
                        recipients,
                        "Confirmation automatique",
                        (
                            f"Faute de confirmation sous 7 jours, "
                            f"l'intervention {r.reference} a été confirmée "
                            "automatiquement et les fonds libérés."
                        ),
                        {
                            "type": "intervention.auto_confirmed",
                            "reference": r.reference,
                        },
                    )
            except Exception:
                pass
            stats["auto_confirmed"] += 1
            if verbose:
                self.stdout.write(f"  auto-confirmed {r.reference}")

        self.stdout.write(self.style.SUCCESS(
            f"Timeouts traites : devis_expires={stats['devis_expired']} "
            f"intervention_relances={stats['intervention_reminded']} "
            f"litige_propose={stats['intervention_dispute_offered']} "
            f"auto_confirmes={stats['auto_confirmed']}"
        ))
