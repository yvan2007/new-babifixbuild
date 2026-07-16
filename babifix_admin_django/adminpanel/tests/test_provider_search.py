"""Recherche de prestataires — non-régression UnboundLocalError sur `Q`.

Les deux endpoints de recherche utilisaient `Q(...)` pour le filtre texte, puis
réimportaient `Q` plus bas DANS la même fonction. Python en déduisait que `Q`
était une variable locale → `UnboundLocalError` dès qu'un `q=` était fourni,
donc une 500 sur la recherche publique ET la recherche client.
"""
from django.contrib.auth.models import User
from django.test import Client as DjangoClient, TestCase

from adminpanel.auth import create_token
from adminpanel.models import Category, Provider, UserProfile


class ProviderSearchTest(TestCase):
    def setUp(self):
        self.http = DjangoClient()
        self.cat = Category.objects.create(nom="Plomberie", icone_slug="tuyau")
        presta = User.objects.create_user("presta_search", password="Pwd12345!")
        UserProfile.objects.create(user=presta, role="prestataire", active=True)
        Provider.objects.create(
            user=presta, nom="Plombier Cocody", specialite="Plomberie",
            ville="Abidjan", category=self.cat, statut=Provider.Status.VALID,
            latitude=5.35, longitude=-3.99,
        )
        cli = User.objects.create_user("cli_search", password="Pwd12345!")
        UserProfile.objects.create(user=cli, role="client", active=True)
        self.cli_tok = create_token(cli.id, "client")

    # ── Catalogue public ───────────────────────────────────────────────────
    def test_public_providers_avec_recherche_texte(self):
        r = self.http.get("/api/public/providers/?q=Plombier")
        self.assertEqual(r.status_code, 200)

    def test_public_providers_recherche_texte_et_geo(self):
        # Le cas qui déclenchait le bug : filtre texte PUIS bloc géo (qui
        # contenait l'import local de Q).
        r = self.http.get("/api/public/providers/?q=Plombier&lat=5.35&lon=-3.99")
        self.assertEqual(r.status_code, 200)

    # ── Recherche côté client ──────────────────────────────────────────────
    def test_client_prestataires_avec_recherche_texte(self):
        r = self.http.get(
            "/api/client/prestataires?q=Plombier",
            HTTP_AUTHORIZATION=f"Bearer {self.cli_tok}",
        )
        self.assertEqual(r.status_code, 200)

    def test_client_prestataires_recherche_texte_et_geo(self):
        r = self.http.get(
            "/api/client/prestataires?q=Plombier&lat=5.35&lon=-3.99&radius_km=auto",
            HTTP_AUTHORIZATION=f"Bearer {self.cli_tok}",
        )
        self.assertEqual(r.status_code, 200)
