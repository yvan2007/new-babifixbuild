"""
WalletService — gestion du wallet prestataire BABIFIX.

Flux :
  1. Paiement client confirmé → credit_provider(payment)
  2. Prestataire demande retrait → request_withdrawal(provider_id, amount, phone, operator)

Bugs corrigés v2 :
  - payment.amount → payment.montant (champ réel du modèle Payment)
  - reservation.prestataire (CharField nom) → reservation.assigned_provider (FK Provider)
  - Ajout tracking PlatformRevenue sur chaque commission perçue
"""

import logging
from decimal import Decimal

from django.db import transaction
from django.utils import timezone

logger = logging.getLogger(__name__)

BABIFIX_COMMISSION_RATE = Decimal("0.15")
WITHDRAWAL_MIN_FCFA = Decimal("1000")
URGENCE_SURCHARGE_PCT = 20  # +20 % sur le montant si is_urgent


class WalletService:

    @staticmethod
    @transaction.atomic
    def credit_provider(payment) -> dict:
        """
        Crédite le wallet prestataire après confirmation d'un paiement.
        Déduit la commission BABIFIX (15 %) et enregistre les transactions.
        Enregistre aussi la commission dans PlatformRevenue.
        """
        from adminpanel.models import Provider, WalletTransaction, PlatformRevenue, Reservation
        from adminpanel.services.referral_service import ReferralService

        reservation = getattr(payment, "reservation", None)
        if not reservation:
            logger.warning("credit_provider: payment %s has no reservation", payment.pk)
            return {"error": "no_reservation"}

        # ← CORRECTION: assigned_provider est la FK Provider, pas le CharField nom
        provider = getattr(reservation, "assigned_provider", None)
        if not provider:
            # Fallback: chercher via prestataire_user
            prestataire_user = getattr(reservation, "prestataire_user", None)
            if prestataire_user:
                provider = Provider.objects.filter(user=prestataire_user).first()
        if not provider:
            logger.warning("credit_provider: reservation %s has no provider", reservation.pk)
            return {"error": "no_provider"}

        try:
            prov = Provider.objects.select_for_update().get(pk=provider.pk)
        except Provider.DoesNotExist:
            return {"error": "provider_not_found"}

        # ← CORRECTION: payment.montant, pas payment.amount
        gross = Decimal(str(payment.montant or 0))
        if gross <= 0:
            return {"error": "amount_zero"}

        # Taux de commission effectif (réduit pour premium)
        commission_rate = _get_effective_commission_rate(prov)
        commission = (gross * commission_rate).quantize(Decimal("1"))
        net = gross - commission

        # Créditer le wallet du prestataire
        prov.solde_fcfa = (prov.solde_fcfa or Decimal("0")) + net
        prov.save(update_fields=["solde_fcfa"])

        WalletTransaction.objects.create(
            provider=prov,
            tx_type="credit",
            amount_fcfa=net,
            reference=reservation.reference,
            description=f"Paiement reçu — {reservation.reference} (net après commission {int(commission_rate * 100)}%)",
            status="success",
        )
        WalletTransaction.objects.create(
            provider=prov,
            tx_type="commission",
            amount_fcfa=commission,
            reference=reservation.reference,
            description=f"Commission BABIFIX {int(commission_rate * 100)}% sur {reservation.reference}",
            status="success",
        )

        # Enregistrer la commission côté plateforme BABIFIX
        PlatformRevenue.objects.create(
            amount_fcfa=commission,
            source="commission",
            reference=reservation.reference,
            description=f"Commission {int(commission_rate * 100)}% — {prov.nom} — {reservation.reference}",
            payment=payment,
        )

        # Bonus filleul : créditer 1000 FCFA sur la première réservation terminée
        try:
            if reservation.client_user_id:
                from django.contrib.auth.models import User
                client_user = User.objects.get(pk=reservation.client_user_id)
                ReferralService.validate_first_booking_reward(client_user)
        except Exception as exc:
            logger.warning("Erreur bonus filleul: %s", exc)

        # Notifier le prestataire en temps réel via WebSocket
        try:
            from asgiref.sync import async_to_sync
            from channels.layers import get_channel_layer
            channel_layer = get_channel_layer()
            async_to_sync(channel_layer.group_send)(
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
            logger.warning("WS wallet.credited failed: %s", exc)

        logger.info(
            "WalletService: crédité %s FCFA au prestataire %s — commission BABIFIX %s FCFA",
            net, prov.pk, commission,
        )
        return {
            "solde_after": float(prov.solde_fcfa),
            "credit": float(net),
            "commission": float(commission),
            "commission_rate_pct": int(commission_rate * 100),
        }

    @staticmethod
    @transaction.atomic
    def credit_provider_premium(provider, tier: str, amount_fcfa: Decimal) -> dict:
        """Enregistre un paiement d'abonnement premium dans PlatformRevenue."""
        from adminpanel.models import PlatformRevenue
        PlatformRevenue.objects.create(
            amount_fcfa=amount_fcfa,
            source="premium",
            reference=f"PREMIUM-{provider.pk}-{tier}",
            description=f"Abonnement premium {tier} — {provider.nom}",
        )
        return {"ok": True, "amount": float(amount_fcfa), "tier": tier}

    @staticmethod
    @transaction.atomic
    def request_withdrawal(provider_id: int, amount_fcfa: Decimal, phone: str, operator: str) -> dict:
        """
        Initie une demande de retrait Mobile Money.
        Status → pending (admin valide ou API Mobile Money déclenche le virement).
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

        # Notifier le prestataire via WebSocket
        try:
            from asgiref.sync import async_to_sync
            from channels.layers import get_channel_layer
            channel_layer = get_channel_layer()
            async_to_sync(channel_layer.group_send)(
                f"prestataire_{prov.user_id}",
                {
                    "type": "prestataire_notify",
                    "event_type": "wallet.withdrawal_requested",
                    "payload": {
                        "tx_id": tx.pk,
                        "amount": float(amount_fcfa),
                        "solde_after": float(prov.solde_fcfa),
                        "operator": operator,
                        "phone": phone,
                        "status": "pending",
                    },
                },
            )
        except Exception as exc:
            logger.warning("WS wallet.withdrawal_requested failed: %s", exc)

        # Notifier l'admin qu'un retrait est en attente
        try:
            from adminpanel.push_dispatch import _schedule
            from django.contrib.auth.models import User
            admin_ids = list(User.objects.filter(is_staff=True, is_active=True).values_list("id", flat=True))
            if admin_ids:
                _schedule(
                    admin_ids,
                    "BABIFIX — Demande de retrait",
                    f"{prov.nom} demande un retrait de {amount_fcfa:,.0f} FCFA via {operator.upper()}",
                    {
                        "type": "wallet.withdrawal_pending",
                        "provider_id": str(prov.pk),
                        "amount": str(amount_fcfa),
                        "route": "/admin/withdrawals",
                    },
                )
        except Exception as exc:
            logger.warning("Erreur notif admin retrait: %s", exc)

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
        """Retourne le solde et les 50 dernières transactions d'un prestataire."""
        from adminpanel.models import Provider, WalletTransaction

        try:
            prov = Provider.objects.get(pk=provider_id)
        except Provider.DoesNotExist:
            return {"error": "provider_not_found"}

        txs = WalletTransaction.objects.filter(provider=prov).order_by("-created_at")[:50]
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

    @staticmethod
    def get_platform_summary(days: int = 30) -> dict:
        """Résumé des revenus BABIFIX sur les N derniers jours."""
        from adminpanel.models import PlatformRevenue, WalletTransaction
        from django.db.models import Sum, Count

        threshold = timezone.now() - timezone.timedelta(days=days)

        rev_qs = PlatformRevenue.objects.filter(created_at__gte=threshold)
        total = rev_qs.aggregate(total=Sum("amount_fcfa"))["total"] or Decimal("0")
        by_source = list(
            rev_qs.values("source").annotate(total=Sum("amount_fcfa"), count=Count("id"))
        )

        # Retraits en attente
        pending_withdrawals = WalletTransaction.objects.filter(
            tx_type="debit", status="pending"
        ).aggregate(total=Sum("amount_fcfa"), count=Count("id"))

        return {
            "period_days": days,
            "total_revenue_fcfa": float(total),
            "by_source": [
                {"source": s["source"], "total": float(s["total"] or 0), "count": s["count"]}
                for s in by_source
            ],
            "pending_withdrawals_count": pending_withdrawals["count"] or 0,
            "pending_withdrawals_fcfa": float(pending_withdrawals["total"] or 0),
        }


def _get_effective_commission_rate(provider) -> Decimal:
    """Commission effective = taux catégorie - réduction premium."""
    base = Decimal("0.18")
    if provider.category_id:
        try:
            from adminpanel.models import CategoryCommission
            cc = CategoryCommission.objects.get(category_id=provider.category_id, actif=True)
            base = Decimal(str(cc.commission_rate)) / Decimal("100")
        except Exception:
            pass

    reduction = {"bronze": 0, "silver": 5, "gold": 10}.get(provider.premium_tier or "", 0)
    effective = base - Decimal(str(reduction)) / Decimal("100")
    return max(Decimal("0.05"), effective)
