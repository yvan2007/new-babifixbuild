"""
WalletService — gestion du wallet prestataire BABIFIX.

Flux :
  1. Paiement client confirmé → credit_provider(payment)
  2. Prestataire demande retrait → request_withdrawal(provider, amount, phone, operator)
"""

import logging
from decimal import Decimal

from django.db import transaction

logger = logging.getLogger(__name__)

# Commission BABIFIX : 15 % sur chaque prestation
BABIFIX_COMMISSION_RATE = Decimal("0.15")
WITHDRAWAL_MIN_FCFA = Decimal("1000")


class WalletService:

    @staticmethod
    @transaction.atomic
    def credit_provider(payment) -> dict:
        """
        Crédite le wallet prestataire après confirmation d'un paiement.
        Déduit la commission BABIFIX (15 %) et enregistre les deux transactions.

        Args:
            payment: instance adminpanel.models.Payment

        Returns:
            dict avec solde_after, credit, commission
        """
        from adminpanel.models import Provider, WalletTransaction

        reservation = getattr(payment, "reservation", None)
        if not reservation:
            logger.warning("WalletService.credit_provider: payment %s has no reservation", payment.pk)
            return {"error": "no_reservation"}

        provider = getattr(reservation, "prestataire", None)
        if not provider:
            logger.warning("WalletService.credit_provider: reservation %s has no prestataire", reservation.pk)
            return {"error": "no_prestataire"}

        try:
            prov = Provider.objects.select_for_update().get(pk=provider.pk)
        except Provider.DoesNotExist:
            return {"error": "provider_not_found"}

        gross = Decimal(str(payment.amount or 0))
        commission = (gross * BABIFIX_COMMISSION_RATE).quantize(Decimal("1"))
        net = gross - commission

        prov.solde_fcfa = (prov.solde_fcfa or Decimal("0")) + net
        prov.save(update_fields=["solde_fcfa"])

        WalletTransaction.objects.create(
            provider=prov,
            tx_type="credit",
            amount_fcfa=net,
            reference=getattr(reservation, "reference", ""),
            description=f"Paiement reçu pour {reservation.reference} (net après commission)",
        )
        WalletTransaction.objects.create(
            provider=prov,
            tx_type="commission",
            amount_fcfa=commission,
            reference=getattr(reservation, "reference", ""),
            description=f"Commission BABIFIX 15 % sur {reservation.reference}",
        )

        logger.info(
            "WalletService: crédité %s FCFA (net) au prestataire %s — commission %s FCFA",
            net, prov.pk, commission,
        )
        return {
            "solde_after": float(prov.solde_fcfa),
            "credit": float(net),
            "commission": float(commission),
        }

    @staticmethod
    @transaction.atomic
    def request_withdrawal(provider_id: int, amount_fcfa: Decimal, phone: str, operator: str) -> dict:
        """
        Initie une demande de retrait Mobile Money.

        Args:
            provider_id: PK du Provider
            amount_fcfa: montant à retirer (Decimal)
            phone: numéro Mobile Money
            operator: 'mtn' | 'orange' | 'wave' | 'moov'

        Returns:
            dict avec status, solde_after ou error
        """
        from adminpanel.models import Provider, WalletTransaction

        if amount_fcfa < WITHDRAWAL_MIN_FCFA:
            return {
                "error": "min_amount",
                "detail": f"Montant minimum de retrait : {WITHDRAWAL_MIN_FCFA} FCFA",
            }

        valid_operators = {"mtn", "orange", "wave", "moov"}
        if operator not in valid_operators:
            return {"error": "invalid_operator", "detail": f"Opérateur invalide : {operator}"}

        try:
            prov = Provider.objects.select_for_update().get(pk=provider_id)
        except Provider.DoesNotExist:
            return {"error": "provider_not_found"}

        if (prov.solde_fcfa or Decimal("0")) < amount_fcfa:
            return {
                "error": "insufficient_funds",
                "detail": f"Solde insuffisant ({prov.solde_fcfa} FCFA disponible)",
            }

        prov.solde_fcfa = (prov.solde_fcfa or Decimal("0")) - amount_fcfa
        prov.wallet_phone = phone
        prov.wallet_operator = operator
        prov.save(update_fields=["solde_fcfa", "wallet_phone", "wallet_operator"])

        tx = WalletTransaction.objects.create(
            provider=prov,
            tx_type="debit",
            amount_fcfa=amount_fcfa,
            status="pending",
            phone=phone,
            operator=operator,
            description=f"Retrait {operator.upper()} vers {phone}",
        )

        # TODO : appel API Mobile Money (MTN MoMo, Orange, Wave) pour déclencher le virement
        # En attendant : statut "pending" → l'admin valide manuellement
        logger.info(
            "WalletService: retrait %s FCFA demandé par provider %s via %s %s",
            amount_fcfa, provider_id, operator, phone,
        )
        return {
            "status": "pending",
            "tx_id": tx.pk,
            "solde_after": float(prov.solde_fcfa),
            "amount": float(amount_fcfa),
            "operator": operator,
            "phone": phone,
        }

    @staticmethod
    def get_wallet_summary(provider_id: int) -> dict:
        """Retourne le solde et les 20 dernières transactions d'un prestataire."""
        from adminpanel.models import Provider, WalletTransaction

        try:
            prov = Provider.objects.get(pk=provider_id)
        except Provider.DoesNotExist:
            return {"error": "provider_not_found"}

        txs = WalletTransaction.objects.filter(provider=prov).order_by("-created_at")[:20]
        return {
            "solde_fcfa": float(prov.solde_fcfa or 0),
            "wallet_phone": prov.wallet_phone,
            "wallet_operator": prov.wallet_operator,
            "transactions": [
                {
                    "id": t.pk,
                    "type": t.tx_type,
                    "amount": float(t.amount_fcfa),
                    "status": t.status,
                    "reference": t.reference,
                    "description": t.description,
                    "operator": t.operator,
                    "phone": t.phone,
                    "created_at": t.created_at.isoformat(),
                }
                for t in txs
            ],
        }
