"""Tests d'intégration bout-en-bout des nouvelles fonctionnalités (Phases 1–4).

Couvre : template d'exigences par catégorie, visite de diagnostic + caution
(déblocage adresse, commission configurable, déduction, no-show), devis en 2
temps (estimation non payable), et score de fiabilité.

Run : python manage.py test adminpanel.tests.test_phase1_4_features
"""
import json
from decimal import Decimal

from django.test import TestCase, Client as DjangoClient
from django.contrib.auth.models import User

from adminpanel.auth import create_token
from adminpanel.models import (
    Category, Provider, Reservation, UserProfile, Payment,
    PlatformRevenue, PlatformConfig, Devis,
)


def _client_user(username="cli", email="cli@babifix.ci"):
    u = User.objects.create_user(username=username, password="Pwd12345!", email=email)
    UserProfile.objects.create(user=u, role="client", active=True)
    return u, create_token(u.id, "client")


def _presta_user(username="prov", email="prov@babifix.ci"):
    u = User.objects.create_user(username=username, password="Pwd12345!", email=email)
    UserProfile.objects.create(user=u, role="prestataire", active=True)
    return u, create_token(u.id, "prestataire")


TEMPLATE = [
    {"key": "surface_m2", "label": "Surface", "type": "number", "unit": "m²", "required": True},
    {"key": "type_peinture", "label": "Type", "type": "select", "choices": ["Mate", "Satinée"]},
]


