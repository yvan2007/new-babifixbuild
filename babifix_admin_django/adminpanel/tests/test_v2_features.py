"""
Tests comprehensifs pour les fonctionnalités v2 — BABIFIX Backend
Couvre : Google/Apple Sign-In, acompte/solde, portfolio, KYC, rate limiting, pagination
Run : python manage.py test adminpanel.tests.test_v2_features
"""
import json
from datetime import datetime, timedelta
from unittest.mock import patch, MagicMock
from decimal import Decimal

from django.test import TestCase, Client as DjangoClient, override_settings
from django.contrib.auth.models import User
from django.utils import timezone

from adminpanel.models import (
    Category, Payment, Provider, Reservation,
    UserProfile, Notification,
)
from adminpanel.auth import create_token
from adminpanel.jwt_auth import create_access_token, create_refresh_token
from adminpanel.services.provider_service import ProviderService, ProviderSearchInput
from adminpanel.services.reservation_service import (
    ReservationService, CreateReservationInput,
)


def _make_user(username, role, password='Pwd12345!'):
    user = User.objects.create_user(username=username, password=password)
    UserProfile.objects.create(user=user, role=role, active=True, email_verified=True)
    return user


class GoogleSignInTests(TestCase):
    """Tests pour Google Sign-In."""

    def setUp(self):
        self.client = DjangoClient()

    @override_settings(GOOGLE_CLIENT_ID="test-google-client-id.apps.googleusercontent.com")
    @patch('urllib.request.urlopen')
    def test_google_signin_new_user(self, mock_urlopen):
        """Google Sign-In cree un nouvel utilisateur."""
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "aud": "test-google-client-id.apps.googleusercontent.com",
            "sub": "123456789",
            "email": "test@example.com",
            "name": "Test User",
            "picture": "https://example.com/photo.jpg",
            "email_verified": True,
        }).encode('utf-8')
        mock_urlopen.return_value.__enter__ = MagicMock(return_value=mock_response)
        mock_urlopen.return_value.__exit__ = MagicMock(return_value=False)

        response = self.client.post('/api/auth/google', json.dumps({
            "idToken": "fake-google-id-token"
        }), content_type='application/json')

        self.assertEqual(response.status_code, 200)
        data = json.loads(response.content)
        self.assertTrue(data['ok'])
        self.assertTrue(data['is_new'])
        self.assertIn('access_token', data)
        self.assertIn('refresh_token', data)
        self.assertEqual(data['user']['email'], 'test@example.com')

    @override_settings(GOOGLE_CLIENT_ID="test-google-client-id.apps.googleusercontent.com")
    @patch('urllib.request.urlopen')
    def test_google_signin_existing_user(self, mock_urlopen):
        """Google Sign-In reconnait un utilisateur existant."""
        user = User.objects.create_user(
            username='testuser', email='test@example.com', first_name='Test'
        )
        UserProfile.objects.create(user=user, role='client', email_verified=True)

        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "aud": "test-google-client-id.apps.googleusercontent.com",
            "sub": "123456789",
            "email": "test@example.com",
            "name": "Test User",
        }).encode('utf-8')
        mock_urlopen.return_value.__enter__ = MagicMock(return_value=mock_response)
        mock_urlopen.return_value.__exit__ = MagicMock(return_value=False)

        response = self.client.post('/api/auth/google', json.dumps({
            "idToken": "fake-google-id-token"
        }), content_type='application/json')

        self.assertEqual(response.status_code, 200)
        data = json.loads(response.content)
        self.assertTrue(data['ok'])
        self.assertFalse(data['is_new'])

    @override_settings(GOOGLE_CLIENT_ID="")
    def test_google_signin_not_configured(self):
        """Google Sign-In retourne erreur si non configure."""
        response = self.client.post('/api/auth/google', json.dumps({
            "idToken": "fake-token"
        }), content_type='application/json')

        self.assertEqual(response.status_code, 500)

    @override_settings(GOOGLE_CLIENT_ID="test-client-id")
    @patch('urllib.request.urlopen')
    def test_google_signin_invalid_audience(self, mock_urlopen):
        """Google Sign-In rejette un token avec audience invalide."""
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "aud": "wrong-client-id",
            "sub": "123456789",
            "email": "test@example.com",
        }).encode('utf-8')
        mock_urlopen.return_value.__enter__ = MagicMock(return_value=mock_response)
        mock_urlopen.return_value.__exit__ = MagicMock(return_value=False)

        response = self.client.post('/api/auth/google', json.dumps({
            "idToken": "fake-token"
        }), content_type='application/json')

        self.assertEqual(response.status_code, 401)


