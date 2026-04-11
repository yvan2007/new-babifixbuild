"""
Tests d'intégration — Workflow Réservations BABIFIX
Cible : création, transitions de statut, flux espèces, notation, litige
Run : python manage.py test adminpanel.tests.test_api_reservations
"""
import json
import uuid

from django.test import TestCase, Client as DjangoClient
from django.contrib.auth.models import User

from adminpanel.auth import create_token
from adminpanel.models import Category, Provider, Reservation, UserProfile


def _unique_ref():
    return f'RES-{uuid.uuid4().hex[:8].upper()}'


def _make_user(username, role, password='Pwd12345!'):
    user = User.objects.create_user(username=username, password=password)
    UserProfile.objects.create(user=user, role=role, active=True)
    return user, create_token(user.id, role)


class ReservationCreationTest(TestCase):
    """Tests de POST /api/client/reservations (création de réservation)."""

    def setUp(self):
        self.http = DjangoClient()
        self.client_user, self.client_token = _make_user('cli_resv', 'client')
        self.prest_user, self.prest_token = _make_user('prest_resv', 'prestataire')
        self.provider = Provider.objects.create(
            user=self.prest_user,
            nom='Test Provider',
            specialite='Plomberie',
            ville='Abidjan',
            statut=Provider.Status.VALID,
        )

    def _post_reservation(self, payload, token=None):
        return self.http.post(
            '/api/client/reservations',
            data=json.dumps(payload),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {token or self.client_token}',
        )

    def test_create_reservation_returns_201(self):
        resp = self._post_reservation({
            'provider_id': self.provider.id,
            'title': 'Fuite robinet cuisine',
            'montant': '25000',
            'payment_type': 'ESPECES',
            'address_label': 'Cocody, Abidjan',
        })
        self.assertIn(resp.status_code, [200, 201])

    def test_create_reservation_returns_reference(self):
        resp = self._post_reservation({
            'provider_id': self.provider.id,
            'title': 'Réparation fuite',
            'montant': '30000',
        })
        data = resp.json()
        self.assertIn('reference', data)
        self.assertTrue(data['reference'].startswith('RES'))

    def test_create_reservation_default_status_pending(self):
        resp = self._post_reservation({
            'provider_id': self.provider.id,
            'title': 'Test status',
            'montant': '10000',
        })
        ref = resp.json().get('reference')
        if ref:
            resv = Reservation.objects.get(reference=ref)
            self.assertEqual(resv.statut, Reservation.Status.PENDING)

    def test_create_reservation_without_auth_returns_401(self):
        resp = self.http.post(
            '/api/client/reservations',
            data=json.dumps({'provider_id': self.provider.id, 'title': 'Test', 'montant': '0'}),
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, 401)

    def test_create_reservation_mobile_money(self):
        resp = self._post_reservation({
            'provider_id': self.provider.id,
            'title': 'Paiement Orange Money',
            'montant': '15000',
            'payment_type': 'MOBILE_MONEY',
            'mobile_money_operator': 'ORANGE_MONEY',
        })
        self.assertIn(resp.status_code, [200, 201])
        ref = resp.json().get('reference')
        if ref:
            resv = Reservation.objects.get(reference=ref)
            self.assertEqual(resv.payment_type, 'MOBILE_MONEY')
            self.assertEqual(resv.mobile_money_operator, 'ORANGE_MONEY')


class ReservationStatusTransitionTest(TestCase):
    """Tests des transitions de statut prestataire."""

    def setUp(self):
        self.http = DjangoClient()
        self.prest_user, self.prest_token = _make_user('prest_st', 'prestataire')
        self.client_user, self.client_token = _make_user('cli_st', 'client')
        self.provider = Provider.objects.create(
            user=self.prest_user,
            nom='Status Provider',
            specialite='Électricité',
            ville='Abidjan',
            statut=Provider.Status.VALID,
        )
        self.reservation = Reservation.objects.create(
            reference=_unique_ref(),
            client='cli_st',
            prestataire='Status Provider',
            montant='20000 FCFA',
            statut=Reservation.Status.PENDING,
            prestataire_user=self.prest_user,
            client_user=self.client_user,
            assigned_provider=self.provider,
        )

    def _decision(self, decision):
        return self.http.post(
            f'/api/prestataire/requests/{self.reservation.reference}/decision',
            data=json.dumps({'decision': decision}),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.prest_token}',
        )

    def test_prestataire_accepts_request(self):
        resp = self._decision('accept')
        self.assertIn(resp.status_code, [200, 201])
        self.reservation.refresh_from_db()
        self.assertEqual(self.reservation.statut, Reservation.Status.CONFIRMED)

    def test_prestataire_refuses_request(self):
        resp = self._decision('refuse')
        self.assertIn(resp.status_code, [200, 201])
        self.reservation.refresh_from_db()
        self.assertEqual(self.reservation.statut, Reservation.Status.CANCELLED)

    def test_decision_requires_prestataire_token(self):
        resp = self.http.post(
            f'/api/prestataire/requests/{self.reservation.reference}/decision',
            data=json.dumps({'decision': 'accept'}),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.client_token}',
        )
        self.assertIn(resp.status_code, [401, 403])

    def test_start_mission_after_confirm(self):
        # Confirmer d'abord
        self.reservation.statut = Reservation.Status.CONFIRMED
        self.reservation.save()
        resp = self.http.post(
            f'/api/prestataire/requests/{self.reservation.reference}/status',
            data=json.dumps({'status': 'En cours'}),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.prest_token}',
        )
        self.assertIn(resp.status_code, [200, 201])
        self.reservation.refresh_from_db()
        self.assertEqual(self.reservation.statut, Reservation.Status.IN_PROGRESS)

    def test_complete_mission(self):
        self.reservation.statut = Reservation.Status.IN_PROGRESS
        self.reservation.save()
        resp = self.http.post(
            f'/api/prestataire/requests/{self.reservation.reference}/status',
            data=json.dumps({'status': 'Terminee'}),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.prest_token}',
        )
        self.assertIn(resp.status_code, [200, 201])
        self.reservation.refresh_from_db()
        self.assertEqual(self.reservation.statut, Reservation.Status.DONE)

    def test_unknown_reservation_returns_404(self):
        resp = self.http.post(
            '/api/prestataire/requests/RES-XXXXXXXX/decision',
            data=json.dumps({'decision': 'accept'}),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.prest_token}',
        )
        self.assertIn(resp.status_code, [404, 400])


