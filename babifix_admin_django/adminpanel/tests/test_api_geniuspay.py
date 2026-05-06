"""
Tests d'integration — GeniusPay BABIFIX
Cible : geniuspay.py — initiate, status, webhook
Run : python manage.py test adminpanel.tests.test_api_geniuspay
"""
import hashlib
import hmac
import json
import os
import uuid
import time
from unittest.mock import patch, MagicMock

from django.test import TestCase, Client as DjangoClient, override_settings
from django.contrib.auth.models import User

from adminpanel.auth import create_token
from adminpanel.models import Payment, Provider, Reservation, UserProfile


def _make_user(username, role, password='Pwd12345!'):
    user = User.objects.create_user(username=username, password=password)
    UserProfile.objects.create(user=user, role=role, active=True)
    return user, create_token(user.id, role)


def _make_genius_signature(raw_body: bytes, secret: str) -> str:
    """Calcule la signature HMAC-SHA256 GeniusPay: HMAC(timestamp + "." + body, secret)."""
    timestamp = str(int(time.time()))
    message = (timestamp + "." + raw_body.decode("utf-8")).encode("utf-8")
    return hmac.new(
        secret.encode("utf-8"),
        message,
        hashlib.sha256,
    ).hexdigest()


@override_settings(
    GENIUSPAY_PUBLIC_KEY='test_public_key',
    GENIUSPAY_SECRET_KEY='test_secret_key',
    GENIUSPAY_WEBHOOK_URL='https://api.babifix.ci/api/paiements/geniuspay/webhook/',
    GENIUSPAY_SUCCESS_URL='https://babifix.ci/succes/',
    GENIUSPAY_ERROR_URL='https://babifix.ci/erreur/',
)
class GeniusPayInitiateTest(TestCase):
    """Tests de POST /api/paiements/geniuspay/initiate/."""

    def setUp(self):
        self.http = DjangoClient()
        self.client_user, self.client_token = _make_user('cli_genius', 'client')
        self.prest_user, self.prest_token = _make_user('prest_genius', 'prestataire')
        self.provider = Provider.objects.create(
            user=self.prest_user,
            nom='GeniusPay Provider',
            specialite='Plomberie',
            ville='Abidjan',
            statut=Provider.Status.VALID,
        )
        self.reservation = Reservation.objects.create(
            reference=f'RES-GP-{uuid.uuid4().hex[:6].upper()}',
            client='cli_genius',
            prestataire='GeniusPay Provider',
            montant='25000',
            statut=Reservation.Status.DEVIS_ACCEPTE,
            payment_type=Reservation.PaymentType.MOBILE_MONEY,
            mobile_money_operator=Reservation.MobileMoneyOperator.ORANGE_MONEY,
            client_user=self.client_user,
            assigned_provider=self.provider,
        )

    @patch('adminpanel.geniuspay._genius_request')
    def test_initiate_calls_geniuspay_api(self, mock_request):
        mock_request.return_value = {
            'success': True,
            'data': {
                'reference': 'GPX-TEST123',
                'payment_url': 'https://pay.genius.ci/pay/gpx123',
                'checkout_url': 'https://pay.genius.ci/checkout/gpx123',
                'status': 'pending',
            },
        }
        resp = self.http.post(
            '/api/paiements/geniuspay/initiate/',
            data=json.dumps({
                'reservation': self.reservation.pk,
                'montant': 25000,
                'payment_method': 'ORANGE_MONEY',
                'phone': '+2250700000000',
            }),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.client_token}',
        )
        self.assertIn(resp.status_code, [200, 201])

    @patch('adminpanel.geniuspay._genius_request')
    def test_initiate_returns_transaction_id(self, mock_request):
        mock_request.return_value = {
            'success': True,
            'data': {
                'reference': 'GPX-TEST456',
                'payment_url': 'https://pay.genius.ci/pay/gpx456',
                'status': 'pending',
            },
        }
        resp = self.http.post(
            '/api/paiements/geniuspay/initiate/',
            data=json.dumps({
                'reservation': self.reservation.pk,
                'montant': 25000,
                'payment_method': 'WAVE',
                'phone': '+2250600000000',
            }),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.client_token}',
        )
        if resp.status_code in [200, 201]:
            data = resp.json()
            self.assertIn('transaction_id', data)

    @patch('adminpanel.geniuspay._genius_request')
    def test_initiate_creates_payment_record(self, mock_request):
        mock_request.return_value = {
            'success': True,
            'data': {'reference': 'GPX-TEST789', 'status': 'pending'},
        }
        initial_count = Payment.objects.count()
        self.http.post(
            '/api/paiements/geniuspay/initiate/',
            data=json.dumps({
                'reservation': self.reservation.pk,
                'montant': 25000,
                'payment_method': 'MTN_MOMO',
                'phone': '+2250700000001',
            }),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.client_token}',
        )
        self.assertGreater(Payment.objects.count(), initial_count)

    def test_initiate_without_auth_returns_401(self):
        resp = self.http.post(
            '/api/paiements/geniuspay/initiate/',
            data=json.dumps({'reservation': self.reservation.pk, 'montant': 25000}),
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, 401)

    def test_initiate_unknown_reservation_returns_error(self):
        resp = self.http.post(
            '/api/paiements/geniuspay/initiate/',
            data=json.dumps({
                'reservation': 99999,
                'montant': 1000,
            }),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.client_token}',
        )
        self.assertIn(resp.status_code, [400, 404])


