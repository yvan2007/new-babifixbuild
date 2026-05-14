"""EscrowService — orchestration paiement BABIFIX (Phase F).

Règle métier confirmée par le porteur du projet :

1. Quand le client accepte un devis, il DOIT verser un acompte avant que le
   prestataire ne démarre l'intervention.

2. Deux stratégies selon `Reservation.payment_type` :

   * **ESPECES (cash)** : l'acompte est exactement la **commission** de la
     plateforme (`Devis.commission_montant` = 18 % du sous-total). Ce
     montant est versé en Mobile Money via GeniusPay et constitue
     immédiatement un `PlatformRevenue` (c'est notre part finale). Le solde
     (82 %) sera donné en cash au prestataire en main à main à la fin du
     chantier. La plateforme n'a plus rien à libérer à la confirmation.

   * **MOBILE_MONEY** : l'acompte est le **total du devis** (`total_ttc`).
     L'argent reste en escrow (compte plateforme) jusqu'à la confirmation
     client. À la confirmation, on libère `net_prestataire` (82 %) dans le
     wallet du prestataire et on enregistre `commission_montant` (18 %) en
     PlatformRevenue.

3. **AUCUN fonds ne quitte la plateforme avant `client_confirme_prestation_at`.**
   En particulier le wallet prestataire n'est jamais crédité au moment du
   paiement initial — uniquement à `release_funds()`.

4. Idempotence : `release_funds` est sûr d'être appelé plusieurs fois (il
   regarde `funds_released_at`).
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from decimal import Decimal
from typing import Optional

from django.db import transaction
from django.utils import timezone

logger = logging.getLogger(__name__)

# B12 — Montant minimum acceptable en Mobile Money (limite GeniusPay 200 XOF).
# Si la commission cash devait être < ce seuil, on prélève ce minimum à la
# place ; le surplus (différence entre minimum et commission réelle) est
# tracé via `EscrowQuote.cash_minimum_surplus` puis reversé au prestataire
# à la confirmation pour qu'aucune partie ne soit lésée.
MIN_ONLINE_PAYMENT_XOF = Decimal("500")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _latest_devis(reservation):
    """Devis ACCEPTE le plus récent, sinon ENVOYE, sinon None."""
    from adminpanel.models import Devis

    qs = Devis.objects.filter(reservation=reservation).order_by("-created_at")
    accepted = qs.filter(statut=Devis.Statut.ACCEPTE).first()
    if accepted:
        return accepted
    return qs.filter(statut=Devis.Statut.ENVOYE).first()


@dataclass
class EscrowQuote:
    """Ce que le client doit verser maintenant pour démarrer l'intervention."""

    strategy: str  # "CASH_COMMISSION_ONLY" | "MOBILE_FULL"
    amount_due: Decimal  # montant à payer EN LIGNE (XOF entier)
    commission_montant: Decimal  # commission plateforme
    net_prestataire: Decimal  # ce que touchera le presta
    total_devis: Decimal  # total devis (référence affichage)
    cash_remainder: Decimal  # solde à payer cash au presta (0 si mobile)
    devis_id: Optional[int]
    devis_reference: str
    # B12 — Surplus prélevé en plus de la commission cash pour respecter
    # MIN_ONLINE_PAYMENT_XOF. Sera reversé au prestataire à la confirmation.
    cash_minimum_surplus: Decimal = Decimal("0")