class CashPaymentFlowTest(TestCase):
    """Tests du flux paiement espèces (3 étapes : client → prestataire → admin)."""

    def setUp(self):
        self.http = DjangoClient()
        self.client_user, self.client_token = _make_user('cli_cash', 'client')
        self.prest_user, self.prest_token = _make_user('prest_cash', 'prestataire')
        self.admin_user, self.admin_token = _make_user('admin_cash', 'admin')
        self.provider = Provider.objects.create(
            user=self.prest_user,
            nom='Cash Provider',
            specialite='Ménage',
            ville='Abidjan',
            statut=Provider.Status.VALID,
        )
        self.reservation = Reservation.objects.create(
            reference=_unique_ref(),
            client='cli_cash',
            prestataire='Cash Provider',
            montant='15000 FCFA',
            statut=Reservation.Status.DONE,
            payment_type=Reservation.PaymentType.ESPECES,
            cash_flow_status=Reservation.CashFlowStatus.PENDING_PRESTATAIRE,
            prestataire_user=self.prest_user,
            client_user=self.client_user,
            assigned_provider=self.provider,
        )

    def test_prestataire_confirms_cash_receipt(self):
        resp = self.http.post(
            f'/api/prestataire/requests/{self.reservation.reference}/cash-confirm',
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.prest_token}',
        )
        self.assertIn(resp.status_code, [200, 201])
        self.reservation.refresh_from_db()
        self.assertEqual(
            self.reservation.cash_flow_status,
            Reservation.CashFlowStatus.PENDING_ADMIN,
        )

    def test_admin_validates_cash_payment(self):
        self.reservation.cash_flow_status = Reservation.CashFlowStatus.PENDING_ADMIN
        self.reservation.save()
        resp = self.http.post(
            f'/api/admin/reservations/{self.reservation.reference}/cash-validate',
            data=json.dumps({'action': 'validate'}),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.admin_token}',
        )
        self.assertIn(resp.status_code, [200, 201])
        self.reservation.refresh_from_db()
        self.assertEqual(
            self.reservation.cash_flow_status,
            Reservation.CashFlowStatus.VALIDATED,
        )

    def test_admin_refuses_cash_payment(self):
        self.reservation.cash_flow_status = Reservation.CashFlowStatus.PENDING_ADMIN
        self.reservation.save()
        resp = self.http.post(
            f'/api/admin/reservations/{self.reservation.reference}/cash-validate',
            data=json.dumps({'action': 'refuse', 'motif': 'Litige client'}),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.admin_token}',
        )
        self.assertIn(resp.status_code, [200, 201])
        self.reservation.refresh_from_db()
        self.assertEqual(
            self.reservation.cash_flow_status,
            Reservation.CashFlowStatus.REFUSED,
        )

    def test_cash_confirm_requires_prestataire_auth(self):
        resp = self.http.post(
            f'/api/prestataire/requests/{self.reservation.reference}/cash-confirm',
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.client_token}',
        )
        self.assertIn(resp.status_code, [401, 403])


class ReservationRequestsListTest(TestCase):
    """Tests de GET /api/prestataire/requests."""

    def setUp(self):
        self.http = DjangoClient()
        self.prest_user, self.prest_token = _make_user('prest_list', 'prestataire')
        self.provider = Provider.objects.create(
            user=self.prest_user,
            nom='List Provider',
            specialite='Plomberie',
            ville='Abidjan',
            statut=Provider.Status.VALID,
        )
        # Créer 3 réservations dans différents statuts
        for i, statut in enumerate([
            Reservation.Status.PENDING,
            Reservation.Status.CONFIRMED,
            Reservation.Status.DONE,
        ]):
            Reservation.objects.create(
                reference=f'RES-LIST-{i}',
                client=f'Client {i}',
                prestataire='List Provider',
                montant=f'{(i+1)*10000} FCFA',
                statut=statut,
                prestataire_user=self.prest_user,
                assigned_provider=self.provider,
            )

    def test_requests_returns_200(self):
        resp = self.http.get(
            '/api/prestataire/requests',
            HTTP_AUTHORIZATION=f'Bearer {self.prest_token}',
        )
        self.assertEqual(resp.status_code, 200)

    def test_requests_returns_items_key(self):
        resp = self.http.get(
            '/api/prestataire/requests',
            HTTP_AUTHORIZATION=f'Bearer {self.prest_token}',
        )
        data = resp.json()
        self.assertIn('items', data)

    def test_requests_items_is_list(self):
        resp = self.http.get(
            '/api/prestataire/requests',
            HTTP_AUTHORIZATION=f'Bearer {self.prest_token}',
        )
        self.assertIsInstance(resp.json()['items'], list)

    def test_requests_without_auth_returns_401(self):
        resp = self.http.get('/api/prestataire/requests')
        self.assertEqual(resp.status_code, 401)
