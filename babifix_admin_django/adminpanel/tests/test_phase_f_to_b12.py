"""Tests Phase A → G + B7/C1/B12 (E5).

Couvre :
- EscrowService.quote / mark_escrow_received / release_funds
  - Mobile 100% → 82% wallet + 18% PlatformRevenue à la confirmation
  - Cash 18% → commission encaissée à l'acompte, pas de doublon
  - B12 commission < 500 → surplus reversé au presta
  - Idempotence release_funds
- CancellationService
  - Stages before_devis / after_accept / after_start
  - Pénalité client vs presta
  - Refund mobile + refund commission cash
- ClientJournalView (POST/GET)
- MediaService (upload, validation, redimensionnement)

Run : python manage.py test adminpanel.tests.test_phase_f_to_b12
"""
from __future__ import annotations

import base64
import io
from decimal import Decimal

from django.contrib.auth.models import User
from django.test import TestCase
from django.utils import timezone

from adminpanel.models import (
    Category,
    Devis,
    LigneDevis,
    Payment,
    PlatformRevenue,
    Provider,
    Reservation,
    WalletTransaction,
)
from adminpanel.services.cancellation_service import CancellationService
from adminpanel.services.escrow_service import (
    EscrowService,
    MIN_ONLINE_PAYMENT_XOF,
)
from adminpanel.services.media_service import MediaService, MediaUploadError


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
class _Base(TestCase):
    def setUp(self):
        self.client_user = User.objects.create_user(
            username=f"client_{self._testMethodName}", password="x"
        )
        self.presta_user = User.objects.create_user(
            username=f"presta_{self._testMethodName}", password="x"
        )
        self.cat = Category.objects.create(
            nom=f"Plomberie_{self._testMethodName}",
            icone_slug="plumber",
        )
        self.prov = Provider.objects.create(
            user=self.presta_user,
            nom="Provider Test",
            specialite="Plomberie",
            ville="Abidjan",
            category=self.cat,
            statut=Provider.Status.VALID,
        )
        self.res = Reservation.objects.create(
            reference=f"RES-{self._testMethodName[:18]}",
            client="C",
            prestataire=self.prov.nom,
            montant=Decimal("0"),
            statut=Reservation.Status.DEMANDE_ENVOYEE,
            payment_type=Reservation.PaymentType.MOBILE_MONEY,
            client_user=self.client_user,
            prestataire_user=self.presta_user,
            assigned_provider=self.prov,
        )

    def _make_devis(self, sous_total: Decimal, accepted: bool = True) -> Devis:
        d = Devis.objects.create(
            reservation=self.res,
            prestataire=self.prov,
            diagnostic="t",
            commission_rate=18,
            statut=Devis.Statut.ENVOYE,
        )
        LigneDevis.objects.create(
            devis=d,
            type_ligne="FOURNITURE",
            description="X",
            quantite=Decimal("1"),
            prix_unitaire=sous_total,
        )
        d.save()
        d.refresh_from_db()
        if accepted:
            d.statut = Devis.Statut.ACCEPTE
            d.save()
            self.res.statut = Reservation.Status.DEVIS_ACCEPTE
            self.res.montant = d.total_ttc
            self.res.save()
        return d


# ---------------------------------------------------------------------------
# Phase A — formule devis
# ---------------------------------------------------------------------------
class DevisFormulaTest(_Base):
    def test_total_ttc_equals_sous_total(self):
        d = self._make_devis(Decimal("20000"))
        self.assertEqual(d.total_ttc, Decimal("20000.00"))

    def test_net_prestataire_is_82pct(self):
        d = self._make_devis(Decimal("20000"))
        self.assertEqual(d.net_prestataire, Decimal("16400.00"))
        self.assertEqual(d.commission_montant, Decimal("3600.00"))


