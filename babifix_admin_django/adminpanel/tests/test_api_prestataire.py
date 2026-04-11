"""
Tests d'intégration — Workflow Prestataire BABIFIX
Cible : inscription → validation admin → disponibilité → gains → profil
Run : python manage.py test adminpanel.tests.test_api_prestataire
"""
import json

from django.test import TestCase, Client as DjangoClient
from django.contrib.auth.models import User

from adminpanel.auth import create_token
from adminpanel.models import AdminAuditLog, Category, Provider, Reservation, UserProfile


def _make_prestataire_user(username='prest', password='Pwd12345!'):
    """Crée un User + UserProfile prestataire + token."""
    user = User.objects.create_user(username=username, password=password)
    UserProfile.objects.create(user=user, role='prestataire', active=True)
    token = create_token(user.id, 'prestataire')
    return user, token


def _make_admin_user(username='admin_op', password='Admin1!'):
    user = User.objects.create_user(username=username, password=password, is_staff=True)
    UserProfile.objects.create(user=user, role='admin', active=True)
    token = create_token(user.id, 'admin')
    return user, token


class ProviderRegistrationTest(TestCase):
    """Tests de POST /api/prestataire/register."""

    def setUp(self):
        self.http = DjangoClient()
        self.category = Category.objects.create(nom='Plomberie', icone_slug='plumber')
        self.user, self.token = _make_prestataire_user()

    def _post_register(self, payload, token=None):
        headers = {}
        if token:
            headers['HTTP_AUTHORIZATION'] = f'Bearer {token}'
        return self.http.post(
            '/api/prestataire/register',
            data=json.dumps(payload),
            content_type='application/json',
            **headers,
        )

    def test_register_creates_provider_pending(self):
        resp = self._post_register({
            'nom': 'Koffi Yao',
            'specialite': 'Plomberie',
            'ville': 'Abidjan',
            'cni_url': 'https://babifix.ci/media/cni/koffi.jpg',
        }, token=self.token)
        self.assertIn(resp.status_code, [200, 201])
        self.assertTrue(Provider.objects.filter(nom='Koffi Yao').exists())
        prov = Provider.objects.get(nom='Koffi Yao')
        self.assertEqual(prov.statut, Provider.Status.PENDING)
        self.assertFalse(prov.is_approved)

    def test_register_links_to_user(self):
        self._post_register({
            'nom': 'Linked Provider',
            'specialite': 'Ménage',
            'ville': 'Bouaké',
        }, token=self.token)
        prov = Provider.objects.filter(user=self.user).first()
        self.assertIsNotNone(prov)

    def test_register_without_token_still_creates_orphan_provider(self):
        """Sans token : provider orphelin (pas de user lié) — cas nominal documenté."""
        resp = self._post_register({
            'nom': 'Orphan Provider',
            'specialite': 'Jardinage',
            'ville': 'San-Pédro',
        })
        self.assertIn(resp.status_code, [200, 201])

    def test_register_missing_nom_returns_error(self):
        resp = self._post_register({'specialite': 'Électricité', 'ville': 'Abidjan'})
        self.assertNotIn(resp.status_code, [200, 201])

    def test_register_idempotent_for_same_user(self):
        """Deuxième appel avec le même user met à jour le dossier existant."""
        self._post_register({'nom': 'First', 'specialite': 'A', 'ville': 'B'}, token=self.token)
        resp = self._post_register({'nom': 'Updated', 'specialite': 'A', 'ville': 'B'}, token=self.token)
        self.assertIn(resp.status_code, [200, 201])
        # Un seul provider par user
        count = Provider.objects.filter(user=self.user).count()
        self.assertEqual(count, 1)


class ProviderValidationWorkflowTest(TestCase):
    """Tests du workflow de validation admin (pending→valid/refused)."""

    def setUp(self):
        self.http = DjangoClient()
        self.prest_user, self.prest_token = _make_prestataire_user('prest_wf')
        self.admin_user, self.admin_token = _make_admin_user()
        self.provider = Provider.objects.create(
            user=self.prest_user,
            nom='Workflow Test',
            specialite='Électricité',
            ville='Abidjan',
            statut=Provider.Status.PENDING,
        )

    def test_admin_can_accept_provider(self):
        resp = self.http.post(
            '/api/admin/prestataires/bulk-action/',
            data=json.dumps({
                'ids': [self.provider.id],
                'action': 'accept',
            }),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.admin_token}',
        )
        self.assertIn(resp.status_code, [200, 201])
        self.provider.refresh_from_db()
        self.assertEqual(self.provider.statut, Provider.Status.VALID)
        self.assertTrue(self.provider.is_approved)

    def test_admin_can_refuse_provider_with_motif(self):
        resp = self.http.post(
            '/api/admin/prestataires/bulk-action/',
            data=json.dumps({
                'ids': [self.provider.id],
                'action': 'refuse',
                'motif': 'CNI illisible',
            }),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.admin_token}',
        )
        self.assertIn(resp.status_code, [200, 201])
        self.provider.refresh_from_db()
        self.assertEqual(self.provider.statut, Provider.Status.REFUSED)
        self.assertFalse(self.provider.is_approved)

    def test_refuse_creates_audit_log(self):
        self.http.post(
            '/api/admin/prestataires/bulk-action/',
            data=json.dumps({'ids': [self.provider.id], 'action': 'refuse', 'motif': 'Test'}),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.admin_token}',
        )
        self.assertTrue(
            AdminAuditLog.objects.filter(
                action__in=['provider_refused', 'bulk_refuse'],
                target_id=self.provider.id,
            ).exists()
        )

    def test_accept_creates_audit_log(self):
        self.http.post(
            '/api/admin/prestataires/bulk-action/',
            data=json.dumps({'ids': [self.provider.id], 'action': 'accept'}),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.admin_token}',
        )
        self.assertTrue(
            AdminAuditLog.objects.filter(
                action__in=['provider_accepted', 'bulk_accept'],
                target_id=self.provider.id,
            ).exists()
        )

    def test_bulk_action_requires_admin_role(self):
        """Un token client ne peut pas faire de bulk action."""
        _, client_token = (lambda u: (u, create_token(u.id, 'client')))(
            User.objects.create_user(username='mere_client', password='x')
        )
        UserProfile.objects.create(
            user=User.objects.get(username='mere_client'), role='client'
        )
        resp = self.http.post(
            '/api/admin/prestataires/bulk-action/',
            data=json.dumps({'ids': [self.provider.id], 'action': 'accept'}),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {client_token}',
        )
        self.assertIn(resp.status_code, [401, 403])


