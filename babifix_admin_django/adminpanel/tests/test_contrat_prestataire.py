"""Contrat prestataire — le contrat doit dire la VÉRITÉ et couvrir ce qu'on applique.

Deux exigences non négociables vérifiées ici :

1. Le taux de commission affiché doit être EXACTEMENT celui réellement prélevé.
   (Avant : le contrat le recalculait depuis une autre source, sans la remise
   dégressive par volume → il pouvait afficher un taux différent du facturé.)

2. Toute règle appliquée par le code doit figurer dans le contrat, et un
   changement matériel doit forcer une NOUVELLE signature. On ne suspend pas un
   compte sur une clause que la personne n'a jamais signée.
"""
import json
from decimal import Decimal

from django.contrib.auth.models import User
from django.test import Client as DjangoClient, TestCase
from django.utils import timezone

from adminpanel.auth import create_token
from adminpanel.models import Category, Provider, UserProfile
from adminpanel.views_extra import CONTRAT_VERSION


class ContratPrestataireTest(TestCase):
    def setUp(self):
        self.http = DjangoClient()
        self.cat = Category.objects.create(nom="Plomberie", icone_slug="plomberie")
        self.presta = User.objects.create_user("presta_ct", password="Pwd12345!")
        UserProfile.objects.create(user=self.presta, role="prestataire", active=True)
        self.prov = Provider.objects.create(
            user=self.presta, nom="Plombier Contrat", specialite="Plomberie",
            ville="Abidjan", category=self.cat, statut=Provider.Status.VALID,
        )
        self.tok = create_token(self.presta.id, "prestataire")

    def _get_contrat(self):
        r = self.http.get(
            "/api/prestataire/contrat/", HTTP_AUTHORIZATION=f"Bearer {self.tok}"
        )
        self.assertEqual(r.status_code, 200, r.content)
        return r.json()

    # ── 1. Le contrat ne doit pas mentir sur le prix ───────────────────────
    def test_commission_affichee_est_celle_reellement_prelevee(self):
        from adminpanel.services.wallet_service import _get_effective_commission_rate

        d = self._get_contrat()
        reel = int(
            (Decimal(str(_get_effective_commission_rate(self.prov))) * 100).quantize(
                Decimal("1")
            )
        )
        self.assertEqual(d["commission_rate"], reel)

    # ── 2. Le contrat doit couvrir ce que le code applique ─────────────────
    def test_contrat_couvre_les_regles_appliquees_par_le_code(self):
        d = self._get_contrat()
        titres = " ".join(c["titre"] for c in d["clauses"]).lower()
        for attendu in (
            "transport",            # visite de diagnostic
            "séquestre",            # escrow
            "contourner",           # anti-désintermédiation
            "fiabilité",            # score
            "suspension automatique",
            "abonnement",
            "fidélité",
        ):
            self.assertIn(attendu, titres, f"Clause manquante : {attendu}")

    def test_clause_suspension_annonce_les_seuils_reels(self):
        # Les seuils du contrat viennent de PlatformConfig : ils ne peuvent pas
        # diverger du code qui suspend réellement.
        from adminpanel.models import PlatformConfig

        cfg = PlatformConfig.get_solo()
        cfg.suspension_score_seuil = 25
        cfg.suspension_visites_suspectes = 4
        cfg.save()

        d = self._get_contrat()
        clause = next(
            c for c in d["clauses"] if "suspension automatique" in c["titre"].lower()
        )
        self.assertIn("25", clause["contenu"])
        self.assertIn("4", clause["contenu"])

    def test_clause_transport_dit_100_pourcent_presta(self):
        d = self._get_contrat()
        clause = next(c for c in d["clauses"] if "transport" in c["titre"].lower())
        self.assertIn("100%", clause["contenu"])
        self.assertIn("5 000", clause["contenu"])

    # ── 3. Un changement de version force une nouvelle signature ───────────
    def test_non_signe_au_depart(self):
        d = self._get_contrat()
        self.assertFalse(d["contrat_signe"])
        self.assertEqual(d["contrat_version"], CONTRAT_VERSION)

    def test_signature_enregistre_la_version_du_serveur(self):
        # Même si le client envoie une autre version, le serveur impose la sienne
        # (sinon une app modifiée « signerait » une version obsolète).
        r = self.http.post(
            "/api/prestataire/contrat/sign/",
            data=json.dumps({"version": "0.1"}),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {self.tok}",
        )
        self.assertEqual(r.status_code, 200, r.content)
        self.assertEqual(r.json()["contrat_version"], CONTRAT_VERSION)

        self.prov.refresh_from_db()
        self.assertEqual(self.prov.contrat_version, CONTRAT_VERSION)
        self.assertTrue(self._get_contrat()["contrat_signe"])

    def test_ancienne_version_signee_exige_une_resignature(self):
        # Prestataire ayant signé l'ancien contrat (sans la suspension auto).
        self.prov.contrat_accepte_at = timezone.now()
        self.prov.contrat_version = "1.0"
        self.prov.save(update_fields=["contrat_accepte_at", "contrat_version"])

        d = self._get_contrat()
        self.assertFalse(d["contrat_signe"])
        self.assertTrue(d["resignature_requise"])

        # L'app le voit aussi via /me → elle re-route vers le contrat.
        r = self.http.get(
            "/api/prestataire/me", HTTP_AUTHORIZATION=f"Bearer {self.tok}"
        )
        self.assertEqual(r.status_code, 200, r.content)
        self.assertFalse(r.json()["provider"]["contrat_signe"])