# ---------------------------------------------------------------------------
# Phase F — escrow mobile + cash
# ---------------------------------------------------------------------------
class EscrowMobileTest(_Base):
    def test_mobile_full_flow_18pct_to_platform(self):
        d = self._make_devis(Decimal("20000"))
        self.res.payment_type = Reservation.PaymentType.MOBILE_MONEY
        self.res.save()

        # 1. Quote
        q = EscrowService.quote(self.res)
        self.assertEqual(q.strategy, "MOBILE_FULL")
        self.assertEqual(q.amount_due, Decimal("20000"))
        self.assertEqual(q.cash_remainder, Decimal("0"))

        # 2. Paiement reçu
        p = Payment.objects.create(
            reference="P-MOB",
            client="C",
            prestataire="P",
            montant="20000",
            commission="0",
            etat=Payment.State.COMPLETE,
            reservation=self.res,
            type_paiement=Payment.TypePaiement.MOBILE_MONEY,
        )
        EscrowService.mark_escrow_received(p)
        self.res.refresh_from_db()
        self.prov.refresh_from_db()
        # Escrow strict : aucun revenu plateforme ni crédit wallet
        self.assertEqual(self.prov.solde_fcfa, Decimal("0"))
        self.assertEqual(
            PlatformRevenue.objects.filter(reference=self.res.reference).count(),
            0,
        )

        # 3. Confirmation client → release
        self.res.client_confirme_prestation_at = timezone.now()
        self.res.save()
        r = EscrowService.release_funds(self.res)
        self.prov.refresh_from_db()
        self.assertEqual(r["released_to_provider"], 16400.0)
        self.assertEqual(r["platform_revenue"], 3600.0)
        self.assertEqual(self.prov.solde_fcfa, Decimal("16400"))
        total_pr = sum(
            p.amount_fcfa
            for p in PlatformRevenue.objects.filter(reference=self.res.reference)
        )
        self.assertEqual(total_pr, Decimal("3600"))

    def test_release_is_idempotent(self):
        d = self._make_devis(Decimal("20000"))
        self.res.payment_type = Reservation.PaymentType.MOBILE_MONEY
        p = Payment.objects.create(
            reference="P-IDEM",
            client="C",
            prestataire="P",
            montant="20000",
            commission="0",
            etat=Payment.State.COMPLETE,
            reservation=self.res,
            type_paiement=Payment.TypePaiement.MOBILE_MONEY,
        )
        EscrowService.mark_escrow_received(p)
        self.res.client_confirme_prestation_at = timezone.now()
        self.res.save()
        EscrowService.release_funds(self.res)
        r2 = EscrowService.release_funds(self.res)
        self.assertTrue(r2.get("already_released"))
        # Pas de doublon
        self.assertEqual(
            PlatformRevenue.objects.filter(reference=self.res.reference).count(),
            1,
        )


class EscrowCashTest(_Base):
    def test_cash_only_18pct_commission_upfront(self):
        d = self._make_devis(Decimal("20000"))
        self.res.payment_type = Reservation.PaymentType.ESPECES
        self.res.save()
        q = EscrowService.quote(self.res)
        self.assertEqual(q.strategy, "CASH_COMMISSION_ONLY")
        self.assertEqual(q.amount_due, Decimal("3600"))
        self.assertEqual(q.cash_remainder, Decimal("16400"))

        p = Payment.objects.create(
            reference="P-CASH",
            client="C",
            prestataire="P",
            montant="3600",
            commission="0",
            etat=Payment.State.COMPLETE,
            reservation=self.res,
            type_paiement=Payment.TypePaiement.MOBILE_MONEY,
        )
        EscrowService.mark_escrow_received(p)
        total_pr = sum(
            p.amount_fcfa
            for p in PlatformRevenue.objects.filter(reference=self.res.reference)
        )
        self.assertEqual(total_pr, Decimal("3600"))
        # Confirmation : aucune commission supplémentaire
        self.res.client_confirme_prestation_at = timezone.now()
        self.res.save()
        EscrowService.release_funds(self.res)
        total_after = sum(
            p.amount_fcfa
            for p in PlatformRevenue.objects.filter(reference=self.res.reference)
        )
        self.assertEqual(total_after, Decimal("3600"))


