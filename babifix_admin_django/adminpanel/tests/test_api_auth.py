"""
Tests d'intégration — Endpoints d'authentification BABIFIX
Cible : /api/auth/login, /api/auth/register, /api/auth/me
Run : python manage.py test adminpanel.tests.test_api_auth
"""
import json

from django.test import TestCase, Client as DjangoClient
from django.contrib.auth.models import User

from adminpanel.auth import create_token
from adminpanel.models import UserProfile


class AuthLoginTest(TestCase):
    """Tests de l'endpoint POST /api/auth/login."""

    def setUp(self):
        self.client = DjangoClient()
        self.user = User.objects.create_user(
            username='test_client',
            password='Secure123!',
            email='client@babifix.ci',
        )
        UserProfile.objects.create(user=self.user, role='client', active=True)

    def _post_login(self, username, password):
        return self.client.post(
            '/api/auth/login',
            data=json.dumps({'username': username, 'password': password}),
            content_type='application/json',
        )

    # ── succès ───────────────────────────────────────────────────────────────
    def test_login_success_returns_token_and_role(self):
        resp = self._post_login('test_client', 'Secure123!')
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertIn('token', data)
        self.assertEqual(data['role'], 'client')
        self.assertEqual(data['username'], 'test_client')

    def test_login_token_is_non_empty_string(self):
        resp = self._post_login('test_client', 'Secure123!')
        data = resp.json()
        self.assertIsInstance(data['token'], str)
        self.assertGreater(len(data['token']), 20)

    # ── échec ─────────────────────────────────────────────────────────────────
    def test_login_wrong_password_returns_401(self):
        resp = self._post_login('test_client', 'WrongPassword')
        self.assertIn(resp.status_code, [401, 400])

    def test_login_unknown_user_returns_401(self):
        resp = self._post_login('nobody', 'anything')
        self.assertIn(resp.status_code, [401, 400])

    def test_login_empty_body_returns_400(self):
        resp = self.client.post(
            '/api/auth/login',
            data='{}',
            content_type='application/json',
        )
        self.assertIn(resp.status_code, [400, 401])

    def test_login_invalid_json_returns_400(self):
        resp = self.client.post(
            '/api/auth/login',
            data='not_json',
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, 400)

    def test_login_method_get_not_allowed(self):
        resp = self.client.get('/api/auth/login')
        self.assertIn(resp.status_code, [405, 404])


class AuthRegisterTest(TestCase):
    """Tests de l'endpoint POST /api/auth/register."""

    def setUp(self):
        self.client = DjangoClient()

    def _post_register(self, payload):
        return self.client.post(
            '/api/auth/register',
            data=json.dumps(payload),
            content_type='application/json',
        )

    def test_register_client_creates_user_and_profile(self):
        resp = self._post_register({
            'username': 'nouveau_client',
            'password': 'Password123!',
            'role': 'client',
        })
        self.assertIn(resp.status_code, [200, 201])
        self.assertTrue(User.objects.filter(username='nouveau_client').exists())
        profile = UserProfile.objects.get(user__username='nouveau_client')
        self.assertEqual(profile.role, 'client')

    def test_register_prestataire_creates_user_with_correct_role(self):
        resp = self._post_register({
            'username': 'nouveau_prest',
            'password': 'Password123!',
            'role': 'prestataire',
        })
        self.assertIn(resp.status_code, [200, 201])
        profile = UserProfile.objects.get(user__username='nouveau_prest')
        self.assertEqual(profile.role, 'prestataire')

    def test_register_duplicate_username_returns_error(self):
        self._post_register({
            'username': 'dup_user',
            'password': 'Password1!',
            'role': 'client',
        })
        resp = self._post_register({
            'username': 'dup_user',
            'password': 'Password1!',
            'role': 'client',
        })
        self.assertNotEqual(resp.status_code, 200)

    def test_register_missing_username_returns_400(self):
        resp = self._post_register({'password': 'Password1!', 'role': 'client'})
        self.assertIn(resp.status_code, [400, 422])

    def test_register_missing_password_returns_400(self):
        resp = self._post_register({'username': 'test_no_pw', 'role': 'client'})
        self.assertIn(resp.status_code, [400, 422])

    def test_register_invalid_role_returns_error(self):
        resp = self._post_register({
            'username': 'bad_role',
            'password': 'Password1!',
            'role': 'superadmin_hacker',
        })
        self.assertNotIn(resp.status_code, [200, 201])


class TokenAuthMiddlewareTest(TestCase):
    """Tests du système de token Bearer pour les endpoints protégés."""

    def setUp(self):
        self.client = DjangoClient()
        self.user = User.objects.create_user(username='auth_user', password='Pwd1!')
        UserProfile.objects.create(user=self.user, role='client', active=True)
        self.token = create_token(self.user.id, 'client')

    def _auth_header(self, token=None):
        return {'HTTP_AUTHORIZATION': f'Bearer {token or self.token}'}

    def test_protected_endpoint_without_token_returns_401(self):
        resp = self.client.get('/api/auth/me')
        self.assertEqual(resp.status_code, 401)

    def test_protected_endpoint_with_valid_token_returns_200(self):
        resp = self.client.get('/api/auth/me', **self._auth_header())
        self.assertIn(resp.status_code, [200, 201])

    def test_invalid_token_returns_401(self):
        resp = self.client.get('/api/auth/me', **self._auth_header('invalid.token.here'))
        self.assertEqual(resp.status_code, 401)

    def test_malformed_bearer_prefix_returns_401(self):
        resp = self.client.get(
            '/api/auth/me',
            HTTP_AUTHORIZATION=f'Token {self.token}',  # wrong prefix
        )
        self.assertEqual(resp.status_code, 401)

    def test_role_restriction_prestataire_endpoint_with_client_token(self):
        """Un token client ne peut pas accéder aux endpoints prestataire protégés."""
        resp = self.client.patch(
            '/api/prestataire/availability/',
            data=json.dumps({'disponible': False}),
            content_type='application/json',
            **self._auth_header(),
        )
        # Either 403 (role mismatch) or endpoint-specific error
        self.assertIn(resp.status_code, [403, 401, 405])
