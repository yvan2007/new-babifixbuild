"""CancellationService — annulation BABIFIX avec remboursement escrow (C1).

Règles métier (alignées sur `ANNULATION_RULES` côté views) :

| Stage          | Annulation CLIENT      | Annulation PRESTATAIRE       |
|----------------|------------------------|------------------------------|
| before_devis   | 0% pénalité, refund    | 0% pénalité, refund          |
| after_devis    | 0% pénalité, refund    | 0% pénalité, refund          |
| after_accept   | 10% pénalité, 90% refund | 0% pénalité, refund        |
| after_start    | 50% pénalité, 50% refund | 0% pénalité, refund full   |

Concrètement :

- **Mobile (escrow plateforme intégral)** : on calcule
  `refund_owed_fcfa = montant_verse × refund_pct`, le reste est versé au
  prestataire (compensation pénalité) ou retourné à zéro selon le stage.
  La libération réelle au presta utilise toujours `release_funds` mais
  avec un montant partiel.

- **Cash (seule la commission 18% est en escrow MM)** :
  - Si stage = before_start ET annulation par presta : on rembourse 100%
    de la commission (PlatformRevenue.refunded_at = now), le client n'a
    rien à régler au presta.
  - Si stage = before_start ET annulation par client : la commission est
    conservée par défaut (pénalité) sauf si refund_pct=100.
  - Si stage = after_start : la commission reste acquise, le presta a
    droit au prorata travail effectué (réglé en cash hors plateforme).

- Ne fait JAMAIS de virement MM réel — `refund_owed_fcfa` est une dette
  qu'un admin honore manuellement via l'interface admin (puis set
  `refund_paid_at`).

Idempotent : si `cancelled_at` est déjà set, retourne immédiatement.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from decimal import Decimal
from typing import Optional

from django.db import transaction
from django.utils import timezone

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Détermination du stage
# ---------------------------------------------------------------------------
def _stage(reservation) -> str:
    """Identifie l'étape d'avancement pour appliquer la règle de pénalité."""
    from adminpanel.models import Reservation

    statut = reservation.statut
    if reservation.prestation_terminee_at or statut in {
        Reservation.Status.DONE,
        "Terminee",
        Reservation.Status.CONFIRMED,
        "Confirmee",
    }:
        # Trop tard pour annuler
        return "completed"
    if statut == Reservation.Status.INTERVENTION_EN_COURS:
        return "after_start"
    if statut == Reservation.Status.DEVIS_ACCEPTE or reservation.acompte_valide:
        return "after_accept"
    if statut == Reservation.Status.DEVIS_ENVOYE:
        return "after_devis"
    return "before_devis"


# Penalty pct retenue par la plateforme/presta. Le reste = refund client.
_PENALTY = {
    "CLIENT": {
        "before_devis": 0,
        "after_devis": 0,
        "after_accept": 10,
        "after_start": 50,
    },
    "PRESTATAIRE": {
        "before_devis": 0,
        "after_devis": 0,
        "after_accept": 0,
        "after_start": 0,
    },
    "ADMIN": {
        "before_devis": 0,
        "after_devis": 0,
        "after_accept": 0,
        "after_start": 0,
    },
}


@dataclass
class CancellationResult:
    ok: bool
    stage: str
    by: str
    penalty_pct: int
    refund_owed_fcfa: float
    presta_credited_fcfa: float
    platform_revenue_fcfa: float
    platform_commission_refunded: bool
    detail: str = ""


# ---------------------------------------------------------------------------
# Service
# ---------------------------------------------------------------------------
class CancellationService:

    @staticmethod
    @transaction.atomic
    def cancel(reservation, *, by: str, motif: str = "") -> CancellationResult:
        from adminpanel.models import (
            PlatformRevenue,
            Provider,
            Reservation,
            WalletTransaction,
        )
        from adminpanel.services.escrow_service import _latest_devis

        by = (by or "").upper()
        if by not in _PENALTY:
            return CancellationResult(
                ok=False, stage="", by=by, penalty_pct=0,
                refund_owed_fcfa=0, presta_credited_fcfa=0,
                platform_revenue_fcfa=0, platform_commission_refunded=False,
                detail="invalid_by",
            )

        # Idempotence
        if reservation.cancelled_at:
            return CancellationResult(
                ok=True, stage=reservation.cancellation_stage or "",
                by=reservation.cancellation_by or by,
                penalty_pct=0,
                refund_owed_fcfa=float(reservation.refund_owed_fcfa or 0),
                presta_credited_fcfa=0, platform_revenue_fcfa=0,
                platform_commission_refunded=False,
                detail="already_cancelled",
            )

        stage = _stage(reservation)
        if stage == "completed":
            return CancellationResult(
                ok=False, stage=stage, by=by, penalty_pct=0,
                refund_owed_fcfa=0, presta_credited_fcfa=0,
                platform_revenue_fcfa=0, platform_commission_refunded=False,
                detail="cannot_cancel_after_completion",
            )

        penalty_pct = _PENALTY[by][stage]
        refund_pct = 100 - penalty_pct

        devis = _latest_devis(reservation)
        net_prestataire = (
            Decimal(str(devis.net_prestataire or 0)) if devis else Decimal("0")
        )
        commission = (
            Decimal(str(devis.commission_montant or 0)) if devis else Decimal("0")
        )

        montant_verse = Decimal(str(reservation.montant_verse or 0))
        refund_owed = Decimal("0")
        presta_credit = Decimal("0")
        platform_rev = Decimal("0")
        commission_refunded = False

        is_cash = reservation.payment_type == Reservation.PaymentType.ESPECES

        if montant_verse > 0:
            if is_cash:
                # Seule la commission est en escrow plateforme.
                # Refund total uniquement si by=PRESTATAIRE ou (by=CLIENT & refund=100%)
                if refund_pct >= 100 or by != "CLIENT":
                    # Reverser la commission au client + marquer PR refunded
                    refund_owed = commission
                    pr_qs = PlatformRevenue.objects.filter(
                        reference=reservation.reference,
                        refunded_at__isnull=True,
                    )
                    for pr in pr_qs:
                        pr.refunded_at = timezone.now()
                        pr.description = (
                            f"{pr.description} | REMBOURSÉ {by} {stage}"
                        )[:5000]
                        pr.save(update_fields=["refunded_at", "description"])
                        commission_refunded = True
                else:
                    # La plateforme conserve sa commission encaissée à l'acompte.
                    # Le presta n'est pas crédité (pas de wallet activé en cash).
                    platform_rev = commission  # informatif, déjà comptabilisé
            else:
                # Mobile : montant_verse = total_ttc.
                if refund_pct >= 100:
                    refund_owed = montant_verse
                elif refund_pct <= 0:
                    # Pas de refund client : tout va à la plateforme + presta
                    refund_owed = Decimal("0")
                    presta_credit = (montant_verse * Decimal("50")) / Decimal("100")
                    platform_rev = montant_verse - presta_credit
                else:
                    refund_owed = (montant_verse * Decimal(refund_pct)) / Decimal("100")
                    retenu = montant_verse - refund_owed
                    # Le retenu est partagé : la part presta = net% du retenu,
                    # la part plateforme = commission% du retenu.
                    if (commission + net_prestataire) > 0:
                        presta_credit = (
                            retenu * net_prestataire / (commission + net_prestataire)
                        )
                        platform_rev = retenu - presta_credit
                    else:
                        # fallback : tout en plateforme
                        platform_rev = retenu

                # Crédite réellement le wallet presta si applicable
                if presta_credit > 0:
                    provider = (
                        reservation.assigned_provider
                        or Provider.objects.filter(
                            user_id=reservation.prestataire_user_id
                        ).first()
                    )
                    if provider:
                        prov = Provider.objects.select_for_update().get(
                            pk=provider.pk
                        )
                        prov.solde_fcfa = (
                            prov.solde_fcfa or Decimal("0")
                        ) + presta_credit.quantize(Decimal("1"))
                        prov.save(update_fields=["solde_fcfa"])
                        WalletTransaction.objects.create(
                            provider=prov,
                            tx_type="credit",
                            amount_fcfa=presta_credit.quantize(Decimal("1")),
                            reference=reservation.reference,
                            description=(
                                f"Annulation {by} {stage} — compensation prestataire"
                            ),
                            status="success",
                        )
                if platform_rev > 0:
                    PlatformRevenue.objects.create(
                        amount_fcfa=platform_rev.quantize(Decimal("1")),
                        source=PlatformRevenue.Source.COMMISSION,
                        reference=reservation.reference,
                        description=(
                            f"Pénalité annulation {by} {stage} — "
                            f"{penalty_pct}% retenus sur {montant_verse} FCFA"
                        ),
                    )

        # ── Règlement de la caution de visite (no-show / annulation) ──────────
        # Règle : si la visite a eu lieu, le prestataire garde la caution
        # (compensation du déplacement). Sinon, elle est remboursée au client
        # (le déplacement n'a pas été consommé), commission plateforme incluse.
        caution_montant = Decimal(str(getattr(reservation, "caution_montant", 0) or 0))
        caution_refunded = False
        if (
            caution_montant > 0
            and getattr(reservation, "caution_payee", False)
            and not getattr(reservation, "caution_deduite", False)
            and not getattr(reservation, "caution_remboursee", False)
        ):
            if not getattr(reservation, "visite_effectuee", False):
                # Remboursement dû au client (s'ajoute au refund éventuel).
                refund_owed = refund_owed + caution_montant
                reservation.caution_remboursee = True
                caution_refunded = True
                # La plateforme rend aussi sa commission de caution.
                for pr in PlatformRevenue.objects.filter(
                    reference=reservation.reference,
                    refunded_at__isnull=True,
                    description__icontains="caution",
                ):
                    pr.refunded_at = timezone.now()
                    pr.description = (f"{pr.description} | REMBOURSÉ caution {by}")[:5000]
                    pr.save(update_fields=["refunded_at", "description"])
            # else : visite faite → le presta garde la caution (rien à faire,
            # le Payment de caution reste acquis).

        # Persiste l'état d'annulation
        reservation.statut = Reservation.Status.CANCELLED
        reservation.cancelled_at = timezone.now()
        reservation.cancellation_by = by
        reservation.cancellation_stage = stage
        reservation.cancellation_motif = (motif or "")[:5000]
        reservation.refund_owed_fcfa = refund_owed.quantize(Decimal("1"))
        # Le presta ne touchera plus rien via release_funds → on marque
        # funds_released_at pour que release_funds soit no-op.
        if not reservation.funds_released_at:
            reservation.funds_released_at = timezone.now()
        reservation.save(update_fields=[
            "statut",
            "cancelled_at",
            "cancellation_by",
            "cancellation_stage",
            "cancellation_motif",
            "refund_owed_fcfa",
            "funds_released_at",
            "caution_remboursee",
        ])

        # Notif aux 2 parties
        try:
            from adminpanel.push_dispatch import _schedule

            recipients = []
            if by != "CLIENT" and reservation.client_user_id:
                recipients.append(reservation.client_user_id)
            if (
                by != "PRESTATAIRE"
                and reservation.assigned_provider
                and reservation.assigned_provider.user_id
            ):
                recipients.append(reservation.assigned_provider.user_id)
            if recipients:
                _schedule(
                    recipients,
                    "Réservation annulée",
                    f"{reservation.reference} annulée par {by.lower()} ({stage}).",
                    {
                        "type": "reservation.cancelled",
                        "reference": reservation.reference,
                        "by": by,
                        "stage": stage,
                        "refund_owed_fcfa": str(refund_owed),
                    },
                )
        except Exception as exc:
            logger.debug("notif cancel skipped: %s", exc)

        # Bloc système dans la conversation unique
        try:
            from adminpanel.services.conversation_service import post_system_event

            post_system_event(
                reservation,
                event_type="reservation.cancelled",
                body=(
                    f"Réservation annulée par {by.lower()} ({stage}). "
                    + (
                        f"Remboursement dû au client : {int(refund_owed)} F CFA. "
                        if refund_owed > 0
                        else ""
                    )
                    + (
                        f"Pénalité retenue : {penalty_pct}%."
                        if penalty_pct > 0
                        else ""
                    )
                ),
                extra={
                    "by": by,
                    "stage": stage,
                    "penalty_pct": penalty_pct,
                    "refund_owed_fcfa": float(refund_owed),
                },
            )
        except Exception as exc:
            logger.debug("system event cancel skipped: %s", exc)

        logger.info(
            "Cancellation: %s by=%s stage=%s pen=%d%% refund=%s "
            "presta_credit=%s platform=%s",
            reservation.reference,
            by,
            stage,
            penalty_pct,
            refund_owed,
            presta_credit,
            platform_rev,
        )

        return CancellationResult(
            ok=True,
            stage=stage,
            by=by,
            penalty_pct=penalty_pct,
            refund_owed_fcfa=float(refund_owed),
            presta_credited_fcfa=float(presta_credit),
            platform_revenue_fcfa=float(platform_rev),
            platform_commission_refunded=commission_refunded,
        )