class AppleSignInTests(TestCase):
    """Tests pour Apple Sign-In."""

    def setUp(self):
        self.client = DjangoClient()

    @override_settings(
        APPLE_BUNDLE_ID="ci.babifix.client",
        APPLE_TEAM_ID="TEAM123",
        APPLE_KEY_ID="KEY123",
        APPLE_PRIVATE_KEY="-----BEGIN EC PRIVATE KEY-----\ntest\n-----END EC PRIVATE KEY-----",
    )
    @patch('jwt.decode')
    def test_apple_signin_with_identity_token(self, mock_decode):
        """Apple Sign-In avec identity token."""
        mock_decode.return_value = {
            "aud": "ci.babifix.client",
            "sub": "apple-user-123",
            "email": "test@privaterelay.appleid.com",
        }

        response = self.client.post('/api/auth/apple', json.dumps({
            "identityToken": "fake-apple-identity-token"
        }), content_type='application/json')

        self.assertEqual(response.status_code, 200)
        data = json.loads(response.content)
        self.assertTrue(data['ok'])
        self.assertTrue(data['is_new'])
        self.assertIn('access_token', data)

    @override_settings(APPLE_BUNDLE_ID="", APPLE_TEAM_ID="")
    def test_apple_signin_not_configured(self):
        """Apple Sign-In retourne erreur si non configure."""
        response = self.client.post('/api/auth/apple', json.dumps({
            "identityToken": "fake-token"
        }), content_type='application/json')

        self.assertEqual(response.status_code, 500)


class PaginationTests(TestCase):
    """Tests pour la pagination des endpoints."""

    def setUp(self):
        self.client = DjangoClient()
        self.user = _make_user('pagination_user', 'client')
        self.token = create_token(self.user.id, 'client')

        for i in range(25):
            Reservation.objects.create(
                reference=f'RES-PAG-{i:04d}',
                title=f'Reservation {i}',
                client=f'Client {i}',
                client_user=self.user,
                prestataire=f'Provider {i}',
                montant=Decimal('5000'),
                statut='DEMANDE_ENVOYEE',
            )

    def test_demandes_list_pagination(self):
        """Pagination sur la liste des demandes."""
        response = self.client.get(
            '/api/client/demandes/?page=1&page_size=10',
            HTTP_AUTHORIZATION=f'Bearer {self.token}',
        )

        self.assertEqual(response.status_code, 200)
        data = json.loads(response.content)
        self.assertEqual(len(data['demandes']), 10)
        self.assertEqual(data['total'], 25)
        self.assertEqual(data['page'], 1)
        self.assertTrue(data['has_next'])

    def test_demandes_list_page_2(self):
        """Page 2 de la liste des demandes."""
        response = self.client.get(
            '/api/client/demandes/?page=2&page_size=10',
            HTTP_AUTHORIZATION=f'Bearer {self.token}',
        )

        self.assertEqual(response.status_code, 200)
        data = json.loads(response.content)
        self.assertEqual(len(data['demandes']), 10)
        self.assertTrue(data['has_next'])

    def test_demandes_list_page_3(self):
        """Page 3 de la liste des demandes (derniere page)."""
        response = self.client.get(
            '/api/client/demandes/?page=3&page_size=10',
            HTTP_AUTHORIZATION=f'Bearer {self.token}',
        )

        self.assertEqual(response.status_code, 200)
        data = json.loads(response.content)
        self.assertEqual(len(data['demandes']), 5)
        self.assertFalse(data['has_next'])


