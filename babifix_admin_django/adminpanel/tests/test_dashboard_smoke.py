"""Smoke test : le dashboard admin doit se rendre sans exception, AVEC des données.

Reproduit l'erreur 500 vue en production sur la racine (qui redirige vers le
dashboard) après l'ajout du radar anti-fuite et des paiements groupés. Une base
vide ne suffit pas : il faut des paiements/réservations pour exercer les boucles.
"""
from datetime import timedelta
from decimal import Decimal

from django.contrib.auth.models import User
from django.test import Client as DjangoClient, TestCase
from django.utils import timezone

from adminpanel.models import (
    Abonnement, Category, Devis, Payment, Provider, Reservation, UserProfile, WalletTransaction,
)


class DashboardSmokeTest(TestCase):
    def setUp(self):
        self.admin = User.objects.create_superuser(
            "admin_smoke", "admin_smoke@babifix.ci", "Pwd12345!"
        )
        self.http = DjangoClient()
        self.http.force_login(self.admin)

        self.cat = Category.objects.create(nom="Plomberie", icone_slug="tuyau")
        self.presta = User.objects.create_user("prov_smoke", password="Pwd12345!")
        UserProfile.objects.create(user=self.presta, role="prestataire", active=True)
        self.cli = User.objects.create_user("cli_smoke", password="Pwd12345!")
        UserProfile.objects.create(user=self.cli, role="client", active=True)
        self.prov = Provider.objects.create(
            user=self.presta, nom="Plombier Test", specialite="Plomberie",
            ville="Abidjan", category=self.cat, statut=Provider.Status.VALID,
        )

        # Réservation « normale » + devis + paiement (exerce paiements_groupes).
        self.res = Reservation.objects.create(
            reference="RES-SMOKE", client="cli_smoke", prestataire="Plombier Test",
            montant=Decimal("50000"), statut="Terminee", client_user=self.cli,
            assigned_provider=self.prov, prestataire_user=self.presta,
            payment_type="MOBILE_MONEY",
        )
        Devis.objects.create(
            reservation=self.res, prestataire=self.prov, reference="DV-SMOKE",
            statut="ACCEPTE",
            sous_total=Decimal("50000"), total_ttc=Decimal("50000"),
            commission_rate=18, commission_montant=Decimal("9000"),
            net_prestataire=Decimal("41000"),
        )
        Payment.objects.create(
            reference="PAY-SMOKE", client="cli_smoke", prestataire="Plombier Test",
            montant=Decimal("50000"), commission=Decimal("9000"),
            etat=Payment.State.COMPLETE, reservation=self.res,
            type_paiement=Payment.TypePaiement.MOBILE_MONEY,
        )
        # Paiement SANS réservation (bloc « orphelin » du regroupement).
        Payment.objects.create(
            reference="PAY-ORPHAN", client="cli_smoke", prestataire="Plombier Test",
            montant=Decimal("1500"), commission=Decimal("0"),
            etat=Payment.State.COMPLETE,
            type_paiement=Payment.TypePaiement.MOBILE_MONEY,
        )

        # Réservation FLAGGÉE par le radar (exerce radar_visites).
        self.res_radar = Reservation.objects.create(
            reference="RES-SMOKE-RADAR", client="cli_smoke",
            prestataire="Plombier Test", montant=Decimal("0"),
            statut="DEVIS_EN_COURS", client_user=self.cli,
            assigned_provider=self.prov, prestataire_user=self.presta,
            caution_payee=True, caution_montant=Decimal("3000"),
            visite_effectuee=True, visite_effectuee_at=timezone.now(),
            visite_suspecte=True, visite_suspecte_at=timezone.now(),
            visite_suspecte_motif="Aucun devis envoyé.",
        )

    def test_dashboard_section_renders(self):
        r = self.http.get("/?section=dashboard")
        self.assertEqual(r.status_code, 200)

    def test_paiements_section_renders(self):
        r = self.http.get("/?section=paiements")
        self.assertEqual(r.status_code, 200)
        self.assertContains(r, "RES-SMOKE")

    def test_reservations_section_renders_avec_radar(self):
        r = self.http.get("/?section=reservations")
        self.assertEqual(r.status_code, 200)
        self.assertContains(r, "Radar anti-fuite")
        self.assertContains(r, "RES-SMOKE-RADAR")

    def test_radar_reste_visible_sans_visite_suspecte(self):
        # Aucune visite suspecte → le panneau doit RESTER affiché, en état
        # « rien à signaler ». Un panneau qui disparaît quand il n'y a rien ne
        # permet pas de savoir si la surveillance tourne réellement.
        self.res_radar.delete()
        r = self.http.get("/?section=reservations")
        self.assertEqual(r.status_code, 200)
        self.assertContains(r, "Radar anti-fuite")
        self.assertContains(r, "aucune visite suspecte")

    def test_sidebar_reservations_badge_sans_surbrillance_bleue(self):
        """Le badge compteur Reservations ne doit pas avoir de fond bleu type selectionne."""
        Reservation.objects.create(
            reference="RES-UNASSIGNED-BADGE",
            client="cli_smoke",
            prestataire="",
            montant=Decimal("10000"),
            statut="DEMANDE_ENVOYEE",
            client_user=self.cli,
            assigned_provider=None,
        )
        r = self.http.get("/?section=dashboard")
        self.assertEqual(r.status_code, 200)
        html = r.content.decode("utf-8")
        self.assertNotIn('<span class="nav-badge nav-badge--info" title="', html.split("<span>Reservations</span>")[1].split("</a>")[0])
        self.assertIn('<span class="nav-badge" title="', html.split("<span>Reservations</span>")[1].split("</a>")[0])

    def test_paiements_plus_recents_en_haut_tous_types(self):
        """Les paiements les plus recents doivent etre en haut sur dashboard, paiements et finances."""
        now = timezone.now()
        old_res = Reservation.objects.create(
            reference="RES-OLD-ORDER", client="cli_smoke", prestataire="Plombier Test",
            montant=Decimal("12000"), statut="Terminee", client_user=self.cli,
            assigned_provider=self.prov, payment_type="ESPECES",
            created_at=now - timedelta(days=5),
        )
        new_res = Reservation.objects.create(
            reference="RES-NEW-ORDER", client="cli_smoke", prestataire="Plombier Test",
            montant=Decimal("35000"), statut="Terminee", client_user=self.cli,
            assigned_provider=self.prov, payment_type="MOBILE_MONEY",
            created_at=now + timedelta(minutes=1),
        )
        # Ancien paiement especes vs recent paiement mobile money
        Payment.objects.create(
            reference="PAY-OLD-CASH", client="cli_smoke", prestataire="Plombier Test",
            montant=Decimal("12000"), commission=Decimal("1800"),
            etat=Payment.State.COMPLETE, reservation=old_res,
            type_paiement=Payment.TypePaiement.ESPECES,
            created_at=now - timedelta(days=5),
        )
        Payment.objects.create(
            reference="PAY-NEW-MOMO", client="cli_smoke", prestataire="Plombier Test",
            montant=Decimal("35000"), commission=Decimal("5250"),
            etat=Payment.State.COMPLETE, reservation=new_res,
            type_paiement=Payment.TypePaiement.MOBILE_MONEY,
            created_at=now + timedelta(minutes=1),
        )
        # Versements / retraits
        old_wt = WalletTransaction.objects.create(
            provider=self.prov, tx_type="debit", amount_fcfa=Decimal("5000"),
            status="success", reference="WT-OLD",
        )
        WalletTransaction.objects.filter(pk=old_wt.pk).update(created_at=now - timedelta(days=3))
        new_wt = WalletTransaction.objects.create(
            provider=self.prov, tx_type="debit", amount_fcfa=Decimal("8000"),
            status="pending", reference="WT-NEW",
        )
        # Abonnements
        old_ab = Abonnement.objects.create(
            client=self.cli, pack_nom="Pack Old", prix=Decimal("5000"),
            date_debut=now.date(), date_fin=now.date(),
        )
        Abonnement.objects.filter(pk=old_ab.pk).update(created_at=now - timedelta(days=2))
        new_ab = Abonnement.objects.create(
            client=self.cli, pack_nom="Pack New", prix=Decimal("10000"),
            date_debut=now.date(), date_fin=now.date(),
        )

        # 1. Dashboard : paiements recents
        r_dash = self.http.get("/?section=dashboard")
        self.assertEqual(r_dash.status_code, 200)
        dash_refs = [p.reference for p in r_dash.context["paiements"]]
        self.assertEqual(dash_refs[0], "PAY-NEW-MOMO")
        self.assertLess(dash_refs.index("PAY-NEW-MOMO"), dash_refs.index("PAY-OLD-CASH"))

        # 2. Section Paiements & Abonnements : groupes + tableau + abonnements + kanban
        r_pay = self.http.get("/?section=paiements")
        self.assertEqual(r_pay.status_code, 200)
        grp_refs = [g["reference"] for g in r_pay.context["paiements_groupes"]]
        self.assertEqual(grp_refs[0], "RES-NEW-ORDER")
        self.assertLess(grp_refs.index("RES-NEW-ORDER"), grp_refs.index("RES-OLD-ORDER"))
        ab_ids = [a.pk for a in r_pay.context["client_abonnements"]]
        self.assertEqual(ab_ids[0], new_ab.pk)

        # 3. Section Finances : paiements + versements
        r_fin = self.http.get("/?section=finances")
        self.assertEqual(r_fin.status_code, 200)
        fin_pay_refs = [p["reference"] for p in r_fin.context["finance_payments"]]
        self.assertEqual(fin_pay_refs[0], "PAY-NEW-MOMO")
        fin_wt_ids = [w.pk for w in r_fin.context["finance_versements"]]
        self.assertEqual(fin_wt_ids[0], new_wt.pk)

        # 4. Section Versements : retraits pending en tete + plus recents en haut
        r_po = self.http.get("/?section=payouts")
        self.assertEqual(r_po.status_code, 200)
        po_wt_ids = [w.pk for w in r_po.context["payout_withdrawals"]]
        self.assertEqual(po_wt_ids[0], new_wt.pk)

    def test_api_public_vitrine_returns_real_live_metrics_and_cities(self):
        """/api/public/vitrine/ doit retourner des KPIs, villes et flux reels (aucune valeur inventee)."""
        from django.core.cache import cache as _cache

        _cache.clear()
        r = self.http.get("/api/public/vitrine/")
        self.assertEqual(r.status_code, 200)
        data = r.json()
        self.assertIn("stats", data)
        self.assertIn("kpis", data)
        self.assertIn("cities", data)
        self.assertIn("live_feed", data)
        self.assertGreaterEqual(data["stats"]["providers_count"], 1)
        self.assertGreaterEqual(data["stats"]["reservations_total"], 1)
        self.assertEqual(len(data["kpis"]), 4)
        abidjan = next((c for c in data["cities"] if c["key"] == "abidjan"), None)
        self.assertIsNotNone(abidjan)
        self.assertTrue(abidjan["has_activity"])
        self.assertGreaterEqual(abidjan["providers_count"], 1)
        self.assertNotIn("10,000+", str(data))
        self.assertNotIn("50,000+", str(data))