class ProviderAvailabilityTest(TestCase):
    """Tests de PATCH /api/prestataire/availability/."""

    def setUp(self):
        self.http = DjangoClient()
        self.prest_user, self.prest_token = _make_prestataire_user('prest_avail')
        self.provider = Provider.objects.create(
            user=self.prest_user,
            nom='Avail Test',
            specialite='Ménage',
            ville='Abidjan',
            statut=Provider.Status.VALID,
            disponible=True,
        )

    def _patch_avail(self, disponible):
        return self.http.patch(
            '/api/prestataire/availability/',
            data=json.dumps({'disponible': disponible}),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.prest_token}',
        )

    def test_set_unavailable(self):
        resp = self._patch_avail(False)
        self.assertIn(resp.status_code, [200, 201])
        self.provider.refresh_from_db()
        self.assertFalse(self.provider.disponible)

    def test_set_available(self):
        self.provider.disponible = False
        self.provider.save()
        resp = self._patch_avail(True)
        self.assertIn(resp.status_code, [200, 201])
        self.provider.refresh_from_db()
        self.assertTrue(self.provider.disponible)

    def test_availability_without_token_returns_401(self):
        resp = self.http.patch(
            '/api/prestataire/availability/',
            data=json.dumps({'disponible': False}),
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, 401)


class ProviderEarningsTest(TestCase):
    """Tests de GET /api/prestataire/earnings."""

    def setUp(self):
        self.http = DjangoClient()
        self.prest_user, self.prest_token = _make_prestataire_user('prest_earn')
        Provider.objects.create(
            user=self.prest_user,
            nom='Earn Test',
            specialite='Plomberie',
            ville='Abidjan',
            statut=Provider.Status.VALID,
        )

    def test_earnings_returns_200(self):
        resp = self.http.get(
            '/api/prestataire/earnings?period=month',
            HTTP_AUTHORIZATION=f'Bearer {self.prest_token}',
        )
        self.assertEqual(resp.status_code, 200)

    def test_earnings_response_has_summary_key(self):
        resp = self.http.get(
            '/api/prestataire/earnings',
            HTTP_AUTHORIZATION=f'Bearer {self.prest_token}',
        )
        data = resp.json()
        self.assertIn('summary', data)

    def test_earnings_day_period(self):
        resp = self.http.get(
            '/api/prestataire/earnings?period=day',
            HTTP_AUTHORIZATION=f'Bearer {self.prest_token}',
        )
        self.assertEqual(resp.status_code, 200)

    def test_earnings_week_period(self):
        resp = self.http.get(
            '/api/prestataire/earnings?period=week',
            HTTP_AUTHORIZATION=f'Bearer {self.prest_token}',
        )
        self.assertEqual(resp.status_code, 200)

    def test_earnings_all_period(self):
        resp = self.http.get(
            '/api/prestataire/earnings?period=all',
            HTTP_AUTHORIZATION=f'Bearer {self.prest_token}',
        )
        self.assertEqual(resp.status_code, 200)

    def test_earnings_without_auth_returns_401(self):
        resp = self.http.get('/api/prestataire/earnings')
        self.assertEqual(resp.status_code, 401)


class ProviderMeTest(TestCase):
    """Tests de GET /api/prestataire/me."""

    def setUp(self):
        self.http = DjangoClient()
        self.prest_user, self.prest_token = _make_prestataire_user('prest_me')
        self.provider = Provider.objects.create(
            user=self.prest_user,
            nom='Me Test',
            specialite='Jardinage',
            ville='Abidjan',
            statut=Provider.Status.VALID,
            average_rating=4.5,
            rating_count=12,
        )

    def test_me_returns_provider_data(self):
        resp = self.http.get(
            '/api/prestataire/me',
            HTTP_AUTHORIZATION=f'Bearer {self.prest_token}',
        )
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertIn('provider', data)
        prov = data['provider']
        self.assertEqual(prov['nom'], 'Me Test')

    def test_me_includes_statut(self):
        resp = self.http.get(
            '/api/prestataire/me',
            HTTP_AUTHORIZATION=f'Bearer {self.prest_token}',
        )
        prov = resp.json()['provider']
        self.assertIn('statut', prov)
        self.assertEqual(prov['statut'], 'Valide')

    def test_me_without_auth_returns_401(self):
        resp = self.http.get('/api/prestataire/me')
        self.assertEqual(resp.status_code, 401)
