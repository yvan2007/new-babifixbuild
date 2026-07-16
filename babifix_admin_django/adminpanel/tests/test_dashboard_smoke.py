"""Smoke test : le dashboard admin doit se rendre sans exception, AVEC des données.

Reproduit l'erreur 500 vue en production sur la racine (qui redirige vers le
dashboard) après l'ajout du radar anti-fuite et des paiements groupés. Une base
vide ne suffit pas : il faut des paiements/réservations pour exercer les boucles.
"""
from decimal import Decimal

from django.contrib.auth.models import User
from django.test import Client as DjangoClient, TestCase
from django.utils import timezone

from adminpanel.models import (
    Category, Devis, Payment, Provider, Reservation, UserProfile,
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