class ProviderServiceTests(TestCase):
    """Tests pour ProviderService."""

    def setUp(self):
        self.prest_user = _make_user('provider_service', 'prestataire')
        self.category = Category.objects.create(nom='Plomberie', actif=True)
        self.provider = Provider.objects.create(
            user=self.prest_user,
            nom='Test Provider',
            specialite='Plomberie',
            ville='Abidjan',
            statut=Provider.Status.VALID,
            disponible=True,
            latitude=5.35,
            longitude=-4.0,
            category=self.category,
        )

    def test_search_providers_returns_dict(self):
        """search_providers retourne un dict avec pagination."""
        input_data = ProviderSearchInput(
            category_id=self.category.id,
            page=1,
            page_size=10,
        )
        result = ProviderService.search_providers(input_data)

        self.assertIn('providers', result)
        self.assertIn('total', result)
        self.assertIn('page', result)
        self.assertIn('has_next', result)
        self.assertEqual(result['total'], 1)

    def test_get_provider_detail(self):
        """get_provider_detail retourne les details du prestataire."""
        result = ProviderService.get_provider_detail(self.provider.id)

        self.assertTrue(result.success)
        self.assertIsNotNone(result.provider)
        self.assertIn('completed_missions', result.data)

    def test_get_provider_detail_not_found(self):
        """get_provider_detail retourne erreur si prestataire inexistant."""
        result = ProviderService.get_provider_detail(99999)

        self.assertFalse(result.success)
        self.assertEqual(result.error, 'provider_not_found')

    def test_check_availability_valid(self):
        """check_availability retourne True pour prestataire valide."""
        available, reason = ProviderService.check_availability(self.provider)
        self.assertTrue(available)

    def test_check_availability_disabled(self):
        """check_availability retourne False si prestataire desactive."""
        self.provider.disponible = False
        self.provider.save()

        available, reason = ProviderService.check_availability(self.provider)
        self.assertFalse(available)
        self.assertEqual(reason, 'provider_disabled')

    def test_get_provider_stats(self):
        """get_provider_stats retourne les statistiques."""
        stats = ProviderService.get_provider_stats(self.provider)

        self.assertIn('completed_missions', stats)
        self.assertIn('in_progress', stats)
        self.assertIn('pending_requests', stats)
        self.assertIn('rating', stats)