class Phase14FeaturesTest(TestCase):
    def setUp(self):
        self.http = DjangoClient()
        self.cat = Category.objects.create(
            nom="Peinture & Ravalement", icone_slug="pinceau",
            profil_devis="SURFACE", template_exigences=TEMPLATE,
        )
        self.cli, self.cli_tok = _client_user()
        self.presta, self.presta_tok = _presta_user()
        self.prov = Provider.objects.create(
            user=self.presta, nom="Peintre Test", specialite="Peinture & Ravalement",
            ville="Abidjan", category=self.cat, statut=Provider.Status.VALID,
        )

    # ------------------------------------------------------------------ helpers
    def _post(self, url, token, payload=None):
        return self.http.post(
            url, data=json.dumps(payload or {}), content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {token}",
        )

    def _get(self, url, token):
        return self.http.get(url, HTTP_AUTHORIZATION=f"Bearer {token}")

    def _make_reservation(self, ref="RES-T1", statut="DEMANDE_ENVOYEE", montant=0):
        return Reservation.objects.create(
            reference=ref, client="cli@babifix.ci", prestataire="Peintre Test",
            montant=montant, statut=statut, client_user=self.cli,
            assigned_provider=self.prov, prestataire_user=self.presta,
            address_street="Rue des Jardins 12", address_quartier="Cocody",
            address_ville="Abidjan", address_is_approximate=True,
            latitude=5.35, longitude=-3.99,
        )

    # ------------------------------------------------------------------ tests
    def test_requirements_endpoint_returns_template(self):
        r = self._get(f"/api/providers/{self.prov.id}/requirements/", self.cli_tok)
        self.assertEqual(r.status_code, 200)
        d = r.json()
        self.assertEqual(d["profil_devis"], "SURFACE")
        self.assertEqual(len(d["template_exigences"]), 2)

    def test_full_visite_caution_cycle(self):
        res = self._make_reservation(ref="RES-CAU")

        # 1) Le presta demande une visite avec caution
        r = self._post(
            f"/api/prestataire/requests/{res.reference}/request-visit",
            self.presta_tok, {"caution_montant": 5000, "caution_motif": "métré"},
        )
        self.assertEqual(r.status_code, 200, r.content)
        res.refresh_from_db()
        self.assertEqual(res.statut, "VISITE_DIAGNOSTIC")
        self.assertEqual(res.caution_montant, Decimal("5000"))

        # 2) Avant paiement : adresse encore masquée pour le presta
        items = self._get("/api/prestataire/requests", self.presta_tok).json()["items"]
        it = next(i for i in items if i["reference"] == "RES-CAU")
        self.assertTrue(it["address_is_approximate"])
        self.assertEqual(it["address_street"], "")

        # 3) Le client paie la caution → commission 12 % (défaut config)
        r = self._post(
            f"/api/client/reservations/{res.reference}/pay-caution",
            self.cli_tok, {"mobile_money_operator": "ORANGE_MONEY"},
        )
        self.assertEqual(r.status_code, 200, r.content)
        res.refresh_from_db()
        self.assertTrue(res.caution_payee)
        self.assertEqual(res.statut, "DEVIS_EN_COURS")
        pay = Payment.objects.get(reference__startswith=f"CAUTION-{res.reference}")
        self.assertEqual(pay.commission, Decimal("600"))  # 12 % de 5000
        self.assertTrue(
            PlatformRevenue.objects.filter(reference=res.reference).exists()
        )

        # 4) Après paiement : adresse exacte révélée au presta
        items = self._get("/api/prestataire/requests", self.presta_tok).json()["items"]
        it = next(i for i in items if i["reference"] == "RES-CAU")
        self.assertFalse(it["address_is_approximate"])
        self.assertIn("Jardins", it["address_street"])
        self.assertTrue(it["caution_payee"])

        # 5) Le presta déclare la visite effectuée → sa part de caution
        #    (5000 − 12 % = 4400) est créditée sur son solde (payée par mobile).
        self.prov.refresh_from_db()
        solde_avant = self.prov.solde_fcfa or Decimal("0")
        r = self._post(
            f"/api/prestataire/requests/{res.reference}/visite-done", self.presta_tok
        )
        self.assertEqual(r.status_code, 200, r.content)
        res.refresh_from_db()
        self.assertTrue(res.visite_effectuee)
        self.assertEqual(r.json().get("caution_versee_presta"), 4400.0)
        self.prov.refresh_from_db()
        self.assertEqual(
            (self.prov.solde_fcfa or Decimal("0")) - solde_avant, Decimal("4400")
        )
        # Idempotent : un 2e appel ne recrédite pas.
        self._post(
            f"/api/prestataire/requests/{res.reference}/visite-done", self.presta_tok
        )
        self.prov.refresh_from_db()
        self.assertEqual(
            (self.prov.solde_fcfa or Decimal("0")) - solde_avant, Decimal("4400")
        )

        # 6) Devis ferme puis acceptation → caution déduite du montant
        r = self._post(
            f"/api/prestataire/requests/{res.reference}/devis", self.presta_tok,
            {"diagnostic": "Peinture salon", "lignes": [
                {"type_ligne": "MAIN_OEUVRE", "description": "Peinture", "quantite": 1,
                 "prix_unitaire": 50000},
            ]},
        )
        self.assertEqual(r.status_code, 200, r.content)
        res.refresh_from_db()
        self.assertEqual(res.statut, "DEVIS_ENVOYE")

        r = self._post(
            f"/api/client/reservations/{res.reference}/devis/accept", self.cli_tok
        )
        self.assertEqual(r.status_code, 200, r.content)
        res.refresh_from_db()
        self.assertTrue(res.caution_deduite)
        self.assertEqual(res.montant, Decimal("45000"))  # 50000 - 5000

    def test_estimation_not_payable(self):
        res = self._make_reservation(ref="RES-EST")
        r = self._post(
            f"/api/prestataire/requests/{res.reference}/devis", self.presta_tok,
            {"diagnostic": "Estimation", "est_estimation": True,
             "prix_min": 40000, "prix_max": 60000, "lignes": []},
        )
        self.assertEqual(r.status_code, 200, r.content)
        res.refresh_from_db()
        self.assertEqual(res.statut, "DEVIS_EN_COURS")  # pas payable
        dev = Devis.objects.get(reservation=res)
        self.assertTrue(dev.est_estimation)

        # Le client ne peut PAS accepter une estimation
        r = self._post(
            f"/api/client/reservations/{res.reference}/devis/accept", self.cli_tok
        )
        self.assertEqual(r.status_code, 409)
        self.assertEqual(r.json().get("error"), "estimation_only")

    def test_caution_commission_configurable(self):
        cfg = PlatformConfig.get_solo()
        cfg.caution_commission_pct = 20
        cfg.save()

        res = self._make_reservation(ref="RES-CFG")
        # Caution plafonnée à 5 000 FCFA (règle métier).
        self._post(
            f"/api/prestataire/requests/{res.reference}/request-visit",
            self.presta_tok, {"caution_montant": 5000},
        )
        self._post(
            f"/api/client/reservations/{res.reference}/pay-caution",
            self.cli_tok, {"mobile_money_operator": "WAVE"},
        )
        pay = Payment.objects.get(reference__startswith=f"CAUTION-{res.reference}")
        self.assertEqual(pay.commission, Decimal("1000"))  # 20 % de 5000

    def test_reliability_suspicious_cancellation(self):
        # Cancellation via l'endpoint LIVE (api_client_cancel_reservation).
        res = self._make_reservation(ref="RES-REL", statut="VISITE_DIAGNOSTIC")
        res.caution_payee = True
        res.visite_effectuee = False
        res.save(update_fields=["caution_payee", "visite_effectuee"])

        prof = UserProfile.objects.get(user=self.cli)
        prof.fiabilite_score = 100
        prof.save(update_fields=["fiabilite_score"])

        r = self._post(
            f"/api/client/reservations/{res.reference}/cancel",
            self.cli_tok, {"motif": "je me désiste"},
        )
        self.assertEqual(r.status_code, 200, r.content)

        res.refresh_from_db()
        prof.refresh_from_db()
        self.assertEqual(res.statut, "Annulee")
        self.assertTrue(res.annulation_suspecte)      # flag anti-contournement
        self.assertTrue(res.caution_remboursee)       # caution rendue (pas de visite)
        self.assertEqual(prof.fiabilite_score, 92)    # 100 - 8 (défaut)

    def test_reliability_completion_bonus(self):
        from adminpanel.services.reliability_service import ReliabilityService

        self.prov.fiabilite_score = 90
        self.prov.save(update_fields=["fiabilite_score"])
        res = self._make_reservation(ref="RES-DONE")
        ReliabilityService.on_completion(res)
        self.prov.refresh_from_db()
        self.assertEqual(self.prov.fiabilite_score, 92)  # +2 (défaut)
