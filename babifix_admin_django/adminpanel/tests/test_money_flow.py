"""Tests du flux argent BABIFIX — retraits, remboursements, litiges.

Couvre les garanties critiques (anti-régression) :
- Retrait : demande → versement payout (simulation) → succès ; échec webhook → remboursement solde.
- Anti-fraude : KYC requis, plafond journalier.
- Litige : versement GELÉ tant qu'un litige est ouvert.
- Résolution litige : RELEASE paie le presta, REFUND bloque + dette client.
- Remboursement client automatique (payout) + idempotence.

Les clés GeniusPay sont neutralisées en setUp → mode SIMULATION (aucun appel réseau).

Run : python manage.py test adminpanel.tests.test_money_flow
"""
from __future__ import annotations

from decimal import Decimal

from django.contrib.auth.models import User
from django.test import TestCase
from django.utils import timezone

from adminpanel import geniuspay as gp
from adminpanel.models import (
    Devis,
    Provider,
    Reservation,
    UserProfile,
    WalletTransaction,
)
from adminpanel.services.escrow_service import EscrowService
from adminpanel.services.wallet_service import WalletService


class _MoneyBase(TestCase):
    def setUp(self):
        # Forcer le mode simulation (pas d'appel GeniusPay réel pendant les tests).
        self._keys = (gp.GENIUSPAY_PUBLIC_KEY, gp.GENIUSPAY_SECRET_KEY)
        gp.GENIUSPAY_PUBLIC_KEY = ""
        gp.GENIUSPAY_SECRET_KEY = ""

        self.presta_user = User.objects.create_user(username=f"p_{self._testMethodName}")
        self.client_user = User.objects.create_user(username=f"c_{self._testMethodName}")
        self.prov = Provider.objects.create(
            user=self.presta_user,
            nom="Provider Test",
            statut=Provider.Status.VALID,
            solde_fcfa=Decimal("0"),
        )

    def tearDown(self):
        gp.GENIUSPAY_PUBLIC_KEY, gp.GENIUSPAY_SECRET_KEY = self._keys

    def _reservation(self, dispute=False):
        return Reservation.objects.create(
            reference=f"RES-{self._testMethodName[:18]}",
            client="Jean Client",
            prestataire=self.prov.nom,
            montant=Decimal("10000"),
            statut=Reservation.Status.DONE,
            payment_type=Reservation.PaymentType.MOBILE_MONEY,
            mobile_money_operator="ORANGE_MONEY",
            client_user=self.client_user,
            prestataire_user=self.presta_user,
            assigned_provider=self.prov,
            montant_verse=Decimal("10000"),
            dispute_ouverte=dispute,
        )

    def _devis(self, res):
        return Devis.objects.create(
            reference=f"DV-{self._testMethodName[:16]}",
            reservation=res,
            prestataire=self.prov,
            diagnostic="x",
            sous_total=Decimal("10000"),
            commission_montant=Decimal("1800"),
            total_ttc=Decimal("10000"),
            net_prestataire=Decimal("8200"),
            commission_rate=18,
            statut=Devis.Statut.ACCEPTE,
        )


class WithdrawalTests(_MoneyBase):
    def test_request_then_payout_success(self):
        self.prov.solde_fcfa = Decimal("5000")
        self.prov.save()
        r = WalletService.request_withdrawal(self.prov.pk, Decimal("5000"), "+2250700000000", "orange")
        self.assertEqual(r.get("status"), "pending")
        tx_id = r["tx_id"]
        out = WalletService.process_withdrawal(tx_id)
        self.assertTrue(out.get("ok"))
        tx = WalletTransaction.objects.get(pk=tx_id)
        self.assertEqual(tx.status, "success")  # simulation = completed
        self.prov.refresh_from_db()
        self.assertEqual(self.prov.solde_fcfa, Decimal("0"))  # déjà débité à la demande

    def test_kyc_required(self):
        self.prov.statut = Provider.Status.PENDING
        self.prov.kyc_status = "pending"
        self.prov.solde_fcfa = Decimal("50000")
        self.prov.save()
        r = WalletService.request_withdrawal(self.prov.pk, Decimal("5000"), "+2250700000000", "orange")
        self.assertEqual(r.get("error"), "kyc_required")

    def test_daily_cap(self):
        self.prov.solde_fcfa = Decimal("600000")
        self.prov.save()
        r1 = WalletService.request_withdrawal(self.prov.pk, Decimal("100000"), "+2250700000000", "orange")
        self.assertEqual(r1.get("status"), "pending")
        r2 = WalletService.request_withdrawal(self.prov.pk, Decimal("450000"), "+2250700000000", "orange")
        self.assertEqual(r2.get("error"), "daily_cap")

    def test_webhook_failure_refunds_balance(self):
        # Solde déjà débité (=0), retrait en cours de versement.
        tx = WalletTransaction.objects.create(
            provider=self.prov, tx_type="debit", amount_fcfa=Decimal("3000"),
            status="processing", reference="PYT-FAILTEST", phone="+2250700000000", operator="wave",
        )
        WalletService.handle_payout_webhook(external_reference="PYT-FAILTEST", success=False)
        tx.refresh_from_db()
        self.prov.refresh_from_db()
        self.assertEqual(tx.status, "failed")
        self.assertEqual(self.prov.solde_fcfa, Decimal("3000"))  # recrédité
        self.assertTrue(
            WalletTransaction.objects.filter(provider=self.prov, tx_type="refund").exists()
        )


class DisputeMoneyTests(_MoneyBase):
    def test_dispute_blocks_release(self):
        res = self._reservation(dispute=True)
        self._devis(res)
        res.client_confirme_prestation_at = timezone.now()
        res.save()
        out = EscrowService.release_funds(res)
        self.assertEqual(out.get("error"), "dispute_open")
        self.prov.refresh_from_db()
        self.assertEqual(self.prov.solde_fcfa, Decimal("0"))  # rien versé

    def test_resolve_release_pays_provider(self):
        res = self._reservation(dispute=True)
        self._devis(res)
        out = EscrowService.resolve_dispute(res, "RELEASE")
        self.assertEqual(out.get("action"), "release")
        self.prov.refresh_from_db()
        res.refresh_from_db()
        self.assertEqual(self.prov.solde_fcfa, Decimal("8200"))
        self.assertFalse(res.dispute_ouverte)

    def test_resolve_refund_blocks_provider(self):
        res = self._reservation(dispute=True)
        self._devis(res)
        out = EscrowService.resolve_dispute(res, "REFUND")
        self.assertEqual(out.get("action"), "refund")
        self.prov.refresh_from_db()
        res.refresh_from_db()
        self.assertEqual(self.prov.solde_fcfa, Decimal("0"))  # presta non payé
        self.assertEqual(res.refund_owed_fcfa, Decimal("10000"))
        self.assertEqual(res.statut, Reservation.Status.CANCELLED)
        self.assertFalse(res.dispute_ouverte)


class ClientRefundTests(_MoneyBase):
    def test_auto_refund_paid_and_idempotent(self):
        UserProfile.objects.create(
            user=self.client_user, role="client", phone_e164="+2250709876543"
        )
        res = self._reservation(dispute=True)
        self._devis(res)
        EscrowService.resolve_dispute(res, "REFUND")
        res.refresh_from_db()
        out = EscrowService.process_client_refund(res)
        self.assertTrue(out.get("ok"))
        res.refresh_from_db()
        self.assertEqual(res.refund_status, "paid")
        self.assertIsNotNone(res.refund_paid_at)
        # idempotent : ne re-paie pas
        out2 = EscrowService.process_client_refund(res)
        self.assertIn("skip", out2)