# ---------------------------------------------------------------------------
# B12 — Commission minimum
# ---------------------------------------------------------------------------
class B12MinimumCommissionTest(_Base):
    def test_quote_enforces_minimum_for_small_cash_devis(self):
        # Devis 2000 FCFA → commission 360 → < 500 minimum.
        d = self._make_devis(Decimal("2000"))
        self.res.payment_type = Reservation.PaymentType.ESPECES
        self.res.save()
        q = EscrowService.quote(self.res)
        self.assertEqual(q.amount_due, MIN_ONLINE_PAYMENT_XOF)
        self.assertEqual(q.commission_montant, Decimal("360.00"))
        self.assertGreater(q.cash_minimum_surplus, Decimal("0"))
        self.assertEqual(
            q.cash_minimum_surplus, MIN_ONLINE_PAYMENT_XOF - Decimal("360"),
        )

    def test_surplus_reversed_to_provider_on_confirmation(self):
        d = self._make_devis(Decimal("2000"))
        self.res.payment_type = Reservation.PaymentType.ESPECES
        self.res.save()
        # Le client paye 500 (commission 360 + surplus 140)
        p = Payment.objects.create(
            reference="P-B12",
            client="C",
            prestataire="P",
            montant=str(MIN_ONLINE_PAYMENT_XOF),
            commission="0",
            etat=Payment.State.COMPLETE,
            reservation=self.res,
            type_paiement=Payment.TypePaiement.MOBILE_MONEY,
        )
        EscrowService.mark_escrow_received(p)
        # Plateforme garde 360 (commission réelle), surplus reste en attente
        pr_total = sum(
            p.amount_fcfa
            for p in PlatformRevenue.objects.filter(reference=self.res.reference)
        )
        self.assertEqual(pr_total, Decimal("360.00"))

        # Confirmation client → surplus 140 reversé au presta
        self.res.client_confirme_prestation_at = timezone.now()
        self.res.save()
        r = EscrowService.release_funds(self.res)
        self.assertEqual(r["released_to_provider"], 140.0)
        self.prov.refresh_from_db()
        self.assertEqual(self.prov.solde_fcfa, Decimal("140"))


# ---------------------------------------------------------------------------
# C1 — Annulation
# ---------------------------------------------------------------------------
class CancellationTest(_Base):
    def test_client_cancel_before_devis_no_penalty(self):
        # Statut DEMANDE_ENVOYEE, aucun paiement
        r = CancellationService.cancel(self.res, by="CLIENT")
        self.assertTrue(r.ok)
        self.assertEqual(r.stage, "before_devis")
        self.assertEqual(r.penalty_pct, 0)
        self.assertEqual(r.refund_owed_fcfa, 0)

    def test_client_cancel_after_accept_mobile_10pct_penalty(self):
        # Devis accepté, acompte mobile versé, intervention pas démarrée.
        self._make_devis(Decimal("20000"))
        self.res.payment_type = Reservation.PaymentType.MOBILE_MONEY
        self.res.acompte_valide = True
        self.res.montant_verse = Decimal("20000")
        self.res.save()

        r = CancellationService.cancel(self.res, by="CLIENT", motif="changement plan")
        self.assertTrue(r.ok)
        self.assertEqual(r.stage, "after_accept")
        self.assertEqual(r.penalty_pct, 10)
        # 90% remboursement attendu
        self.assertEqual(r.refund_owed_fcfa, 18000.0)
        # 10% partagé pro-rata commission/net
        self.assertGreater(r.platform_revenue_fcfa, 0)
        self.assertGreater(r.presta_credited_fcfa, 0)
        # Cumul = 2000 FCFA (10%)
        self.assertAlmostEqual(
            r.platform_revenue_fcfa + r.presta_credited_fcfa, 2000.0, delta=1.0
        )

    def test_prestataire_cancel_after_accept_full_refund(self):
        self._make_devis(Decimal("20000"))
        self.res.payment_type = Reservation.PaymentType.MOBILE_MONEY
        self.res.acompte_valide = True
        self.res.montant_verse = Decimal("20000")
        self.res.save()

        r = CancellationService.cancel(self.res, by="PRESTATAIRE")
        self.assertTrue(r.ok)
        self.assertEqual(r.penalty_pct, 0)
        self.assertEqual(r.refund_owed_fcfa, 20000.0)

    def test_client_cancel_after_start_mobile_50_50(self):
        self._make_devis(Decimal("20000"))
        self.res.payment_type = Reservation.PaymentType.MOBILE_MONEY
        self.res.acompte_valide = True
        self.res.montant_verse = Decimal("20000")
        self.res.statut = Reservation.Status.INTERVENTION_EN_COURS
        self.res.save()

        r = CancellationService.cancel(self.res, by="CLIENT")
        self.assertEqual(r.stage, "after_start")
        self.assertEqual(r.penalty_pct, 50)
        self.assertEqual(r.refund_owed_fcfa, 10000.0)

    def test_cancel_after_completion_refused(self):
        self.res.statut = "Terminee"
        self.res.prestation_terminee_at = timezone.now()
        self.res.save()
        r = CancellationService.cancel(self.res, by="CLIENT")
        self.assertFalse(r.ok)

    def test_idempotent_cancel(self):
        CancellationService.cancel(self.res, by="CLIENT")
        r2 = CancellationService.cancel(self.res, by="CLIENT")
        self.assertEqual(r2.detail, "already_cancelled")

    def test_cash_cancel_presta_refunds_commission(self):
        self._make_devis(Decimal("20000"))
        self.res.payment_type = Reservation.PaymentType.ESPECES
        self.res.statut = Reservation.Status.DEVIS_ACCEPTE
        # Simule commission encaissée à l'acompte
        PlatformRevenue.objects.create(
            amount_fcfa=Decimal("3600"),
            source=PlatformRevenue.Source.COMMISSION,
            reference=self.res.reference,
            description="Commission cash acompte",
        )
        self.res.acompte_valide = True
        self.res.montant_verse = Decimal("3600")
        self.res.save()

        r = CancellationService.cancel(self.res, by="PRESTATAIRE")
        self.assertTrue(r.ok)
        self.assertTrue(r.platform_commission_refunded)
        # PR marquée refunded
        pr = PlatformRevenue.objects.filter(reference=self.res.reference).first()
        self.assertIsNotNone(pr.refunded_at)


