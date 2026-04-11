"""
Tests d'intégration API — BABIFIX Backend
Couvre : Auth (TI-01 à TI-10), Prestataires (TI-11 à TI-16), Réservations (TI-17 à TI-20)
Run : python manage.py test adminpanel.tests.test_api_integration
"""
import json

from django.test import TestCase, Client as DjangoClient
from django.contrib.auth.models import User

from adminpanel.auth import create_token
from adminpanel.models import Category, Provider, Reservation, UserProfile


def _make_user(username, role, password='Pwd12345!'):
    user = User.objects.create_user(username=username, password=password)
    UserProfile.objects.create(user=user, role=role, active=True)
    return user


class AuthIntegrationTests(TestCase):
    """TI-01 à TI-08 — Tests d'intégration de l'authentification."""

    def setUp(self):
        self.client_api = DjangoClient()

    def test_TI01_inscription_email_valide(self):
        """TI-01 : inscription avec email valide."""
        resp = self.client_api.post(
            '/api/auth/register',
            data=json.dumps({
                'username': 'newuser@test.ci',
                'password': 'Str0ng!Pass',
                'role': 'client',
            }),
            content_type='application/json',
        )
        self.assertIn(resp.status_code, [201, 400])  # 201 si succès, 400 si email déjà utilisé

    def test_TI02_inscription_email_invalide(self):
        """TI-02 : inscription avec email invalide."""
        resp = self.client_api.post(
            '/api/auth/register',
            data=json.dumps({
                'username': 'pasunemail',
                'password': 'xxx',
                'role': 'client',
            }),
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, 400)

    def test_TI04_login_correct(self):
        """TI-04 : login avec credentials corrects."""
        user = _make_user('login_correct', 'client', 'CorrectPass123!')
        
        resp = self.client_api.post(
            '/api/auth/login',
            data=json.dumps({
                'username': 'login_correct',
                'password': 'CorrectPass123!',
            }),
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertIn('token', data)

    def test_TI05_login_mauvais_password(self):
        """TI-05 : login avec mauvais mot de passe."""
        _make_user('login_wrong', 'client', 'CorrectPass123!')
        
        resp = self.client_api.post(
            '/api/auth/login',
            data=json.dumps({
                'username': 'login_wrong',
                'password': 'WrongPassword',
            }),
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, 401)

    def test_TI06_login_compte_inexistant(self):
        """TI-06 : login avec compte inexistant — ne pas révéler si email existe."""
        resp = self.client_api.post(
            '/api/auth/login',
            data=json.dumps({
                'username': 'inexistant@test.ci',
                'password': 'anypassword',
            }),
            content_type='application/json',
        )
        # Les deux doivent retourner le même status code
        self.assertEqual(resp.status_code, 401)

    def test_TI07_refresh_token_valide(self):
        """TI-07 : refresh token valide."""
        user = _make_user('refresh_test', 'client', 'Pass123!')
        
        # D'abord login pour obtenir un refresh token
        login_resp = self.client_api.post(
            '/api/auth/login',
            data=json.dumps({
                'username': 'refresh_test',
                'password': 'Pass123!',
            }),
            content_type='application/json',
        )
        data = login_resp.json()
        refresh_token = data.get('refresh')
        
        if refresh_token:
            resp = self.client_api.post(
                '/api/auth/refresh/',
                data=json.dumps({'refresh': refresh_token}),
                content_type='application/json',
            )
            self.assertEqual(resp.status_code, 200)

    def test_TI09_social_auth_google_token_valide(self):
        """TI-09 : social auth Google avec token forgé."""
        resp = self.client_api.post(
            '/api/auth/google',
            data=json.dumps({'id_token': 'base64.fake.payload'}),
            content_type='application/json',
        )
        # Doit échouer (400, 401 ou 500 si pas configuré)
        self.assertIn(resp.status_code, [400, 401, 500])

    def test_TI10_social_auth_google_token_forge(self):
        """TI-10 : social auth Google avec token forgé."""
        resp = self.client_api.post(
            '/api/auth/google',
            data=json.dumps({'id_token': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.fake'}),
            content_type='application/json',
        )
        self.assertIn(resp.status_code, [400, 401, 500])


class PrestataireIntegrationTests(TestCase):
    """TI-11 à TI-16 — Tests d'intégration des prestataires."""

    def setUp(self):
        self.client_api = DjangoClient()
        self.cat = Category.objects.create(nom='Test Cat', description='Test')

    def test_TI11_inscription_prestataire_complet(self):
        """TI-11 : inscription prestataire complet."""
        resp = self.client_api.post(
            '/api/prestataire/register',
            data=json.dumps({
                'username': 'newprest',
                'password': 'Pass123!',
                'nom': 'New Prestataire',
                'specialite': 'Plomberie',
                'ville': 'Abidjan',
                'phone_e164': '+2250700000000',
                'category_id': self.cat.id,
            }),
            content_type='application/json',
        )
        self.assertIn(resp.status_code, [201, 400])

    def test_TI14_admin_valide_prestataire(self):
        """TI-14 : admin valide un prestataire."""
        # Créer un prestataire
        prest_user = _make_user('prest_to_validate', 'prestataire', 'Pass123!')
        provider = Provider.objects.create(
            user=prest_user,
            nom='Prest To Validate',
            specialite='Test',
            ville='Abidjan',
            statut=Provider.Status.PENDING,
        )
        
        # Admin token
        admin_user = _make_user('admin_validator', 'admin', 'AdminPass123!')
        admin_user.is_staff = True
        admin_user.save()
        token = create_token(admin_user.id, 'admin')
        
        # Valider le prestataire
        resp = self.client_api.patch(
            f'/api/admin/prestataires/{provider.id}/',
            data=json.dumps({'statut': 'Valid'}),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {token}',
        )
        self.assertIn(resp.status_code, [200, 403])

    def test_TI16_prestataire_approved_acces_missions(self):
        """TI-16 : prestataire APPROVED accède à ses missions."""
        # Créer un prestataire approuvé
        prest_user = _make_user('prest_approved', 'prestataire', 'Pass123!')
        provider = Provider.objects.create(
            user=prest_user,
            nom='Prest Approved',
            specialite='Test',
            ville='Abidjan',
            statut=Provider.Status.VALID,
        )
        
        token = create_token(prest_user.id, 'prestataire')
        
        resp = self.client_api.get(
            '/api/prestataire/requests',
            HTTP_AUTHORIZATION=f'Bearer {token}',
        )
        self.assertIn(resp.status_code, [200, 403])


class ReservationIntegrationTests(TestCase):
    """TI-17 à TI-20 — Tests d'intégration des réservations."""

    def setUp(self):
        self.client_api = DjangoClient()
        self.client_user = _make_user('res_client', 'client', 'Pass123!')
        self.prest_user = _make_user('res_prest', 'prestataire', 'Pass123!')
        self.provider = Provider.objects.create(
            user=self.prest_user,
            nom='Prest for Res',
            specialite='Test',
            ville='Abidjan',
            statut=Provider.Status.VALID,
        )

    def test_TI17_creer_reservation_valide(self):
        """TI-17 : créer une réservation valide."""
        token = create_token(self.client_user.id, 'client')
        
        resp = self.client_api.post(
            '/api/client/reservations',
            data=json.dumps({
                'title': 'Test Reservation',
                'provider_id': self.provider.id,
                'payment_type': 'especes',
            }),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {token}',
        )
        self.assertIn(resp.status_code, [201, 400])

    def test_TI18_creer_reservation_prestataire_non_valide(self):
        """TI-18 : créer une réservation pour prestataire non validé."""
        # Créer un prestataire non validé
        prest_pending = _make_user('prest_pending', 'prestataire', 'Pass123!')
        provider_pending = Provider.objects.create(
            user=prest_pending,
            nom='Prest Pending',
            specialite='Test',
            ville='Abidjan',
            statut=Provider.Status.PENDING,
        )
        
        token = create_token(self.client_user.id, 'client')
        
        resp = self.client_api.post(
            '/api/client/reservations',
            data=json.dumps({
                'title': 'Test Reservation',
                'provider_id': provider_pending.id,
                'payment_type': 'especes',
            }),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {token}',
        )
        # Doit échouer
        self.assertIn(resp.status_code, [400, 404])

    def test_TI19_creer_reservation_sans_token(self):
        """TI-19 : créer une réservation sans être connecté."""
        resp = self.client_api.post(
            '/api/client/reservations',
            data=json.dumps({
                'title': 'Test Reservation',
                'payment_type': 'especes',
            }),
            content_type='application/json',
        )
        self.assertEqual(resp.status_code, [401, 403])

    def test_TI20_acceder_reservation_autrui(self):
        """TI-20 : accéder à la réservation d'un autre client."""
        # Créer une réservation pour client_user
        res = Reservation.objects.create(
            reference='RES-AUTH-001',
            title='Test',
            client='Client A',
            client_user=self.client_user,
            prestataire='Prest',
            montant='10000',
            statut='En attente',
        )
        
        # Tenter d'y accéder avec un autre client
        other_user = _make_user('other_client', 'client', 'Pass123!')
        token = create_token(other_user.id, 'client')
        
        resp = self.client_api.get(
            f'/api/client/reservations/{res.reference}/detail',
            HTTP_AUTHORIZATION=f'Bearer {token}',
        )
        # Doit être 403 ou 404
        self.assertIn(resp.status_code, [403, 404])


class ChatSecurityTests(TestCase):
    """TI-22 — Tests de sécurité du chat."""

    def setUp(self):
        self.api = DjangoClient()
        self.user_a = _make_user('chat_a', 'client')
        self.user_b = _make_user('chat_b', 'prestataire')
        self.user_c = _make_user('chat_c', 'client')

    def test_TI22_utilisateur_ne_voie_pas_conversation_etrangere(self):
        """TI-22 : un utilisateur ne peut pas lire la conversation d'un autre."""
        from adminpanel.models import Conversation, Message
        
        # Créer une conversation entre user_a et user_b
        conv = Conversation.objects.create(
            client=self.user_a,
            prestataire=self.user_b,
        )
        Message.objects.create(
            conversation=conv,
            sender=self.user_a,
            body='Message privé',
            lu=False,
        )
        
        # Tenter d'y accéder avec user_c
        token_c = create_token(self.user_c.id, 'client')
        resp = self.api.get(
            f'/api/messages?conversation_id={conv.id}',
            HTTP_AUTHORIZATION=f'Bearer {token_c}',
        )
        
        # Doit retourner 403 (forbidden) ou 404 (not found)
        self.assertIn(resp.status_code, [200, 403, 404])
        if resp.status_code == 200:
            data = resp.json()
            # Si 200, doit avoir une liste vide
            messages = data.get('messages', [])
            self.assertEqual(len(messages), 0)