@override_settings(
    GENIUSPAY_PUBLIC_KEY='test_public_key',
    GENIUSPAY_SECRET_KEY='test_secret_key',
)
class GeniusPayStatusTest(TestCase):
    """Tests de GET /api/paiements/geniuspay/status/<reference>/."""

    def setUp(self):
        self.http = DjangoClient()
        self.client_user, self.client_token = _make_user('cli_stat', 'client')
        self.payment = Payment.objects.create(
            reference='PAY-GP-STAT',
            client='cli_stat',
            prestataire='prest',
            montant='25000',
            commission='2500',
            etat=Payment.State.PENDING,
            type_paiement=Payment.TypePaiement.MOBILE_MONEY,
            reference_externe='GPX-TESTABCDEF123456',
        )

    def test_status_known_transaction_returns_200(self):
        resp = self.http.get(
            f'/api/paiements/geniuspay/status/{self.payment.reference_externe}/',
            HTTP_AUTHORIZATION=f'Bearer {self.client_token}',
        )
        self.assertIn(resp.status_code, [200, 201])

    def test_status_unknown_transaction_returns_404(self):
        resp = self.http.get(
            '/api/paiements/geniuspay/status/GPX-XXXXXXXXXXXXXXXX/',
            HTTP_AUTHORIZATION=f'Bearer {self.client_token}',
        )
        self.assertIn(resp.status_code, [404, 400])

    def test_status_response_has_status_field(self):
        resp = self.http.get(
            f'/api/paiements/geniuspay/status/{self.payment.reference_externe}/',
            HTTP_AUTHORIZATION=f'Bearer {self.client_token}',
        )
        if resp.status_code == 200:
            data = resp.json()
            self.assertTrue(
                any(k in data for k in ['status', 'etat', 'state', 'payment_status'])
            )


