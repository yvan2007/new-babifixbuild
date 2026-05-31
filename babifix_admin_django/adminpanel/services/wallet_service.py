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
import os
from decimal import Decimal

from django.db import transaction
from django.utils import timezone

logger = logging.getLogger(__name__)

BABIFIX_COMMISSION_RATE = Decimal("0.18")
WITHDRAWAL_MIN_FCFA = Decimal("1000")
# Plafond cumulé de retrait par prestataire et par jour (anti-fraude).
WITHDRAWAL_DAILY_CAP_FCFA = Decimal(
    os.getenv("WITHDRAWAL_DAILY_CAP_FCFA", "500000")
)
URGENCE_SURCHARGE_PCT = 20  # +20 % sur le montant si is_urgent


def _get_system_commission_rate() -> Decimal:
    """Recupere le taux de commission global depuis SystemSetting."""
    try:
        from adminpanel.models import SystemSetting
        setting = SystemSetting.objects.first()
        if setting and setting.commission:
            return Decimal(str(setting.commission)) / Decimal("100")
    except Exception:
        pass
    return BABIFIX_COMMISSION_RATE


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

        # Anti-fraude 1 : identité validée requise (KYC approuvé OU compte validé
        # par l'admin) avant tout retrait.
        kyc_ok = (getattr(prov, "kyc_status", "") == "approved") or (
            prov.statut == Provider.Status.VALID
        )
        if not kyc_ok:
            return {
                "error": "kyc_required",
                "detail": "Votre identité doit être validée avant d'effectuer un retrait.",
            }

        # Anti-fraude 2 : plafond cumulé par jour.
        from django.db.models import Sum

        start_day = timezone.now().replace(
            hour=0, minute=0, second=0, microsecond=0
        )
        today_sum = WalletTransaction.objects.filter(
            provider=prov,
            tx_type="debit",
            status__in=["pending", "processing", "success"],
            created_at__gte=start_day,
        ).aggregate(t=Sum("amount_fcfa"))["t"] or Decimal("0")
        if today_sum + amount_fcfa > WITHDRAWAL_DAILY_CAP_FCFA:
            return {
                "error": "daily_cap",
                "detail": (
                    f"Plafond journalier de retrait atteint "
                    f"({WITHDRAWAL_DAILY_CAP_FCFA:,.0f} FCFA). Déjà demandé "
                    f"aujourd'hui : {today_sum:,.0f} FCFA."
                ),
            }

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

    # ── Versement automatique (payout GeniusPay) ───────────────────────────
    @staticmethod
    def process_withdrawal(tx_id: int) -> dict:
        """Exécute le versement Mobile Money d'un retrait EN ATTENTE.

        Claim atomique (pending → processing) pour empêcher tout double envoi,
        puis appel payout GeniusPay HORS verrou. En cas d'échec d'envoi, le
        solde est immédiatement recrédité (refund)."""
        from adminpanel.models import WalletTransaction
        from adminpanel.geniuspay import geniuspay_send_payout

        # Phase 1 — claim atomique
        with transaction.atomic():
            tx = (
                WalletTransaction.objects.select_for_update()
                .filter(pk=tx_id, tx_type="debit", status="pending")
                .first()
            )
            if not tx:
                return {"error": "not_found_or_not_pending"}
            tx.status = "processing"
            tx.save(update_fields=["status"])
            provider = tx.provider
            amount = tx.amount_fcfa
            phone = tx.phone
            operator = tx.operator
            prov_nom = provider.nom

        ext_ref = tx.reference or f"RET-{tx.pk}"
        result = geniuspay_send_payout(
            amount=amount,
            phone=phone,
            operator=operator,
            recipient_name=prov_nom,
            reference=ext_ref,
            description=f"Retrait BABIFIX #{tx.pk}",
        )

        if not result.get("ok"):
            WalletService._refund_withdrawal(tx_id, reason=str(result.get("error")))
            return {"error": "payout_failed", "detail": result.get("error")}

        # Phase 2 — mise à jour selon la réponse (completed immédiat ou pending)
        with transaction.atomic():
            tx = WalletTransaction.objects.select_for_update().get(pk=tx_id)
            tx.reference = result.get("external_reference") or ext_ref
            tx.status = "success" if result.get("status") == "completed" else "processing"
            tx.save(update_fields=["reference", "status"])

        WalletService._notify_withdrawal_status(tx)
        logger.info(
            "WalletService.process_withdrawal: tx %s → %s (ref=%s)",
            tx.pk, tx.status, tx.reference,
        )
        return {
            "ok": True,
            "status": tx.status,
            "tx_id": tx.pk,
            "external_reference": tx.reference,
        }

    @staticmethod
    def _refund_withdrawal(tx_id: int, reason: str = "") -> None:
        """Recrédite le solde du prestataire après un versement échoué."""
        from adminpanel.models import Provider, WalletTransaction

        with transaction.atomic():
            tx = WalletTransaction.objects.select_for_update().get(pk=tx_id)
            if tx.status == "failed":
                return  # déjà remboursé (idempotent)
            prov = Provider.objects.select_for_update().get(pk=tx.provider_id)
            prov.solde_fcfa = (prov.solde_fcfa or Decimal("0")) + tx.amount_fcfa
            prov.save(update_fields=["solde_fcfa"])
            tx.status = "failed"
            tx.description = (f"{tx.description or ''} | Échec versement: {reason}")[:480]
            tx.save(update_fields=["status", "description"])
            WalletTransaction.objects.create(
                provider=prov,
                tx_type="refund",
                amount_fcfa=tx.amount_fcfa,
                status="success",
                reference=tx.reference,
                description=f"Remboursement retrait échoué #{tx.pk}",
            )
        WalletService._notify_withdrawal_status(tx, refunded=True)
        logger.info("WalletService._refund_withdrawal: tx %s remboursé (%s)", tx_id, reason)

    @staticmethod
    def handle_payout_webhook(*, external_reference: str, success: bool, raw=None) -> dict:
        """Met à jour un retrait suite au webhook GeniusPay payout.* (idempotent)."""
        from adminpanel.models import WalletTransaction

        tx = (
            WalletTransaction.objects.filter(
                reference=external_reference, tx_type="debit"
            )
            .order_by("-created_at")
            .first()
        )
        if not tx:
            logger.warning("payout webhook: retrait introuvable ref=%s", external_reference)
            return {"error": "tx_not_found"}
        if success:
            if tx.status != "success":
                tx.status = "success"
                tx.save(update_fields=["status"])
                WalletService._notify_withdrawal_status(tx)
            return {"ok": True, "status": "success"}
        # Échec → rembourser si pas déjà fait
        if tx.status != "failed":
            WalletService._refund_withdrawal(tx.pk, reason="payout.failed (webhook)")
        return {"ok": True, "status": "failed_refunded"}

    @staticmethod
    def _notify_withdrawal_status(tx, refunded: bool = False) -> None:
        """Notifie le prestataire (push + WebSocket) de l'état de son retrait."""
        try:
            from adminpanel.push_dispatch import _schedule

            if tx.status == "success":
                title = "BABIFIX — Retrait effectué"
                body = (
                    f"Votre retrait de {tx.amount_fcfa:,.0f} FCFA via "
                    f"{tx.operator.upper()} a été versé."
                )
                ev = "wallet.withdrawal_done"
            elif refunded or tx.status == "failed":
                title = "BABIFIX — Retrait échoué"
                body = (
                    f"Votre retrait de {tx.amount_fcfa:,.0f} FCFA a échoué. "
                    f"Le montant a été recrédité sur votre solde."
                )
                ev = "wallet.withdrawal_failed"
            else:
                title = "BABIFIX — Retrait en cours"
                body = (
                    f"Votre retrait de {tx.amount_fcfa:,.0f} FCFA est en cours "
                    f"de traitement."
                )
                ev = "wallet.withdrawal_processing"
            _schedule([tx.provider.user_id], title, body, {"type": ev, "tx_id": str(tx.pk)})
        except Exception as exc:
            logger.warning("notify withdrawal status (push) failed: %s", exc)
        try:
            from asgiref.sync import async_to_sync
            from channels.layers import get_channel_layer

            layer = get_channel_layer()
            if layer:
                async_to_sync(layer.group_send)(
                    f"prestataire_{tx.provider.user_id}",
                    {
                        "type": "prestataire_notify",
                        "event_type": "wallet.withdrawal_update",
                        "payload": {
                            "tx_id": tx.pk,
                            "status": tx.status,
                            "amount": float(tx.amount_fcfa),
                        },
                    },
                )
        except Exception:
            pass

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
    """Commission effective = taux categorie - reduction premium."""
    base = _get_system_commission_rate()
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
