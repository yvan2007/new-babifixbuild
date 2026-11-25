"""
Tests d'integration de la Refonte Smart BABIFIX :
  - SOS 24/7 (eligibilite, horaire jour/nuit, atomicite premier arrive premier servi)
  - Privacy & Visite de diagnostic (preservations de address_is_approximate, visite gratuite 0 FCFA)
  - Integrite financiere (abonnements expires, Devis.remise, auto_confirm_interventions, idempotence GeniusPay)
  - Recus PDF exacts (acompte partiel, mois en francais, commission masquee client) + emails OTP reset
  - Geolocalisation regionale (Bouake/Yamoussoukro conserves et visibles au client national)
"""
from datetime import datetime, timedelta, timezone as dt_tz
import json
from decimal import Decimal
from unittest.mock import patch

from django.contrib.auth.models import User
from django.core import mail
from django.test import Client as DjangoClient, TestCase, override_settings
from django.utils import timezone

from adminpanel.auth import create_token
from adminpanel.geniuspay import _finalize_completed_payment
from adminpanel.models import (
    Category,
    Devis,
    LigneDevis,
    Payment,
    PlatformConfig,
    Provider,
    Reservation,
    UserProfile,
)
from adminpanel.services.invoice_service import InvoiceService
from adminpanel.services.provider_subscription_service import ProviderSubscriptionService
from adminpanel.services.sos_service import check_sos_eligibility, is_abidjan_night_or_sunday
from adminpanel.services.wallet_service import _get_effective_commission_rate
from adminpanel.tasks import auto_confirm_interventions
from adminpanel.views_v2 import _send_reset_email


def _mk_user(username, role, email):
    u = User.objects.create_user(username=username, password="Pwd12345!", email=email)
    UserProfile.objects.create(user=u, role=role, active=True)
    return u, create_token(u.id, role)


