"""Payout GeniusPay — versements SORTANTS (retraits presta / remboursements client).

Cette fonction n'existait tout simplement pas : `WalletService.process_withdrawal`
et `EscrowService.process_client_refund` l'importaient toutes les deux, d'où un
ImportError → un prestataire ne pouvait PAS récupérer son argent.

Règle de sécurité vérifiée ici : on ne renvoie JAMAIS ok=True sans confirmation
(sauf mode simulation explicite). L'appelant a déjà débité le solde et le
recrédite si ok=False : en cas de doute, on doit échouer, jamais l'inverse.
"""
from decimal import Decimal

from django.test import TestCase

from adminpanel.geniuspay import (
    _normalize_payout_operator,
    geniuspay_send_payout,
)


class NormalizePayoutOperatorTest(TestCase):
    def test_accepte_la_convention_wallet_minuscule(self):
        # Le wallet prestataire stocke 'mtn'/'orange'/'wave'/'moov'.
        self.assertEqual(_normalize_payout_operator("mtn"), "mtn_money")
        self.assertEqual(_normalize_payout_operator("orange"), "orange_money")
        self.assertEqual(_normalize_payout_operator("wave"), "wave")
        self.assertEqual(_normalize_payout_operator("moov"), "pawapay")

    def test_accepte_la_convention_babifix_majuscule(self):
        # Les réservations utilisent 'MTN_MOMO'/'ORANGE_MONEY'/...
        self.assertEqual(_normalize_payout_operator("MTN_MOMO"), "mtn_money")
        self.assertEqual(_normalize_payout_operator("ORANGE_MONEY"), "orange_money")
        self.assertEqual(_normalize_payout_operator("WAVE"), "wave")

    def test_rejette_inconnu_et_vide(self):
        self.assertEqual(_normalize_payout_operator("bitcoin"), "")
        self.assertEqual(_normalize_payout_operator(""), "")
        self.assertEqual(_normalize_payout_operator(None), "")


class SendPayoutValidationTest(TestCase):
    """Entrées invalides → ok=False (donc l'appelant recrédite le solde)."""

    def test_montant_nul_ou_negatif_refuse(self):
        for montant in (0, -100):
            out = geniuspay_send_payout(
                amount=montant, phone="0700000000", operator="orange"
            )
            self.assertFalse(out["ok"])
            self.assertEqual(out["error"], "montant_invalide")

    def test_montant_non_numerique_refuse(self):
        out = geniuspay_send_payout(
            amount="beaucoup", phone="0700000000", operator="orange"
        )
        self.assertFalse(out["ok"])
        self.assertEqual(out["error"], "montant_invalide")

    def test_telephone_manquant_refuse(self):
        out = geniuspay_send_payout(amount=5000, phone="  ", operator="orange")
        self.assertFalse(out["ok"])
        self.assertEqual(out["error"], "telephone_manquant")

    def test_operateur_non_supporte_refuse(self):
        out = geniuspay_send_payout(
            amount=5000, phone="0700000000", operator="bitcoin"
        )
        self.assertFalse(out["ok"])
        self.assertIn("operateur_non_supporte", out["error"])


class SendPayoutSandboxTest(TestCase):
    """Sans clés API → mode simulation : versement auto-validé (démo de bout en bout)."""

    def test_versement_simule_reussit_et_renvoie_une_reference(self):
        out = geniuspay_send_payout(
            amount=Decimal("15000"),
            phone="0700000000",
            operator="orange",
            recipient_name="Plombier Test",
            reference="RET-42",
            description="Retrait BABIFIX #42",
        )
        self.assertTrue(out["ok"])
        self.assertEqual(out["status"], "completed")
        self.assertEqual(out["external_reference"], "RET-42")
        self.assertTrue(out.get("simulated"))

    def test_reference_generee_si_absente(self):
        out = geniuspay_send_payout(
            amount=1000, phone="0700000000", operator="wave"
        )
        self.assertTrue(out["ok"])
        self.assertTrue(out["external_reference"].startswith("PAYOUT-"))