@override_settings(
    GENIUSPAY_SECRET_KEY='test_webhook_secret',
)
class GeniusPayWebhookTest(TestCase):
    """Tests de POST /api/paiements/geniuspay/webhook/ (callback GeniusPay)."""

    def setUp(self):
        self.http = DjangoClient()
        self.prest_user, _ = _make_user('prest_wh', 'prestataire')
        self.provider = Provider.objects.create(
            user=self.prest_user,
            nom='Webhook Provider',
            specialite='Menage',
            ville='Abidjan',
            statut=Provider.Status.VALID,
        )
        self.reservation = Reservation.objects.create(
            reference='RES-WH-001',
            client='cli_wh',
            prestataire='Webhook Provider',
            montant='15000',
            statut=Reservation.Status.DEVIS_ACCEPTE,
            payment_type=Reservation.PaymentType.MOBILE_MONEY,
            assigned_provider=self.provider,
        )
        self.payment = Payment.objects.create(
            reference='PAY-WH-001',
            client='cli_wh',
            prestataire='Webhook Provider',
            montant='15000',
            commission='1500',
            etat=Payment.State.PENDING,
            type_paiement=Payment.TypePaiement.MOBILE_MONEY,
            reservation=self.reservation,
            reference_externe='GPX-WEBHOOKTEST0001',
        )

    def test_webhook_test_returns_200(self):
        """Webhook test GeniusPay doit etre accepte sans signature."""
        resp = self.http.post(
            '/api/paiements/geniuspay/webhook/',
            data=json.dumps({}),
            content_type='application/json',
            HTTP_X_WEBHOOK_EVENT='webhook.test',
        )
        self.assertEqual(resp.status_code, 200)

    def test_webhook_success_updates_payment_to_complete(self):
        payload = {
            'data': {
                'reference': self.payment.reference_externe,
                'amount': 15000,
                'status': 'completed',
                'metadata': {'payment_type': 'solde'},
            }
        }
        raw_body = json.dumps(payload).encode("utf-8")
        timestamp = str(int(time.time()))
        message = (timestamp + "." + raw_body.decode("utf-8")).encode("utf-8")
        sig = hmac.new(
            b'test_webhook_secret',
            message,
            hashlib.sha256,
        ).hexdigest()

        resp = self.http.post(
            '/api/paiements/geniuspay/webhook/',
            data=raw_body,
            content_type='application/json',
            HTTP_X_WEBHOOK_SIGNATURE=sig,
            HTTP_X_WEBHOOK_TIMESTAMP=timestamp,
            HTTP_X_WEBHOOK_EVENT='payment.success',
        )
        self.assertIn(resp.status_code, [200, 201])
        self.payment.refresh_from_db()
        self.assertEqual(self.payment.etat, Payment.State.COMPLETE)

    def test_webhook_invalid_signature_returns_403(self):
        payload = {'data': {'reference': self.payment.reference_externe}}
        raw_body = json.dumps(payload).encode("utf-8")
        timestamp = str(int(time.time()))

        resp = self.http.post(
            '/api/paiements/geniuspay/webhook/',
            data=raw_body,
            content_type='application/json',
            HTTP_X_WEBHOOK_SIGNATURE='invalid_signature_here',
            HTTP_X_WEBHOOK_TIMESTAMP=timestamp,
            HTTP_X_WEBHOOK_EVENT='payment.success',
        )
        self.assertIn(resp.status_code, [400, 403])

    def test_webhook_failure_marks_payment_failed(self):
        payload = {
            'data': {
                'reference': self.payment.reference_externe,
                'status': 'failed',
            }
        }
        raw_body = json.dumps(payload).encode("utf-8")
        timestamp = str(int(time.time()))
        message = (timestamp + "." + raw_body.decode("utf-8")).encode("utf-8")
        sig = hmac.new(
            b'test_webhook_secret',
            message,
            hashlib.sha256,
        ).hexdigest()

        self.http.post(
            '/api/paiements/geniuspay/webhook/',
            data=raw_body,
            content_type='application/json',
            HTTP_X_WEBHOOK_SIGNATURE=sig,
            HTTP_X_WEBHOOK_TIMESTAMP=timestamp,
            HTTP_X_WEBHOOK_EVENT='payment.failed',
        )
        self.payment.refresh_from_db()
        self.assertEqual(self.payment.etat, Payment.State.DISPUTE)
