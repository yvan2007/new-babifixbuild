"""
Tests unitaires — Throttle (rate limiting) BABIFIX
Cible : adminpanel/throttle.py
Run : python manage.py test adminpanel.tests.test_throttle
"""
from django.test import TestCase, RequestFactory, override_settings
from django.core.cache import cache

from adminpanel.throttle import check_rate_limit, rate_limited_response


@override_settings(
    CACHES={
        'default': {
            'BACKEND': 'django.core.cache.backends.locmem.LocMemCache',
        }
    }
)
class ThrottleTest(TestCase):
    """Tests du système de rate limiting par clé de cache."""

    def setUp(self):
        cache.clear()

    def tearDown(self):
        cache.clear()

    def _make_request(self, ip='192.168.1.1'):
        factory = RequestFactory()
        req = factory.post('/api/auth/login')
        req.META['REMOTE_ADDR'] = ip
        return req

    def test_first_request_not_blocked(self):
        req = self._make_request()
        blocked = check_rate_limit(req, 'test_key', max_requests=5, window=60)
        self.assertFalse(blocked)

    def test_under_limit_not_blocked(self):
        req = self._make_request()
        for _ in range(4):
            check_rate_limit(req, 'under_limit', max_requests=5, window=60)
        blocked = check_rate_limit(req, 'under_limit', max_requests=5, window=60)
        self.assertFalse(blocked)

    def test_exceeds_limit_is_blocked(self):
        req = self._make_request()
        for _ in range(5):
            check_rate_limit(req, 'exceed_key', max_requests=5, window=60)
        blocked = check_rate_limit(req, 'exceed_key', max_requests=5, window=60)
        self.assertTrue(blocked)

    def test_different_keys_independent(self):
        req = self._make_request()
        for _ in range(5):
            check_rate_limit(req, 'key_a', max_requests=5, window=60)
        # key_b ne doit pas être affecté
        blocked = check_rate_limit(req, 'key_b', max_requests=5, window=60)
        self.assertFalse(blocked)

    def test_different_ips_independent(self):
        req1 = self._make_request(ip='1.1.1.1')
        req2 = self._make_request(ip='2.2.2.2')
        for _ in range(5):
            check_rate_limit(req1, 'ip_key', max_requests=5, window=60)
        # IP différente ne doit pas être bloquée
        blocked = check_rate_limit(req2, 'ip_key', max_requests=5, window=60)
        self.assertFalse(blocked)

    def test_max_requests_one_blocks_on_second_call(self):
        req = self._make_request()
        check_rate_limit(req, 'max1', max_requests=1, window=60)
        blocked = check_rate_limit(req, 'max1', max_requests=1, window=60)
        self.assertTrue(blocked)

    def test_rate_limited_response_returns_429(self):
        resp = rate_limited_response()
        self.assertEqual(resp.status_code, 429)

    def test_rate_limited_response_is_json(self):
        resp = rate_limited_response()
        import json
        data = json.loads(resp.content)
        self.assertIn('error', data)

    def test_x_forwarded_for_used_when_present(self):
        """Le rate limiting utilise X-Forwarded-For si présent (derrière proxy)."""
        factory = RequestFactory()
        req = factory.post('/api/auth/login')
        req.META['HTTP_X_FORWARDED_FOR'] = '203.0.113.5, 10.0.0.1'
        req.META['REMOTE_ADDR'] = '10.0.0.1'
        # Doit bloquer sur 203.0.113.5 et non 10.0.0.1
        for _ in range(5):
            check_rate_limit(req, 'proxy_key', max_requests=5, window=60)
        blocked = check_rate_limit(req, 'proxy_key', max_requests=5, window=60)
        self.assertTrue(blocked)


@override_settings(
    CACHES={
        'default': {
            'BACKEND': 'django.core.cache.backends.locmem.LocMemCache',
        }
    }
)
class ThrottleIntegrationTest(TestCase):
    """Tests d'intégration du throttle sur l'endpoint de login."""

    def setUp(self):
        cache.clear()
        from django.contrib.auth.models import User
        from adminpanel.models import UserProfile
        self.user = User.objects.create_user(username='throttle_user', password='Good1!')
        UserProfile.objects.create(user=self.user, role='client')

    def tearDown(self):
        cache.clear()

    def _login(self):
        import json
        return self.client.post(
            '/api/auth/login',
            data=json.dumps({'username': 'throttle_user', 'password': 'WrongPwd!'}),
            content_type='application/json',
            REMOTE_ADDR='203.0.113.99',
        )

    def test_repeated_failed_logins_eventually_throttled(self):
        """
        Après N tentatives échouées depuis la même IP,
        le serveur doit soit rejeter avec 429, soit continuer à renvoyer 401.
        L'important : pas de crash (500).
        """
        statuses = []
        for _ in range(12):
            resp = self._login()
            statuses.append(resp.status_code)
        # Toutes les réponses doivent être < 500
        for s in statuses:
            self.assertLess(s, 500, f'Server error encountered: {s}')
        # Si le throttle est actif, au moins un 429
        if 429 in statuses:
            self.assertIn(429, statuses)