# ---------------------------------------------------------------------------
# Service
# ---------------------------------------------------------------------------
class EscrowService:
    """Orchestration paiement initial + libération à la confirmation."""

    # ---------- Calcul du montant à payer ----------------------------------
    @staticmethod
    def quote(reservation) -> EscrowQuote:
        """Calcule l'acompte requis selon la stratégie de la réservation."""
        from adminpanel.models import Reservation

        devis = _latest_devis(reservation)
        if devis is None:
            return EscrowQuote(
                strategy="UNKNOWN",
                amount_due=Decimal("0"),
                commission_montant=Decimal("0"),
                net_prestataire=Decimal("0"),
                total_devis=Decimal("0"),
                cash_remainder=Decimal("0"),
                devis_id=None,
                devis_reference="",
            )

        total = Decimal(str(devis.total_ttc or 0))
        commission = Decimal(str(devis.commission_montant or 0))
        net = Decimal(str(devis.net_prestataire or 0))

        cash_minimum_surplus = Decimal("0")
        if reservation.payment_type == Reservation.PaymentType.ESPECES:
            strategy = "CASH_COMMISSION_ONLY"
            amount_due = commission
            # B12 — Force le minimum acceptable Mobile Money. Si la
            # commission seule est trop faible (devis < ~2 800 FCFA),
            # on prélève le minimum et on note le surplus pour le
            # reverser au presta à la confirmation.
            if amount_due > 0 and amount_due < MIN_ONLINE_PAYMENT_XOF:
                cash_minimum_surplus = MIN_ONLINE_PAYMENT_XOF - amount_due
                amount_due = MIN_ONLINE_PAYMENT_XOF
            cash_remainder = net - cash_minimum_surplus
            if cash_remainder < 0:
                cash_remainder = Decimal("0")
        else:
            strategy = "MOBILE_FULL"
            amount_due = total
            # B12 — Mobile : même garde-fou si jamais un devis fait < 200 XOF.
            if amount_due > 0 and amount_due < MIN_ONLINE_PAYMENT_XOF:
                amount_due = MIN_ONLINE_PAYMENT_XOF
            cash_remainder = Decimal("0")

        return EscrowQuote(
            strategy=strategy,
            amount_due=amount_due.quantize(Decimal("1")),
            commission_montant=commission,
            net_prestataire=net,
            total_devis=total,
            cash_remainder=cash_remainder.quantize(Decimal("1")),
            devis_id=devis.id,
            devis_reference=devis.reference,
            cash_minimum_surplus=cash_minimum_surplus.quantize(Decimal("1")),
        )

    # ---------- Hook webhook GeniusPay -------------------------------------
    @staticmethod
    @transaction.atomic
    def mark_escrow_received(payment) -> dict:
        """Appelé par le webhook GeniusPay quand un paiement est validé.

        Ne crédite JAMAIS le wallet du prestataire.

        - Cash (acompte = commission) : enregistre directement en
          `PlatformRevenue` (c'est notre part finale) et marque
          `commission_collected_at`.
        - Mobile (paiement total) : marque l'acompte comme reçu en escrow,
          met à jour `montant_verse` et `acompte_valide`. Aucune écriture
          dans `PlatformRevenue` ni dans le wallet presta : on attendra la
          confirmation client (`release_funds`).
        """
        from adminpanel.models import PlatformRevenue, Reservation

        reservation = getattr(payment, "reservation", None)
        if not reservation:
            logger.warning(
                "mark_escrow_received: payment %s has no reservation", payment.pk
            )
            return {"error": "no_reservation"}

        gross = Decimal(str(payment.montant or 0))
        if gross <= 0:
            return {"error": "amount_zero"}

        reservation.montant_verse = (reservation.montant_verse or Decimal("0")) + gross
        reservation.acompte_valide = True
        if not reservation.cash_client_declared_at:
            reservation.cash_client_declared_at = timezone.now()
        update_fields = [
            "montant_verse",
            "acompte_valide",
            "cash_client_declared_at",
            "montant_restant",
        ]

        if reservation.payment_type == Reservation.PaymentType.ESPECES:
            # B12 — Le client paye au moins MIN_ONLINE_PAYMENT_XOF. La
            # portion `commission_montant` du devis est notre revenu ; le
            # surplus éventuel (devis très petit) est mis de côté pour
            # être reversé au presta à la confirmation.
            devis = _latest_devis(reservation)
            commission_due = (
                Decimal(str(devis.commission_montant or 0)) if devis else gross
            )
            if commission_due > gross:
                commission_due = gross  # garde-fou
            PlatformRevenue.objects.create(
                amount_fcfa=commission_due,
                source=PlatformRevenue.Source.COMMISSION,
                reference=reservation.reference,
                description=(
                    f"Commission 18 % prélevée à l'acompte cash — {reservation.reference}"
                ),
                payment=payment,
            )
            reservation.cash_flow_status = Reservation.CashFlowStatus.VALIDATED
            reservation.cash_admin_validated_at = timezone.now()
            update_fields += ["cash_flow_status", "cash_admin_validated_at"]
            surplus = gross - commission_due
            if surplus > 0:
                logger.info(
                    "EscrowService: surplus cash %s FCFA mis en escrow pour %s "
                    "(reversement presta à la confirmation)",
                    surplus,
                    reservation.reference,
                )
            logger.info(
                "EscrowService: commission cash %s FCFA encaissée pour %s",
                commission_due,
                reservation.reference,
            )
        else:
            # Mobile : tout est en escrow plateforme, rien n'est encore acquis.
            reservation.cash_flow_status = Reservation.CashFlowStatus.PENDING_ADMIN
            update_fields.append("cash_flow_status")
            logger.info(
                "EscrowService: escrow mobile %s FCFA bloqué pour %s",
                gross,
                reservation.reference,
            )

        reservation.save(update_fields=update_fields)

        # Notif temps réel
        try:
            from asgiref.sync import async_to_sync
            from channels.layers import get_channel_layer

            layer = get_channel_layer()
            if layer:
                async_to_sync(layer.group_send)(
                    f"reservation_{reservation.pk}",
                    {
                        "type": "reservation_event",
                        "event_type": "escrow.received",
                        "payload": {
                            "reference": reservation.reference,
                            "montant_verse": float(reservation.montant_verse),
                            "payment_type": reservation.payment_type,
                        },
                    },
                )
        except Exception as exc:
            logger.debug("WS escrow.received skipped: %s", exc)

        return {
            "ok": True,
            "strategy": (
                "CASH_COMMISSION_ONLY"
                if reservation.payment_type == Reservation.PaymentType.ESPECES
                else "MOBILE_FULL"
            ),
            "montant_verse": float(reservation.montant_verse),
        }

    # ---------- Libération à la confirmation client ------------------------
    @staticmethod
    @transaction.atomic
    def release_funds(reservation) -> dict:
        """Libère les fonds après confirmation client.

        Idempotent : si `funds_released_at` est déjà set, retourne
        immédiatement.

        - Mobile : crédite le wallet presta de `net_prestataire`, enregistre
          la commission en `PlatformRevenue`.
        - Cash : rien à libérer (commission déjà encaissée, solde déjà payé
          main à main). On marque juste `funds_released_at`.
        """
        from adminpanel.models import (
            PlatformRevenue,
            Provider,
            Reservation,
            WalletTransaction,
        )

        if getattr(reservation, "funds_released_at", None):
            return {"ok": True, "already_released": True}

        if not reservation.client_confirme_prestation_at:
            return {"error": "client_not_confirmed"}

        devis = _latest_devis(reservation)
        if devis is None:
            logger.warning(
                "release_funds: aucune devis pour %s — abort",
                reservation.reference,
            )
            return {"error": "no_devis"}

        commission = Decimal(str(devis.commission_montant or 0))
        net = Decimal(str(devis.net_prestataire or 0))

        result = {
            "ok": True,
            "released_to_provider": 0.0,
            "platform_revenue": 0.0,
            "strategy": (
                "CASH_COMMISSION_ONLY"
                if reservation.payment_type == Reservation.PaymentType.ESPECES
                else "MOBILE_FULL"
            ),
        }

        if reservation.payment_type == Reservation.PaymentType.ESPECES:
            # Cash : commission déjà en PlatformRevenue lors de l'acompte.
            # Le presta a perçu son net en main à main.
            #
            # B12 — Si on a prélevé un minimum supérieur à la commission
            # (devis très petit), le surplus doit être reversé au presta
            # maintenant (wallet) pour qu'aucune partie ne soit lésée.
            montant_verse = Decimal(str(reservation.montant_verse or 0))
            surplus = montant_verse - commission
            if surplus > 0:
                provider = reservation.assigned_provider
                if not provider and reservation.prestataire_user_id:
                    provider = Provider.objects.filter(
                        user_id=reservation.prestataire_user_id
                    ).first()
                if provider:
                    prov = Provider.objects.select_for_update().get(pk=provider.pk)
                    prov.solde_fcfa = (
                        prov.solde_fcfa or Decimal("0")
                    ) + surplus.quantize(Decimal("1"))
                    prov.save(update_fields=["solde_fcfa"])
                    WalletTransaction.objects.create(
                        provider=prov,
                        tx_type="credit",
                        amount_fcfa=surplus.quantize(Decimal("1")),
                        reference=reservation.reference,
                        description=(
                            f"Surplus minimum MM reversé — {reservation.reference}"
                        ),
                        status="success",
                    )
                    result["released_to_provider"] = float(surplus)
                    logger.info(
                        "EscrowService.release_funds: cash %s — surplus %s "
                        "reversé au presta",
                        reservation.reference,
                        surplus,
                    )
                else:
                    logger.warning(
                        "release_funds cash surplus: provider introuvable pour %s",
                        reservation.reference,
                    )
            else:
                logger.info(
                    "EscrowService.release_funds: cash %s — rien à reverser via wallet "
                    "(commission déjà acquise, net en main à main).",
                    reservation.reference,
                )
        else:
            # Mobile : la plateforme libère le net vers le wallet presta et
            # acte la commission en PlatformRevenue.
            provider = reservation.assigned_provider
            if not provider and reservation.prestataire_user_id:
                provider = Provider.objects.filter(
                    user_id=reservation.prestataire_user_id
                ).first()
            if not provider:
                logger.warning(
                    "release_funds: aucun provider pour %s", reservation.reference
                )
                return {"error": "no_provider"}

            prov = Provider.objects.select_for_update().get(pk=provider.pk)
            prov.solde_fcfa = (prov.solde_fcfa or Decimal("0")) + net
            prov.save(update_fields=["solde_fcfa"])

            WalletTransaction.objects.create(
                provider=prov,
                tx_type="credit",
                amount_fcfa=net,
                reference=reservation.reference,
                description=(
                    f"Libération escrow — {reservation.reference} "
                    f"(net après commission 18 %)"
                ),
                status="success",
            )
            WalletTransaction.objects.create(
                provider=prov,
                tx_type="commission",
                amount_fcfa=commission,
                reference=reservation.reference,
                description=(
                    f"Commission BABIFIX 18 % prélevée — {reservation.reference}"
                ),
                status="success",
            )
            PlatformRevenue.objects.create(
                amount_fcfa=commission,
                source=PlatformRevenue.Source.COMMISSION,
                reference=reservation.reference,
                description=(
                    f"Commission 18 % libérée à la confirmation — {reservation.reference}"
                ),
            )

            result["released_to_provider"] = float(net)
            result["platform_revenue"] = float(commission)
            result["provider_balance"] = float(prov.solde_fcfa)

            # Notif temps réel
            try:
                from asgiref.sync import async_to_sync
                from channels.layers import get_channel_layer

                layer = get_channel_layer()
                if layer:
                    async_to_sync(layer.group_send)(
                        f"prestataire_{prov.user_id}",
                        {
                            "type": "prestataire_notify",
                            "event_type": "wallet.credited",
                            "payload": {
                                "solde_fcfa": float(prov.solde_fcfa),
                                "net": float(net),
                                "commission": float(commission),
                                "reference": reservation.reference,
                            },
                        },
                    )
            except Exception as exc:
                logger.debug("WS wallet.credited skipped: %s", exc)

        reservation.funds_released_at = timezone.now()
        reservation.solde_valide = True
        reservation.cash_flow_status = Reservation.CashFlowStatus.VALIDATED
        reservation.save(
            update_fields=["funds_released_at", "solde_valide", "cash_flow_status"]
        )

        logger.info(
            "EscrowService.release_funds: %s — strategy=%s released=%s commission=%s",
            reservation.reference,
            result["strategy"],
            result.get("released_to_provider"),
            result.get("platform_revenue"),
        )
        return result