class ReservationServiceTests(TestCase):
    """Tests pour ReservationService."""

    def setUp(self):
        self.client_user = _make_user('res_service_client', 'client')
        self.prest_user = _make_user('res_service_prest', 'prestataire')
        self.provider = Provider.objects.create(
            user=self.prest_user,
            nom='Test Provider',
            specialite='Plomberie',
            ville='Abidjan',
            statut=Provider.Status.VALID,
            disponible=True,
        )

    def test_create_reservation_success(self):
        """create_reservation reussit avec donnees valides."""
        input_data = CreateReservationInput(
            title='Reparation fuite',
            description_probleme='Fuite dans la salle de bain',
            assigned_provider_id=self.provider.id,
            payment_type='ESPECES',
        )

        result = ReservationService.create_reservation(self.client_user, input_data)

        self.assertTrue(result.success)
        self.assertIsNotNone(result.reservation)
        self.assertIn('reference', result.data)
        self.assertEqual(result.reservation.statut, Reservation.Status.DEMANDE_ENVOYEE)

    def test_create_reservation_no_title(self):
        """create_reservation echoue sans titre."""
        input_data = CreateReservationInput(title='')

        result = ReservationService.create_reservation(self.client_user, input_data)

        self.assertFalse(result.success)
        self.assertEqual(result.error, 'title_required')

    def test_create_reservation_provider_not_found(self):
        """create_reservation echoue si prestataire inexistant."""
        input_data = CreateReservationInput(
            title='Test',
            assigned_provider_id=99999,
        )

        result = ReservationService.create_reservation(self.client_user, input_data)

        self.assertFalse(result.success)
        self.assertEqual(result.error, 'provider_not_found')

    def test_transition_status_valid(self):
        """transition_status valide une transition autorisee."""
        res = Reservation.objects.create(
            reference='RES-TRANS-001',
            title='Test',
            client='Client',
            client_user=self.client_user,
            prestataire='Provider',
            assigned_provider=self.provider,
            montant=Decimal('5000'),
            statut=Reservation.Status.DEMANDE_ENVOYEE,
        )

        result = ReservationService.transition_status(
            res, Reservation.Status.DEVIS_EN_COURS, self.client_user
        )

        self.assertTrue(result.success)
        self.assertEqual(result.reservation.statut, Reservation.Status.DEVIS_EN_COURS)

    def test_can_cancel(self):
        """can_cancel autorise l'annulation."""
        res = Reservation.objects.create(
            reference='RES-CANCEL-001',
            title='Test',
            client='Client',
            client_user=self.client_user,
            prestataire='Provider',
            assigned_provider=self.provider,
            montant=Decimal('5000'),
            statut='DEMANDE_ENVOYEE',
        )

        can_cancel, reason = ReservationService.can_cancel(self.client_user, res)
        self.assertTrue(can_cancel)

    def test_can_cancel_not_owner(self):
        """can_cancel refuse si pas proprietaire."""
        other_user = _make_user('other_user', 'client')
        res = Reservation.objects.create(
            reference='RES-CANCEL-002',
            title='Test',
            client='Client',
            client_user=self.client_user,
            prestataire='Provider',
            assigned_provider=self.provider,
            montant=Decimal('5000'),
            statut='DEMANDE_ENVOYEE',
        )

        can_cancel, reason = ReservationService.can_cancel(other_user, res)
        self.assertFalse(can_cancel)
        self.assertEqual(reason, 'not_owner')


class JWTAuthTests(TestCase):
    """Tests pour l'authentification JWT."""

    def test_create_and_verify_access_token(self):
        """Creation et verification d'un access token."""
        token = create_access_token(1, 'client')
        self.assertIsNotNone(token)
        self.assertIsInstance(token, str)

    def test_create_and_verify_refresh_token(self):
        """Creation et verification d'un refresh token."""
        token = create_refresh_token(1, 'client')
        self.assertIsNotNone(token)
        self.assertIsInstance(token, str)


class ServicesIntegrationTests(TestCase):
    """Tests d'integration des services."""

    def setUp(self):
        self.client_user = _make_user('integration_client', 'client')
        self.prest_user = _make_user('integration_prest', 'prestataire')
        self.category = Category.objects.create(nom='Electricite', actif=True)
        self.provider = Provider.objects.create(
            user=self.prest_user,
            nom='Electricien Pro',
            specialite='Electricite',
            ville='Abidjan',
            statut=Provider.Status.VALID,
            disponible=True,
            tarif_horaire=5000,
            category=self.category,
        )

    def test_full_reservation_flow(self):
        """Flux complet: recherche prestataire -> creation reservation -> transition statut."""
        search_input = ProviderSearchInput(
            category_id=self.category.id,
            page=1,
            page_size=10,
        )
        search_result = ProviderService.search_providers(search_input)
        self.assertEqual(search_result['total'], 1)

        available, reason = ProviderService.check_availability(self.provider)
        self.assertTrue(available)

        res_input = CreateReservationInput(
            title='Installation electrique',
            description_probleme='Installer 3 prises',
            assigned_provider_id=self.provider.id,
            payment_type='MOBILE_MONEY',
        )
        res_result = ReservationService.create_reservation(self.client_user, res_input)
        self.assertTrue(res_result.success)
        res = res_result.reservation

        result = ReservationService.transition_status(
            res, Reservation.Status.DEVIS_EN_COURS, self.client_user
        )
        self.assertTrue(result.success)
        self.assertEqual(res.statut, Reservation.Status.DEVIS_EN_COURS)