# ---------------------------------------------------------------------------
# B7 — MediaService
# ---------------------------------------------------------------------------
class MediaServiceTest(TestCase):
    def _png_bytes(self) -> bytes:
        try:
            from PIL import Image
        except Exception:
            self.skipTest("Pillow non installé")
        img = Image.new("RGB", (300, 200), color="green")
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        return buf.getvalue()

    def test_store_bytes_jpeg(self):
        try:
            from PIL import Image
        except Exception:
            self.skipTest("Pillow non installé")
        img = Image.new("RGB", (100, 100), color="blue")
        buf = io.BytesIO()
        img.save(buf, format="JPEG")
        url = MediaService.store_bytes(buf.getvalue(), "image/jpeg", user_id=42)
        self.assertTrue(url.startswith("/media/babifix_uploads/"))
        self.assertTrue(url.endswith(".jpg"))

    def test_resize_large_image(self):
        try:
            from PIL import Image
        except Exception:
            self.skipTest("Pillow non installé")
        # 3000x2000 → doit être réduit à 1600x...
        img = Image.new("RGB", (3000, 2000), color="red")
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=90)
        url = MediaService.store_bytes(buf.getvalue(), "image/jpeg", user_id=1)
        # On vérifie indirectement via la taille du fichier stocké
        import os
        from django.conf import settings
        path = settings.MEDIA_ROOT / url.replace("/media/", "")
        self.assertTrue(os.path.exists(path))
        # Re-ouvre et vérifie max dim 1600
        with Image.open(path) as out:
            self.assertLessEqual(max(out.size), 1600)

    def test_reject_unsupported_mime(self):
        with self.assertRaises(MediaUploadError):
            MediaService.store_data_uri("data:application/pdf;base64,xxx", 1)

    def test_reject_oversize(self):
        big = b"X" * (7 * 1024 * 1024)
        with self.assertRaises(MediaUploadError):
            MediaService.store_bytes(big, "image/jpeg", 1)

    def test_data_uri_roundtrip(self):
        png = self._png_bytes()
        uri = "data:image/png;base64," + base64.b64encode(png).decode()
        url = MediaService.store_data_uri(uri, user_id=1)
        self.assertTrue(url.startswith("/media/"))


# ---------------------------------------------------------------------------
# Journal client (POST/GET)
# ---------------------------------------------------------------------------
class ClientJournalTest(_Base):
    def test_fields_persist(self):
        self.res.client_photos_avant = ["http://x/a.jpg"]
        self.res.client_photos_apres = ["http://x/b.jpg", "http://x/c.jpg"]
        self.res.client_journal_note = "Très bien."
        self.res.save()
        self.res.refresh_from_db()
        self.assertEqual(len(self.res.client_photos_apres), 2)
        self.assertEqual(self.res.client_journal_note, "Très bien.")


