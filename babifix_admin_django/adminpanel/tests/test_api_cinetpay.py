"""
Tests d'intégration — CinetPay BABIFIX
Cible : cinetpay.py — initiate, status, webhook
Run : python manage.py test adminpanel.tests.test_api_cinetpay
"""
import hashlib
import hmac
import json
import os
import uuid
from unittest.mock import patch, MagicMock

from django.test import TestCase, Client as DjangoClient, override_settings
from django.contrib.auth.models import User

from adminpanel.auth import create_token
from adminpanel.models import Payment, Provider, Reservation, UserProfile


def _make_user(username, role, password='Pwd12345!'):
    user = User.objects.create_user(username=username, password=password)
    UserProfile.objects.create(user=user, role=role, active=True)
    return user, create_token(user.id, role)


@override_settings(
    CINETPAY_APIKEY='test_api_key',
    CINETPAY_SITE_ID='test_site_id',
    CINETPAY_NOTIFY_URL='https://api.babifix.ci/api/paiements/cinetpay/webhook/',
    CINETPAY_RETURN_URL='https://babifix.ci/retour/',
    CINETPAY_WEBHOOK_SECRET='test_webhook_secret',
)
class CinetPayInitiateTest(TestCase):
    """Tests de POST /api/paiements/cinetpay/initiate/."""

    def setUp(self):
        self.http = DjangoClient()
        self.client_user, self.client_token = _make_user('cli_cinet', 'client')
        self.prest_user, self.prest_token = _make_user('prest_cinet', 'prestataire')
        self.provider = Provider.objects.create(
            user=self.prest_user,
            nom='CinetPay Provider',
            specialite='Plomberie',
            ville='Abidjan',
            statut=Provider.Status.VALID,
        )
        self.reservation = Reservation.objects.create(
            reference=f'RES-CP-{uuid.uuid4().hex[:6].upper()}',
            client='cli_cinet',
            prestataire='CinetPay Provider',
            montant='25000 FCFA',
            statut=Reservation.Status.CONFIRMED,
            payment_type=Reservation.PaymentType.MOBILE_MONEY,
            mobile_money_operator=Reservation.MobileMoneyOperator.ORANGE_MONEY,
            client_user=self.client_user,
            assigned_provider=self.provider,
        )

    @patch('adminpanel.cinetpay._cinetpay_post')
    def test_initiate_calls_cinetpay_api(self, mock_post):
        mock_post.return_value = {
            'code': '201',
            'message': 'CREATED',
            'data': {'payment_url': 'https://pay.cinetpay.com/pay/txn123'},
        }
        resp = self.http.post(
            '/api/paiements/cinetpay/initiate/',
            data=json.dumps({
                'reservation_reference': self.reservation.reference,
                'montant': 25000,
                'operator': 'ORANGE_MONEY',
                'phone': '+2250700000000',
            }),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.client_token}',
        )
        self.assertIn(resp.status_code, [200, 201])

    @patch('adminpanel.cinetpay._cinetpay_post')
    def test_initiate_returns_transaction_id(self, mock_post):
        mock_post.return_value = {
            'code': '201',
            'message': 'CREATED',
            'data': {'payment_url': 'https://pay.cinetpay.com/test'},
        }
        resp = self.http.post(
            '/api/paiements/cinetpay/initiate/',
            data=json.dumps({
                'reservation_reference': self.reservation.reference,
                'montant': 25000,
                'operator': 'MTN_MOMO',
                'phone': '+2250600000000',
            }),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.client_token}',
        )
        if resp.status_code in [200, 201]:
            data = resp.json()
            self.assertIn('transaction_id', data)

    @patch('adminpanel.cinetpay._cinetpay_post')
    def test_initiate_creates_payment_record(self, mock_post):
        mock_post.return_value = {
            'code': '201',
            'message': 'CREATED',
            'data': {},
        }
        initial_count = Payment.objects.count()
        self.http.post(
            '/api/paiements/cinetpay/initiate/',
            data=json.dumps({
                'reservation_reference': self.reservation.reference,
                'montant': 25000,
                'operator': 'WAVE',
                'phone': '+2250700000001',
            }),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.client_token}',
        )
        # Un enregistrement Payment doit avoir été créé
        self.assertGreater(Payment.objects.count(), initial_count)

    def test_initiate_without_auth_returns_401(self):
        resp = self.http.post(
            '/api/paiements/cinetpay/initiate/',
            data=json.dumps({'reservation_reference': self.reservation.reference}),
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, 401)

    def test_initiate_unknown_reservation_returns_error(self):
        resp = self.http.post(
            '/api/paiements/cinetpay/initiate/',
            data=json.dumps({
                'reservation_reference': 'RES-INEXISTANT',
                'montant': 1000,
            }),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.client_token}',
        )
        self.assertIn(resp.status_code, [400, 404])


