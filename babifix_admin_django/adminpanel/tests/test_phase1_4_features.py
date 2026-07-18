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

        # 3) Le client paie la caution (transport) → 100 % presta, + frais fixe
        #    de mise en relation payé EN PLUS (revenu BABIFIX).
        r = self._post(
            f"/api/client/reservations/{res.reference}/pay-caution",
            self.cli_tok, {"mobile_money_operator": "ORANGE_MONEY"},
        )
        self.assertEqual(r.status_code, 200, r.content)
        res.refresh_from_db()
        self.assertTrue(res.caution_payee)
        self.assertEqual(res.statut, "DEVIS_EN_COURS")
        pay = Payment.objects.get(reference__startswith=f"CAUTION-{res.reference}")
        self.assertEqual(pay.commission, Decimal("0"))  # transport 100 % presta
        # Frais fixe (500 par défaut) facturé en plus + comptabilisé côté BABIFIX.
        self.assertEqual(r.json().get("frais_mise_en_relation"), "500")
        self.assertEqual(r.json().get("total"), "5500")  # 5000 + 500
        self.assertTrue(
            PlatformRevenue.objects.filter(reference=res.reference).exists()
        )

        # 4) Après paiement : adresse exacte révélée au presta
        items = self._get("/api/prestataire/requests", self.presta_tok).json()["items"]
        it = next(i for i in items if i["reference"] == "RES-CAU")
        self.assertFalse(it["address_is_approximate"])
        self.assertIn("Jardins", it["address_street"])
        self.assertTrue(it["caution_payee"])

        # 5) Le presta déclare la visite effectuée → le TRANSPORT (5000) lui est
        #    crédité INTÉGRALEMENT sur son solde (100 % presta, payé par mobile).
        self.prov.refresh_from_db()
        solde_avant = self.prov.solde_fcfa or Decimal("0")
        r = self._post(
            f"/api/prestataire/requests/{res.reference}/visite-done", self.presta_tok
        )
        self.assertEqual(r.status_code, 200, r.content)
        res.refresh_from_db()
        self.assertTrue(res.visite_effectuee)
        self.assertEqual(r.json().get("caution_versee_presta"), 5000.0)
        self.prov.refresh_from_db()
        self.assertEqual(
            (self.prov.solde_fcfa or Decimal("0")) - solde_avant, Decimal("5000")
        )
        # Idempotent : un 2e appel ne recrédite pas.
        self._post(
            f"/api/prestataire/requests/{res.reference}/visite-done", self.presta_tok
        )
        self.prov.refresh_from_db()
        self.assertEqual(
            (self.prov.solde_fcfa or Decimal("0")) - solde_avant, Decimal("5000")
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

    def test_frais_mise_en_relation_configurable(self):
        # Phase 5 : plus de % sur la caution (transport 100 % presta). BABIFIX
        # facture un FRAIS FIXE configurable, payé EN PLUS par le client.
        cfg = PlatformConfig.get_solo()
        cfg.frais_mise_en_relation_fcfa = 800
        cfg.save()

        res = self._make_reservation(ref="RES-CFG")
        # Caution plafonnée à 5 000 FCFA (règle métier).
        self._post(
            f"/api/prestataire/requests/{res.reference}/request-visit",
            self.presta_tok, {"caution_montant": 5000},
        )
        r = self._post(
            f"/api/client/reservations/{res.reference}/pay-caution",
            self.cli_tok, {"mobile_money_operator": "WAVE"},
        )
        pay = Payment.objects.get(reference__startswith=f"CAUTION-{res.reference}")
        self.assertEqual(pay.commission, Decimal("0"))  # transport 100 % presta
        self.assertEqual(r.json().get("frais_mise_en_relation"), "800")
        self.assertEqual(r.json().get("total"), "5800")  # 5000 + 800
        # Le frais est comptabilisé comme revenu plateforme.
        rev = PlatformRevenue.objects.filter(reference=res.reference).first()
        self.assertIsNotNone(rev)
        self.assertEqual(rev.amount_fcfa, Decimal("800"))

    def test_radar_visite_suspecte_flag_et_malus(self):
        """Radar : caution payée + visite faite + AUCUN devis → flag + malus presta."""
        from django.utils import timezone as _tz
        from adminpanel.services.reliability_service import ReliabilityService

        res = self._make_reservation(ref="RES-RADAR", statut="DEVIS_EN_COURS")
        res.caution_payee = True
        res.caution_montant = Decimal("5000")
        res.visite_effectuee = True
        res.visite_effectuee_at = _tz.now()
        res.save()

        self.prov.refresh_from_db()
        score_avant = int(self.prov.fiabilite_score or 100)

        self.assertTrue(ReliabilityService.flag_visite_suspecte_if_leak(res))
        res.refresh_from_db()
        self.assertTrue(res.visite_suspecte)
        self.assertTrue(res.visite_suspecte_motif)
        self.prov.refresh_from_db()
        self.assertEqual(int(self.prov.fiabilite_score), max(0, score_avant - 10))

        # Idempotent : 2e appel ne reflague pas, ne repénalise pas.
        self.assertFalse(ReliabilityService.flag_visite_suspecte_if_leak(res))
        self.prov.refresh_from_db()
        self.assertEqual(int(self.prov.fiabilite_score), max(0, score_avant - 10))

    def test_radar_ignore_sans_caution(self):
        """Pas de caution payée → pas de flag radar (aucune fuite possible)."""
        from django.utils import timezone as _tz
        from adminpanel.services.reliability_service import ReliabilityService

        res = self._make_reservation(ref="RES-NORADAR", statut="DEVIS_EN_COURS")
        res.visite_effectuee = True
        res.visite_effectuee_at = _tz.now()
        res.save()
        self.assertFalse(ReliabilityService.flag_visite_suspecte_if_leak(res))
        res.refresh_from_db()
        self.assertFalse(res.visite_suspecte)

    def test_auto_suspension_apres_visites_suspectes(self):
        """3 visites suspectes → suspension automatique (login bloqué + demandes)."""
        from django.utils import timezone as _tz
        from adminpanel.services.reliability_service import ReliabilityService

        cfg = PlatformConfig.get_solo()
        cfg.auto_suspension_actif = True
        cfg.suspension_visites_suspectes = 3
        cfg.suspension_score_seuil = 20
        cfg.save()

        for i in range(3):
            res = self._make_reservation(ref=f"RES-SUSP-{i}", statut="DEVIS_EN_COURS")
            res.caution_payee = True
            res.caution_montant = Decimal("5000")
            res.visite_effectuee = True
            res.visite_effectuee_at = _tz.now()
            res.save()
            ReliabilityService.flag_visite_suspecte_if_leak(res)

        self.prov.refresh_from_db()
        self.assertEqual(self.prov.statut, Provider.Status.SUSPENDED)
        # Connexion bloquée : user.is_active passe à False.
        self.presta.refresh_from_db()
        self.assertFalse(self.presta.is_active)
        # L'endpoint demandes renvoie « suspended » et aucune demande.
        r = self._get("/api/prestataire/requests", self.presta_tok)
        if r.status_code == 200:
            self.assertTrue(r.json().get("suspended"))
            self.assertEqual(r.json().get("items"), [])

    def test_fidelite_remise_appliquee_babifix_absorbe(self):
        """Crédit fidélité → remise sur ce que paie le client ; presta net INCHANGÉ,
        BABIFIX absorbe."""
        from adminpanel.services.escrow_service import EscrowService

        prof = UserProfile.objects.get(user=self.cli)
        prof.fidelite_credit_fcfa = Decimal("2000")
        prof.save()

        res = self._make_reservation(ref="RES-FID")
        res.payment_type = "MOBILE_MONEY"
        res.save(update_fields=["payment_type"])

        # Devis 50 000 (commission 18 % = 9 000 ; net presta 41 000).
        r = self._post(
            f"/api/prestataire/requests/{res.reference}/devis", self.presta_tok,
            {"diagnostic": "Job", "lignes": [
                {"type_ligne": "MAIN_OEUVRE", "description": "X", "quantite": 1,
                 "prix_unitaire": 50000}]},
        )
        self.assertEqual(r.status_code, 200, r.content)
        r = self._post(
            f"/api/client/reservations/{res.reference}/devis/accept", self.cli_tok
        )
        self.assertEqual(r.status_code, 200, r.content)

        res.refresh_from_db()
        # Remise = min(crédit 2000, commission 9000) = 2000, crédit consommé.
        self.assertEqual(res.remise_fidelite, Decimal("2000"))
        prof.refresh_from_db()
        self.assertEqual(prof.fidelite_credit_fcfa, Decimal("0"))

        # Le client paie total − remise ; le net presta reste sur le devis complet.
        q = EscrowService.quote(res)
        self.assertEqual(q.amount_due, Decimal("14400"))  # 30 % de (50000 − 2000)
        self.assertEqual(q.net_prestataire, Decimal("41000"))  # inchangé (50000 − 9000)

    def test_escrow_quote_reconcilie_avec_caution_deja_payee(self):
        """Non-régression EXACTE du bug signalé : devis 5000, caution/transport
        3000 déjà réglée par mobile. L'écran de PAIEMENT doit refléter le RESTE
        (2000), pas redemander une commission sur les 5000 F complets comme si
        rien n'avait encore été payé.
        """
        from adminpanel.services.escrow_service import EscrowService

        # Statut réel après paiement de la caution (voir api_client_pay_caution) :
        # DEVIS_EN_COURS, pas VISITE_DIAGNOSTIC.
        res = self._make_reservation(ref="RES-CAUT-PAY", statut="DEVIS_EN_COURS")
        res.payment_type = "ESPECES"
        res.caution_montant = Decimal("3000")
        res.caution_payee = True
        res.visite_effectuee = True
        res.save()

        r = self._post(
            f"/api/prestataire/requests/{res.reference}/devis", self.presta_tok,
            {"diagnostic": "Fuite", "lignes": [
                {"type_ligne": "MAIN_OEUVRE", "description": "Réparation",
                 "quantite": 1, "prix_unitaire": 5000}]},
        )
        self.assertEqual(r.status_code, 200, r.content)
        r = self._post(
            f"/api/client/reservations/{res.reference}/devis/accept", self.cli_tok
        )
        self.assertEqual(r.status_code, 200, r.content)

        res.refresh_from_db()
        self.assertTrue(res.caution_deduite)
        self.assertEqual(res.montant, Decimal("2000"))  # 5000 - 3000, déjà correct

        # AVANT LE CORRECTIF : le quote lisait devis.commission_montant (900,
        # 18% de 5000 COMPLETS) et redemandait 4100 en cash, ignorant la
        # caution déjà versée. Attendu maintenant : commission sur le RESTE
        # (2000), donc 360 — porté à 500 par le garde-fou minimum GeniusPay
        # (préexistant, sans rapport avec ce correctif), d'où un surplus de
        # 140 F reversé au presta à la confirmation.
        q = EscrowService.quote(res)
        self.assertEqual(q.commission_montant, Decimal("360"))
        self.assertEqual(q.net_prestataire, Decimal("1640"))  # 2000 - 360
        self.assertEqual(q.amount_due, Decimal("500"))  # 360 -> mini 500 F
        self.assertEqual(q.cash_minimum_surplus, Decimal("140"))  # 500 - 360
        self.assertEqual(q.cash_remainder, Decimal("1500"))  # 1640 - 140

    def test_escrow_quote_reconcilie_avec_caution_deja_payee_mobile_money(self):
        """Même bug, même scénario (devis 5000, caution 3000 déjà payée), mais en
        MOBILE_MONEY plutôt qu'en cash — pour vérifier que le correctif ne
        dépend pas du type de paiement choisi par le client."""
        from adminpanel.services.escrow_service import EscrowService

        res = self._make_reservation(ref="RES-CAUT-PAY-MM", statut="DEVIS_EN_COURS")
        res.payment_type = "MOBILE_MONEY"
        res.caution_montant = Decimal("3000")
        res.caution_payee = True
        res.visite_effectuee = True
        res.save()

        r = self._post(
            f"/api/prestataire/requests/{res.reference}/devis", self.presta_tok,
            {"diagnostic": "Fuite", "lignes": [
                {"type_ligne": "MAIN_OEUVRE", "description": "Réparation",
                 "quantite": 1, "prix_unitaire": 5000}]},
        )
        self.assertEqual(r.status_code, 200, r.content)
        r = self._post(
            f"/api/client/reservations/{res.reference}/devis/accept", self.cli_tok
        )
        self.assertEqual(r.status_code, 200, r.content)

        res.refresh_from_db()
        self.assertTrue(res.caution_deduite)
        self.assertEqual(res.montant, Decimal("2000"))  # 5000 - 3000

        # Acompte 30 % du RESTE réellement dû (2000), pas des 5000 F complets :
        # 30 % de 2000 = 600 (au-dessus du minimum GeniusPay, pas de garde-fou).
        q = EscrowService.quote(res)
        self.assertEqual(q.strategy, "MOBILE_DEPOSIT")
        self.assertEqual(q.commission_montant, Decimal("360"))  # 18 % de 2000
        self.assertEqual(q.net_prestataire, Decimal("1640"))  # 2000 - 360
        self.assertEqual(q.amount_due, Decimal("600"))  # 30 % de 2000

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