class RefonteSmartTests(TestCase):
    def setUp(self):
        self.http = DjangoClient()
        PlatformConfig.get_solo()
        self.cat_plomb = Category.objects.create(
            nom="Plomberie", icone_slug="plomberie", supports_sos=True, actif=True
        )
        self.cat_paint = Category.objects.create(
            nom="Peinture", icone_slug="pinceau", supports_sos=False, actif=True
        )
        self.cli, self.cli_tok = _mk_user("cli_smart", "client", "cli_smart@babifix.ci")
        self.p1_u, self.p1_tok = _mk_user("prov_smart_1", "prestataire", "p1@babifix.ci")
        self.p2_u, self.p2_tok = _mk_user("prov_smart_2", "prestataire", "p2@babifix.ci")
        self.prov1 = Provider.objects.create(
            user=self.p1_u,
            nom="Plombier Cocody 1",
            specialite="Plomberie",
            ville="Cocody, Abidjan",
            category=self.cat_plomb,
            statut=Provider.Status.VALID,
            disponible=True,
            latitude=5.360,
            longitude=-3.987,
        )
        self.prov2 = Provider.objects.create(
            user=self.p2_u,
            nom="Plombier Cocody 2",
            specialite="Plomberie",
            ville="Cocody, Abidjan",
            category=self.cat_plomb,
            statut=Provider.Status.VALID,
            disponible=True,
            latitude=5.365,
            longitude=-3.990,
        )

    def _post(self, url, tok, payload=None):
        return self.http.post(
            url,
            data=json.dumps(payload or {}),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {tok}",
        )

    def _get(self, url, tok):
        return self.http.get(url, HTTP_AUTHORIZATION=f"Bearer {tok}")

    # 1. SOS 24/7 -------------------------------------------------------------
    def test_sos_eligibility_and_day_night_tariff(self):
        day_dt = datetime(2026, 11, 23, 14, 0, tzinfo=dt_tz.utc)  # Lundi 14h UTC
        night_dt = datetime(2026, 11, 23, 22, 0, tzinfo=dt_tz.utc)  # Lundi 22h UTC
        sunday_dt = datetime(2026, 11, 22, 11, 0, tzinfo=dt_tz.utc)  # Dimanche 11h UTC

        self.assertFalse(is_abidjan_night_or_sunday(day_dt))
        self.assertTrue(is_abidjan_night_or_sunday(night_dt))
        self.assertTrue(is_abidjan_night_or_sunday(sunday_dt))

        r_day = check_sos_eligibility(category_id=self.cat_plomb.id, title="Plomberie", now_dt=day_dt)
        self.assertTrue(r_day["eligible"])
        self.assertEqual(r_day["fee_fcfa"], 1500)

        r_night = check_sos_eligibility(category_id=self.cat_plomb.id, title="Plomberie", now_dt=night_dt)
        self.assertTrue(r_night["eligible"])
        self.assertEqual(r_night["fee_fcfa"], 2500)

        r_paint = check_sos_eligibility(category_id=self.cat_paint.id, title="Peinture", now_dt=day_dt)
        self.assertFalse(r_paint["eligible"])

        resp = self._get(f"/api/client/sos/preview/?category_id={self.cat_plomb.id}", self.cli_tok)
        self.assertEqual(resp.status_code, 200)
        self.assertTrue(resp.json()["eligible"])

    def test_sos_rejects_non_eligible_category(self):
        resp = self._post(
            "/api/client/reservations",
            self.cli_tok,
            {
                "title": "Peinture salon",
                "category_id": self.cat_paint.id,
                "sos_mode": True,
                "description_probleme": "Repeindre un mur",
                "latitude": 5.361,
                "longitude": -3.988,
            },
        )
        self.assertEqual(resp.status_code, 400)
        self.assertEqual(resp.json()["error"], "sos_not_eligible")

    def test_sos_atomic_first_claim_wins_and_keeps_address_masked(self):
        resp = self._post(
            "/api/client/reservations",
            self.cli_tok,
            {
                "title": "Plomberie fuite urgente",
                "category_id": self.cat_plomb.id,
                "sos_mode": True,
                "description_probleme": "Tuyau casse sous evier",
                "address_street": "Rue des Jardins 45",
                "address_quartier": "Cocody",
                "address_ville": "Abidjan",
                "latitude": 5.361,
                "longitude": -3.988,
            },
        )
        self.assertEqual(resp.status_code, 201, resp.content)
        body = resp.json()
        ref = body["reference"]
        self.assertTrue(body["sos_mode"])
        self.assertGreaterEqual(body["alerted_providers_count"], 2)

        # Les deux artisans voient l'alerte SOS dans leur liste
        lst1 = self._get("/api/prestataire/requests", self.p1_tok).json()["items"]
        self.assertTrue(any(it["reference"] == ref and it["sos_unclaimed"] for it in lst1))

        # 1er artisan reclame la mission -> 200 OK
        c1 = self._post(f"/api/prestataire/requests/{ref}/sos-claim/", self.p1_tok)
        self.assertEqual(c1.status_code, 200, c1.content)

        # 2e artisan tente de reclamer la meme mission -> 409 Conflict
        c2 = self._post(f"/api/prestataire/requests/{ref}/sos-claim/", self.p2_tok)
        self.assertEqual(c2.status_code, 409)
        self.assertEqual(c2.json()["error"], "sos_already_claimed")

        # T3 Privacy : l'adresse fine reste masquee avant paiement caution/devis
        res = Reservation.objects.get(reference=ref)
        self.assertTrue(res.address_is_approximate)
        self.assertEqual(res.assigned_provider_id, self.prov1.id)

    # 2. Visite & Privacy -----------------------------------------------------
    def test_accept_keeps_address_masked_and_free_visit_zero_fcfa(self):
        res = Reservation.objects.create(
            reference="RES-PRIV-1",
            title="Plomberie",
            client="cli_smart",
            prestataire=self.prov1.nom,
            montant=Decimal("0"),
            statut=Reservation.Status.DEMANDE_ENVOYEE,
            client_user=self.cli,
            assigned_provider=self.prov1,
            prestataire_user=self.p1_u,
            address_street="Rue secrete 99",
            address_quartier="Cocody",
            address_ville="Abidjan",
            address_is_approximate=True,
        )
        r_acc = self._post(
            f"/api/prestataire/requests/{res.reference}/decision",
            self.p1_tok,
            {"decision": "accept"},
        )
        self.assertEqual(r_acc.status_code, 200)
        res.refresh_from_db()
        self.assertTrue(res.address_is_approximate)

        # Preset Visite gratuite (0 FCFA)
        r_vis = self._post(
            f"/api/prestataire/requests/{res.reference}/request-visit",
            self.p1_tok,
            {"caution_montant": 0, "caution_motif": "Diagnostic gratuit"},
        )
        self.assertEqual(r_vis.status_code, 200, r_vis.content)
        res.refresh_from_db()
        self.assertEqual(res.statut, Reservation.Status.VISITE_DIAGNOSTIC)
        self.assertEqual(res.caution_montant, Decimal("0"))
        self.assertTrue(res.caution_payee)
        self.assertFalse(res.address_is_approximate)

    # 3. Integrite Financiere & Abonnements ----------------------------------
    def test_expired_premium_resets_commission_and_devis_remise(self):
        self.prov1.is_premium = True
        self.prov1.premium_tier = "gold"
        self.prov1.premium_until = timezone.now() - timedelta(days=2)
        self.prov1.save()

        sub = ProviderSubscriptionService.get_subscription(self.prov1)
        self.assertIsNone(sub)
        self.prov1.refresh_from_db()
        self.assertFalse(self.prov1.is_premium)
        self.assertEqual(self.prov1.premium_tier, "standard")
        self.assertEqual(ProviderSubscriptionService.calculate_effective_commission(self.prov1), 18)
        self.assertEqual(_get_effective_commission_rate(self.prov1), Decimal("0.18"))

        # Test Devis.save() avec remise
        res = Reservation.objects.create(
            reference="RES-REM-1",
            title="Plomberie",
            client="cli_smart",
            prestataire=self.prov1.nom,
            montant=Decimal("0"),
            statut=Reservation.Status.DEVIS_EN_COURS,
            client_user=self.cli,
            assigned_provider=self.prov1,
            prestataire_user=self.p1_u,
        )
        devis = Devis.objects.create(
            reference="",
            reservation=res,
            prestataire=self.prov1,
            commission_rate=18,
            remise=Decimal("2000"),
            statut=Devis.Statut.ENVOYE,
        )
        LigneDevis.objects.create(
            devis=devis,
            type_ligne=LigneDevis.TypeLigne.MAIN_OEUVRE,
            description="Reparation fuite",
            quantite=1,
            prix_unitaire=Decimal("10000"),
        )
        devis.save()
        self.assertEqual(devis.total_ttc, Decimal("8000"))
        self.assertEqual(devis.commission_montant, Decimal("1440"))
        self.assertEqual(devis.net_prestataire, Decimal("6560"))

    def test_auto_confirm_48h_releases_escrow_funds(self):
        res = Reservation.objects.create(
            reference="RES-48H-1",
            title="Plomberie",
            client="cli_smart",
            prestataire=self.prov1.nom,
            statut=Reservation.Status.WAITING_CLIENT,
            payment_type=Reservation.PaymentType.MOBILE_MONEY,
            client_user=self.cli,
            assigned_provider=self.prov1,
            prestataire_user=self.p1_u,
            montant=Decimal("10000"),
            montant_verse=Decimal("10000"),
            acompte_valide=True,
            solde_valide=True,
            prestation_terminee_at=timezone.now() - timedelta(hours=50),
        )
        dev48 = Devis.objects.create(
            reference="DEV-48H-1",
            reservation=res,
            prestataire=self.prov1,
            commission_rate=18,
            statut=Devis.Statut.ACCEPTE,
        )
        LigneDevis.objects.create(
            devis=dev48,
            type_ligne=LigneDevis.TypeLigne.MAIN_OEUVRE,
            description="Prestation plomberie 48h",
            quantite=1,
            prix_unitaire=Decimal("10000"),
        )
        dev48.save()
        Payment.objects.create(
            reference="PAY-48H-1",
            reservation=res,
            client="cli_smart",
            prestataire=self.prov1.nom,
            montant=Decimal("10000"),
            commission=Decimal("0"),
            etat=Payment.State.COMPLETE,
            type_paiement="WAVE",
        )
        solde_before = self.prov1.solde_fcfa
        res_dict = auto_confirm_interventions()
        self.assertEqual(res_dict.get("confirmed"), 1)
        res.refresh_from_db()
        self.prov1.refresh_from_db()
        self.assertEqual(res.statut, Reservation.Status.DONE)
        self.assertIsNotNone(res.client_confirme_prestation_at)
        self.assertGreater(self.prov1.solde_fcfa, solde_before)

    def test_geniuspay_finalize_idempotent_under_double_call(self):
        res = Reservation.objects.create(
            reference="RES-GP-1",
            title="Plomberie",
            client="cli_smart",
            prestataire=self.prov1.nom,
            statut=Reservation.Status.DEVIS_ACCEPTE,
            payment_type=Reservation.PaymentType.MOBILE_MONEY,
            client_user=self.cli,
            assigned_provider=self.prov1,
            prestataire_user=self.p1_u,
            montant=Decimal("10000"),
        )
        pay = Payment.objects.create(
            reference="GP-TEST-IDEM-1",
            reservation=res,
            client="cli_smart",
            prestataire=self.prov1.nom,
            montant=Decimal("3000"),
            commission=Decimal("0"),
            etat=Payment.State.PENDING,
            type_paiement="WAVE",
        )
        with patch("adminpanel.geniuspay._send_receipt_email"):
            first = _finalize_completed_payment(pay.pk, verify_amount=3000)
            second = _finalize_completed_payment(pay.pk, verify_amount=3000)
        self.assertTrue(first[0])
        self.assertFalse(second[0])
        self.assertEqual(second[2], "already_processed")
        res.refresh_from_db()
        self.assertEqual(res.montant_verse, Decimal("3000"))

    # 4. Recus PDF & Emails --------------------------------------------------
    def test_partial_acompte_invoice_reconciliation_and_french_date(self):
        res = Reservation.objects.create(
            reference="RES-FAC-25",
            title="Plomberie sanitaire",
            client="yvannn",
            prestataire=self.prov1.nom,
            statut=Reservation.Status.DEVIS_ACCEPTE,
            payment_type=Reservation.PaymentType.MOBILE_MONEY,
            client_user=self.cli,
            assigned_provider=self.prov1,
            prestataire_user=self.p1_u,
            montant=Decimal("5000"),
            montant_verse=Decimal("1500"),
            montant_restant=Decimal("3500"),
            acompte_valide=True,
            solde_valide=False,
        )
        dev = Devis.objects.create(
            reference="DEV-25",
            reservation=res,
            prestataire=self.prov1,
            commission_rate=18,
            sous_total=Decimal("5000"),
            total_ttc=Decimal("5000"),
            statut=Devis.Statut.ACCEPTE,
        )
        LigneDevis.objects.create(
            devis=dev,
            description="Remplacement robinet",
            quantite=1,
            prix_unitaire=Decimal("5000"),
        )
        pay = Payment.objects.create(
            reference="ACOMPTE-RES-FAC-25",
            reservation=res,
            client="yvannn",
            prestataire=self.prov1.nom,
            montant=Decimal("1500"),
            commission=Decimal("0"),
            etat=Payment.State.COMPLETE,
            type_paiement="WAVE",
        )
        inv = InvoiceService.get_invoice_data(pay, is_client_view=True)
        self.assertIsNotNone(inv)
        self.assertEqual(inv.sous_total_ttc, 5000.0)
        self.assertEqual(inv.total_paid, 1500.0)
        self.assertEqual(inv.reste_a_payer, 3500.0)
        self.assertFalse(inv.is_fully_paid)
        self.assertEqual(inv.status_label, "ACOMPTE REGLE")
        self.assertNotIn("November", inv.date_emission)

        pdf_bytes = InvoiceService.generate_pdf(pay, is_client_view=True)
        self.assertIsNotNone(pdf_bytes)
        self.assertTrue(pdf_bytes.startswith(b"%PDF-"))

    @override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
    def test_reset_password_email_uses_reset_template_15_min(self):
        mail.outbox.clear()
        with patch("threading.Thread") as mock_thread:
            # Execute synchronement ce que la thread executerait
            def run_sync(target=None, daemon=True):
                target()
                return type("DummyT", (), {"start": lambda self: None})()

            mock_thread.side_effect = run_sync
            _send_reset_email("client@babifix.ci", "654321")

        self.assertEqual(len(mail.outbox), 1)
        sent = mail.outbox[0]
        html_alt = next((c for c, m in sent.alternatives if m == "text/html"), "")
        self.assertIn("Reinitialisation de mot de passe", html_alt)
        self.assertIn("15 minutes", html_alt)
        self.assertNotIn("finaliser votre inscription", html_alt)
        self.assertIn("654321", sent.body)

    # 5. Geolocalisation regionale CI ----------------------------------------
    def test_regional_provider_retained_beyond_50km_and_location_ping_preserves_city(self):
        u_bk, tok_bk = _mk_user("prov_bouake", "prestataire", "bk@babifix.ci")
        r_reg = self._post(
            "/api/prestataire/register",
            tok_bk,
            {
                "nom": "Electricien Bouake",
                "specialite": "Electricite",
                "service_city": "Bouaké",
                "service_address_label": "Air France, Bouaké",
                "service_latitude": 7.6900,
                "service_longitude": -5.0300,
            },
        )
        self.assertIn(r_reg.status_code, (200, 201), r_reg.content)
        prov_bk = Provider.objects.get(user=u_bk)
        prov_bk.statut = Provider.Status.VALID
        prov_bk.save(update_fields=["statut"])
        self.assertAlmostEqual(prov_bk.latitude, 7.6900, places=3)
        self.assertEqual(prov_bk.ville, "Bouaké")

        # Recherche client depuis Korhogo (~204 km de Bouake) sans radius fixe -> rayon adaptatif depasse 50 km
        r_search = self._get(
            "/api/client/prestataires?lat=9.458&lon=-5.629&page_size=50",
            self.cli_tok,
        )
        self.assertEqual(r_search.status_code, 200)
        data_search = r_search.json()
        names = [it["nom"] for it in data_search["items"]]
        self.assertIn("Electricien Bouake", names)
        self.assertGreater(data_search.get("radius_used", 0), 50)

        # Filtre explicite par ville fonctionne meme depuis Abidjan
        r_ville = self._get(
            "/api/client/prestataires?ville=Bouaké&page_size=50",
            self.cli_tok,
        )
        self.assertEqual(r_ville.status_code, 200)
        self.assertIn("Electricien Bouake", [it["nom"] for it in r_ville.json()["items"]])

        # Un ping GPS silencieux ne doit pas ecraser "Bouaké" par "Abidjan"
        r_loc = self._post(
            "/api/prestataire/location/update",
            tok_bk,
            {"latitude": 7.691, "longitude": -5.031, "ville": "Abidjan", "explicit_city": False},
        )
        self.assertEqual(r_loc.status_code, 200)
        prov_bk.refresh_from_db()
        self.assertEqual(prov_bk.ville, "Bouaké")
