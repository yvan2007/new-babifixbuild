"""
Tests unitaires et d'integration pour les algorithmes intelligents BABIFIX :
- Fiabilite reelle (fiabilite_score) et ponderation bayesienne des notes
- Recherche tolerante aux fautes et comprehension des symptomes
- Estimation tarifaire Abidjan, suggestions catalogue et verification de coherence
- Limites d'authentification et confidentialite des donnees admin
"""

import json
from datetime import timedelta

from django.contrib.auth.models import User
from django.test import Client as DjangoClient
from django.test import TestCase
from django.utils import timezone

from adminpanel.auth import create_token
from adminpanel.models import Category, Provider, Reservation, UserProfile
from adminpanel.services.intelligence_service import (
    AdminRiskRadar,
    SmartDevisAdvisor,
    SmartProviderScorer,
)


class SmartProviderScorerTests(TestCase):
    def setUp(self):
        self.cat_plomb = Category.objects.create(nom="Plomberie", icone_slug="goutte")
        self.cat_elec = Category.objects.create(nom="Electricite", icone_slug="eclair")

        self.client_user = User.objects.create_user(username="cli_smart", password="Pwd123!")
        UserProfile.objects.create(user=self.client_user, role="client", active=True)
        self.client_token = create_token(self.client_user.id, "client")

        self.pro_user = User.objects.create_user(username="pro_smart", password="Pwd123!")
        UserProfile.objects.create(user=self.pro_user, role="prestataire", active=True)
        self.pro_token = create_token(self.pro_user.id, "prestataire")

        self.http = DjangoClient()

    def test_fiabilite_score_impacts_elite_ranking(self):
        p_fiable = Provider.objects.create(
            nom="Kouassi Fiable",
            specialite="Plomberie",
            ville="Abidjan - Cocody",
            statut=Provider.Status.VALID,
            disponible=True,
            average_rating=4.7,
            rating_count=15,
            fiabilite_score=100,
            category=self.cat_plomb,
        )
        p_risque = Provider.objects.create(
            nom="Traore Baisse",
            specialite="Plomberie",
            ville="Abidjan - Cocody",
            statut=Provider.Status.VALID,
            disponible=True,
            average_rating=4.7,
            rating_count=15,
            fiabilite_score=40,
            category=self.cat_plomb,
        )
        prof_ok = SmartProviderScorer.compute_profile(p_fiable)
        prof_low = SmartProviderScorer.compute_profile(p_risque)
        self.assertGreater(prof_ok["elite_score"], prof_low["elite_score"])
        self.assertEqual(prof_ok["fiabilite_score"], 100)
        self.assertEqual(prof_low["fiabilite_score"], 40)

    def test_bayesian_rating_beats_single_perfect_review(self):
        p_veteran = Provider.objects.create(
            nom="Yao Veteran",
            specialite="Electricite",
            ville="Abidjan - Marcory",
            statut=Provider.Status.VALID,
            disponible=True,
            average_rating=4.8,
            rating_count=40,
            fiabilite_score=96,
            category=self.cat_elec,
        )
        p_newbie = Provider.objects.create(
            nom="Konan Nouveau",
            specialite="Electricite",
            ville="Abidjan - Marcory",
            statut=Provider.Status.VALID,
            disponible=True,
            average_rating=5.0,
            rating_count=1,
            fiabilite_score=96,
            category=self.cat_elec,
        )
        s_vet = SmartProviderScorer.compute_profile(p_veteran)
        s_new = SmartProviderScorer.compute_profile(p_newbie)
        self.assertGreater(s_vet["bayesian_rating"], s_new["bayesian_rating"])
        self.assertGreater(s_vet["elite_score"], s_new["elite_score"])

    def test_typo_and_symptom_search_on_public_and_client_endpoints(self):
        Provider.objects.create(
            nom="Bamba Tuyau",
            specialite="Plomberie",
            ville="Abidjan - Yopougon",
            statut=Provider.Status.VALID,
            disponible=True,
            average_rating=4.6,
            rating_count=12,
            category=self.cat_plomb,
        )
        Provider.objects.create(
            nom="Fofana Courant",
            specialite="Electricite",
            ville="Abidjan - Yopougon",
            statut=Provider.Status.VALID,
            disponible=True,
            average_rating=4.6,
            rating_count=12,
            category=self.cat_elec,
        )

        # Recherche symptome : "fuite sous evier" doit cibler la plomberie
        resp_pub = self.http.get("/api/public/providers/?q=fuite+sous+evier")
        self.assertEqual(resp_pub.status_code, 200)
        pub_names = [x["nom"] for x in resp_pub.json()["providers"]]
        self.assertIn("Bamba Tuyau", pub_names)

        # Recherche avec faute : "plonbier" sur endpoint client authentifie
        resp_cli = self.http.get(
            "/api/client/prestataires?q=plonbier",
            HTTP_AUTHORIZATION=f"Bearer {self.client_token}",
        )
        self.assertEqual(resp_cli.status_code, 200)
        items = resp_cli.json()["items"]
        self.assertTrue(any(it["nom"] == "Bamba Tuyau" for it in items))
        # Verifie la presence d'une explication client et l'absence de fuite admin
        self.assertIn("trust_reasons", items[0])
        self.assertNotIn("alerts", resp_cli.json())

    def test_smart_price_estimator_and_devis_coherence_endpoints(self):
        Provider.objects.create(
            user=self.pro_user,
            nom="Gbagbo Climatisation",
            specialite="Climatisation",
            ville="Abidjan - Cocody",
            statut=Provider.Status.VALID,
            disponible=True,
            plafond_intervention_fcfa=100000,
        )

        # Endpoint client requiert authentification
        anon = self.http.get("/api/client/smart/price-estimate/?description=clim+ne+refroidit+plus")
        self.assertIn(anon.status_code, (401, 403))

        ok_cli = self.http.get(
            "/api/client/smart/price-estimate/?description=clim+ne+refroidit+plus",
            HTTP_AUTHORIZATION=f"Bearer {self.client_token}",
        )
        self.assertEqual(ok_cli.status_code, 200)
        est = ok_cli.json()["estimate"]
        self.assertEqual(est["slug"], "climatisation")
        self.assertGreaterEqual(est["max_fcfa"], est["min_fcfa"])
        self.assertGreater(len(est["suggested_items"]), 0)

        # Endpoint pro refuse un client normal
        wrong_role = self.http.get(
            "/api/prestataire/smart/devis-assist/",
            HTTP_AUTHORIZATION=f"Bearer {self.client_token}",
        )
        self.assertIn(wrong_role.status_code, (401, 403))

        # Endpoint pro signale un depassement de plafond de facon informative
        check_pro = self.http.post(
            "/api/prestataire/smart/devis-assist/",
            data=json.dumps({"description": "remplacement split", "total_ttc": 180000}),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {self.pro_token}",
        )
        self.assertEqual(check_pro.status_code, 200)
        payload = check_pro.json()
        self.assertTrue(payload["is_anomaly"])
        self.assertEqual(payload["severity"], "warning")

    def test_admin_risk_radar_detects_stale_request_and_low_reliability(self):
        Provider.objects.create(
            nom="Artisan Fragile",
            specialite="Plomberie",
            ville="Abidjan",
            statut=Provider.Status.VALID,
            is_deleted=False,
            fiabilite_score=55,
        )
        Reservation.objects.create(
            reference="RES-STALE-TEST",
            title="Fuite urgente",
            client="cli_smart",
            prestataire="Artisan Fragile",
            montant=15000,
            statut=Reservation.Status.DEMANDE_ENVOYEE,
            created_at=timezone.now() - timedelta(hours=5),
        )
        radar = AdminRiskRadar.build_summary()
        codes = {a["code"] for a in radar["alerts"]}
        self.assertIn("stale_requests", codes)
        self.assertIn("low_reliability_providers", codes)
        self.assertLess(radar["health_score"], 100)