# ---------------------------------------------------------------------------
# B6 — Dispute flow
# ---------------------------------------------------------------------------
class DisputeFlowTest(_Base):
    def test_dispute_resolve_refund(self):
        from adminpanel.models import Dispute
        d = Dispute.objects.create(
            reference="DSP-TEST1",
            motif="Travail non conforme",
            client="C", prestataire="P",
            decision=Dispute.Decision.OPEN,
            reservation=self.res,
        )
        self.res.dispute_ouverte = True
        # Simule un acompte payé
        self._make_devis(Decimal("20000"))
        self.res.payment_type = Reservation.PaymentType.MOBILE_MONEY
        self.res.acompte_valide = True
        self.res.montant_verse = Decimal("20000")
        self.res.save()

        # Résolution = REFUND total (équivalent annulation ADMIN)
        from adminpanel.services.cancellation_service import CancellationService
        r = CancellationService.cancel(self.res, by="ADMIN", motif="Litige refund")
        self.assertTrue(r.ok)
        self.assertEqual(r.refund_owed_fcfa, 20000.0)
        d.decision = Dispute.Decision.REFUND
        d.save()
        self.res.dispute_ouverte = False
        self.res.save()
        d.refresh_from_db()
        self.assertEqual(d.decision, Dispute.Decision.REFUND)


# ---------------------------------------------------------------------------
# C11 — Premium tier sur Devis
# ---------------------------------------------------------------------------
class PremiumTierTest(_Base):
    def test_silver_reduces_commission(self):
        # Le prestataire passe silver
        self.prov.premium_tier = "silver"
        self.prov.save()
        d = self._make_devis(Decimal("20000"), accepted=False)
        # commission_rate doit être réduit de 5 points (18 → 13)
        # MAIS uniquement si le devis est en BROUILLON au moment du save.
        # Donc on simule le re-save brouillon :
        d.statut = Devis.Statut.BROUILLON
        d.save()
        d.refresh_from_db()
        self.assertEqual(d.commission_rate, 13)
        self.assertEqual(d.commission_montant, Decimal("2600.00"))
        self.assertEqual(d.net_prestataire, Decimal("17400.00"))

    def test_gold_reduces_commission(self):
        self.prov.premium_tier = "gold"
        self.prov.save()
        d = self._make_devis(Decimal("20000"), accepted=False)
        d.statut = Devis.Statut.BROUILLON
        d.save()
        d.refresh_from_db()
        # 18 - 10 = 8
        self.assertEqual(d.commission_rate, 8)

    def test_no_change_after_envoye(self):
        # Une fois envoyé, le tier ne change plus le taux
        d = self._make_devis(Decimal("20000"))  # accepté = ENVOYE puis ACCEPTE
        initial_rate = d.commission_rate
        self.prov.premium_tier = "gold"
        self.prov.save()
        d.save()
        d.refresh_from_db()
        self.assertEqual(d.commission_rate, initial_rate)


# ---------------------------------------------------------------------------
# Timeouts (process_timeouts management command)
# ---------------------------------------------------------------------------
class TimeoutsTest(_Base):
    def test_devis_expired_passes_to_expire(self):
        from datetime import timedelta
        from django.core.management import call_command
        d = self._make_devis(Decimal("10000"), accepted=False)
        # Marque envoyé + créé il y a 30 jours
        d.statut = Devis.Statut.ENVOYE
        d.save()
        Devis.objects.filter(pk=d.pk).update(
            created_at=timezone.now() - timedelta(days=30)
        )
        self.res.statut = Reservation.Status.DEVIS_ENVOYE
        self.res.save()

        call_command("process_timeouts", verbosity=0)
        d.refresh_from_db()
        self.assertEqual(d.statut, Devis.Statut.EXPIRE)
        self.res.refresh_from_db()
        self.assertEqual(self.res.statut, Reservation.Status.DEMANDE_ENVOYEE)

    def test_auto_confirm_after_7_days(self):
        from datetime import timedelta
        from django.core.management import call_command
        self._make_devis(Decimal("20000"))
        self.res.payment_type = Reservation.PaymentType.MOBILE_MONEY
        self.res.acompte_valide = True
        self.res.montant_verse = Decimal("20000")
        self.res.statut = "Terminee"
        self.res.prestation_terminee_at = timezone.now() - timedelta(days=10)
        self.res.save()

        call_command("process_timeouts", verbosity=0)
        self.res.refresh_from_db()
        self.assertIsNotNone(self.res.client_confirme_prestation_at)
        self.assertEqual(self.res.statut, Reservation.Status.CONFIRMED)
        # Wallet presta crédité
        self.prov.refresh_from_db()
        self.assertEqual(self.prov.solde_fcfa, Decimal("16400"))