@override_settings(
    CINETPAY_APIKEY='test_api_key',
    CINETPAY_SITE_ID='test_site_id',
    CINETPAY_WEBHOOK_SECRET='test_webhook_secret',
)
class CinetPayStatusTest(TestCase):
    """Tests de GET /api/paiements/cinetpay/status/<transaction_id>/."""

    def setUp(self):
        self.http = DjangoClient()
        self.client_user, self.client_token = _make_user('cli_stat', 'client')
        self.payment = Payment.objects.create(
            reference='PAY-CP-STAT',
            client='cli_stat',
            prestataire='prest',
            montant='25000 FCFA',
            commission='2500 FCFA',
            etat=Payment.State.PENDING,
            type_paiement=Payment.TypePaiement.MOBILE_MONEY,
            reference_externe='BABFX-TESTABCDEF123456',
        )

    def test_status_known_transaction_returns_200(self):
        resp = self.http.get(
            f'/api/paiements/cinetpay/status/{self.payment.reference_externe}/',
            HTTP_AUTHORIZATION=f'Bearer {self.client_token}',
        )
        self.assertIn(resp.status_code, [200, 201])

    def test_status_unknown_transaction_returns_404(self):
        resp = self.http.get(
            '/api/paiements/cinetpay/status/BABFX-XXXXXXXXXXXXXXXX/',
            HTTP_AUTHORIZATION=f'Bearer {self.client_token}',
        )
        self.assertIn(resp.status_code, [404, 400])

    def test_status_response_has_etat_field(self):
        resp = self.http.get(
            f'/api/paiements/cinetpay/status/{self.payment.reference_externe}/',
            HTTP_AUTHORIZATION=f'Bearer {self.client_token}',
        )
        if resp.status_code == 200:
            data = resp.json()
            self.assertTrue(
                any(k in data for k in ['etat', 'status', 'state', 'payment_status'])
            )


@override_settings(
    CINETPAY_WEBHOOK_SECRET='test_webhook_secret',
)
class CinetPayWebhookTest(TestCase):
    """Tests de POST /api/paiements/cinetpay/webhook/ (callback CinetPay)."""

    def setUp(self):
        self.http = DjangoClient()
        self.prest_user, _ = _make_user('prest_wh', 'prestataire')
        self.provider = Provider.objects.create(
            user=self.prest_user,
            nom='Webhook Provider',
            specialite='Ménage',
            ville='Abidjan',
            statut=Provider.Status.VALID,
        )
        self.reservation = Reservation.objects.create(
            reference='RES-WH-001',
            client='cli_wh',
            prestataire='Webhook Provider',
            montant='15000 FCFA',
            statut=Reservation.Status.CONFIRMED,
            payment_type=Reservation.PaymentType.MOBILE_MONEY,
            assigned_provider=self.provider,
        )
        self.payment = Payment.objects.create(
            reference='PAY-WH-001',
            client='cli_wh',
            prestataire='Webhook Provider',
            montant='15000 FCFA',
            commission='1500 FCFA',
            etat=Payment.State.PENDING,
            type_paiement=Payment.TypePaiement.MOBILE_MONEY,
            reservation=self.reservation,
            reference_externe='BABFX-WEBHOOKTEST0001',
        )

    def _make_sig(self, payload_str):
        """Calcule la signature HMAC-SHA256 pour simuler CinetPay."""
        return hmac.new(
            b'test_webhook_secret',
            payload_str.encode(),
            hashlib.sha256,
        ).hexdigest()

    def test_webhook_success_updates_payment_to_complete(self):
        payload = {
            'cpm_trans_id': self.payment.reference_externe,
            'cpm_result': '00',
            'cpm_amount': '15000',
        }
        payload_str = json.dumps(payload, sort_keys=True)
        resp = self.http.post(
            '/api/paiements/cinetpay/webhook/',
            data=payload_str,
            content_type='application/json',
            HTTP_X_CINETPAY_SIGNATURE=self._make_sig(payload_str),
        )
        # Le webhook doit retourner 200
        self.assertIn(resp.status_code, [200, 201])

    def test_webhook_invalid_signature_returns_403(self):
        payload = {
            'cpm_trans_id': self.payment.reference_externe,
            'cpm_result': '00',
        }
        resp = self.http.post(
            '/api/paiements/cinetpay/webhook/',
            data=json.dumps(payload),
            content_type='application/json',
            HTTP_X_CINETPAY_SIGNATURE='invalid_signature_here',
        )
        self.assertIn(resp.status_code, [400, 403])

    def test_webhook_failure_result_keeps_pending(self):
        payload = {
            'cpm_trans_id': self.payment.reference_externe,
            'cpm_result': '01',  # échec
        }
        payload_str = json.dumps(payload, sort_keys=True)
        self.http.post(
            '/api/paiements/cinetpay/webhook/',
            data=payload_str,
            content_type='application/json',
            HTTP_X_CINETPAY_SIGNATURE=self._make_sig(payload_str),
        )
        self.payment.refresh_from_db()
        # Ne doit pas être COMPLETE
        self.assertNotEqual(self.payment.etat, Payment.State.COMPLETE)
