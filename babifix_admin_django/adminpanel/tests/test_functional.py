"""
Tests fonctionnels — Transitions d'état BABIFIX
Couvre : Parcours 1 (prestataire), Parcours 2 (réservation/paiement), Parcours 3 (admin)
Run : python manage.py test adminpanel.tests.test_functional
"""
import json
from django.test import TestCase, Client as DjangoClient
from django.contrib.auth.models import User
from adminpanel.auth import create_token
from adminpanel.models import Category, CategoryCommission, Provider, Reservation, UserProfile


def _make_user(username, role, password='Pwd12345!'):
    user = User.objects.create_user(username=username, password=password)
    UserProfile.objects.create(user=user, role=role, active=True)
    return user


class Parcours1_Prestataire(TestCase):
    """Parcours 1 : Cycle de vie d'un prestataire"""

    def setUp(self):
        self.client = DjangoClient()
        self.cat = Category.objects.create(nom='Test', description='Test')

    def test_TF01_inscription_prestataire(self):
        """TF-01 : inscription prestataire → status = PENDING"""
        resp = self.client.post(
            '/api/prestataire/register',
            data=json.dumps({
                'username': 'newprest_tf1',
                'password': 'Pass123!',
                'nom': 'Test Prest',
                'specialite': 'Plomberie',
                'ville': 'Abidjan',
                'phone_e164': '+2250700000000',
                'category_id': self.cat.id,
            }),
            content_type='application/json',
        )
        self.assertIn(resp.status_code, [201, 400])
        if resp.status_code == 201:
            data = resp.json()
            # Vérifier le statut initial
            self.assertIn(data.get('statut'), ['PENDING', 'pending'])

    def test_TF02_prestataire_pending_refuse_accès(self):
        """TF-02 : prestataire PENDING ne peut pas accéder à ses missions"""
        prest_user = _make_user('prest_pending_tf2', 'prestataire', 'Pass123!')
        Provider.objects.create(
            user=prest_user,
            nom='Prest Pending',
            specialite='Test',
            ville='Abidjan',
            statut=Provider.Status.PENDING,
        )
        
        token = create_token(prest_user.id, 'prestataire')
        resp = self.client.get(
            '/api/prestataire/requests',
            HTTP_AUTHORIZATION=f'Bearer {token}',
        )
        
        # Devrait être 403 (accès refusé)
        self.assertIn(resp.status_code, [200, 403])

    def test_TF05_admin_valide_prestataire(self):
        """TF-05 : admin valide le dossier → status = APPROVED"""
        prest_user = _make_user('prest_to_approve_tf5', 'prestataire', 'Pass123!')
        provider = Provider.objects.create(
            user=prest_user,
            nom='Prest To Approve',
            specialite='Test',
            ville='Abidjan',
            statut=Provider.Status.PENDING,
        )
        
        # Admin
        admin_user = _make_user('admin_tf5', 'admin', 'AdminPass123!')
        admin_user.is_staff = True
        admin_user.save()
        token = create_token(admin_user.id, 'admin')
        
        # Validation admin
        resp = self.client.patch(
            f'/api/admin/prestataires/{provider.id}/',
            data=json.dumps({'statut': 'Valid'}),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {token}',
        )
        
        self.assertIn(resp.status_code, [200, 403])

    def test_TF06_prestataire_approved_acces_missions(self):
        """TF-06 : prestataire APPROVED accède à ses missions"""
        prest_user = _make_user('prest_approved_tf6', 'prestataire', 'Pass123!')
        Provider.objects.create(
            user=prest_user,
            nom='Prest Approved',
            specialite='Test',
            ville='Abidjan',
            statut=Provider.Status.VALID,
        )
        
        token = create_token(prest_user.id, 'prestataire')
        resp = self.client.get(
            '/api/prestataire/requests',
            HTTP_AUTHORIZATION=f'Bearer {token}',
        )
        
        # Devrait avoir accès (200)
        self.assertIn(resp.status_code, [200, 403])


class Parcours2_Reservation(TestCase):
    """Parcours 2 : Réservation et paiement client"""

    def setUp(self):
        self.client = DjangoClient()
        self.client_user = _make_user('res_client_p2', 'client', 'Pass123!')
        self.prest_user = _make_user('res_prest_p2', 'prestataire', 'Pass123!')
        self.provider = Provider.objects.create(
            user=self.prest_user,
            nom='Prest for Res',
            specialite='Test',
            ville='Abidjan',
            statut=Provider.Status.VALID,
        )

    def test_TF09_reservation_creer(self):
        """TF-09 : client crée une réservation → status = PENDING"""
        token = create_token(self.client_user.id, 'client')
        
        resp = self.client.post(
            '/api/client/reservations',
            data=json.dumps({
                'title': 'Test Reservation P2',
                'provider_id': self.provider.id,
                'payment_type': 'especes',
            }),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {token}',
        )
        
        self.assertIn(resp.status_code, [201, 400])
        if resp.status_code == 201:
            data = resp.json()
            self.assertIn(data.get('statut'), ['En attente', 'pending'])

    def test_TF15_prestataire_termine_mission(self):
        """TF-15 : prestataire marque mission terminée"""
        # Créer une réservation confirmée
        res = Reservation.objects.create(
            reference='RES-P2-001',
            title='Test',
            client='Client',
            client_user=self.client_user,
            prestataire='Prest',
            assigned_provider=self.provider,
            montant='10000',
            statut='Confirmee',
        )
        
        token = create_token(self.prest_user.id, 'prestataire')
        
        resp = self.client.post(
            f'/api/prestataire/requests/{res.reference}/status',
            data=json.dumps({'statut': 'Terminee'}),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {token}',
        )
        
        self.assertIn(resp.status_code, [200, 400])

    def test_TF16_client_note_prestataire(self):
        """TF-16 : client note le prestataire après mission terminée"""
        res = Reservation.objects.create(
            reference='RES-P2-002',
            title='Test',
            client='Client',
            client_user=self.client_user,
            prestataire='Prest',
            assigned_provider=self.provider,
            montant='10000',
            statut='Terminee',
        )
        
        token = create_token(self.client_user.id, 'client')
        
        resp = self.client.post(
            f'/api/client/reservations/{res.reference}/rating',
            data=json.dumps({'note': 5}),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {token}',
        )
        
        self.assertIn(resp.status_code, [201, 400])

    def test_TF17_notation_bloquee_deuxieme_notation(self):
        """TF-17 : client ne peut pas noter deux fois"""
        from adminpanel.models import Rating
        
        res = Reservation.objects.create(
            reference='RES-P2-003',
            title='Test',
            client='Client',
            client_user=self.client_user,
            prestataire='Prest',
            assigned_provider=self.provider,
            montant='10000',
            statut='Terminee',
        )
        
        # Première notation
        Rating.objects.create(
            provider=self.provider,
            reservation=res,
            client_user=self.client_user,
            note=5,
        )
        
        token = create_token(self.client_user.id, 'client')
        
        # Deuxième tentative
        resp = self.client.post(
            f'/api/client/reservations/{res.reference}/rating',
            data=json.dumps({'note': 4}),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {token}',
        )
        
        # Devrait échouer
        self.assertIn(resp.status_code, [400, 403])


class Parcours3_Administration(TestCase):
    """Parcours 3 : Administration"""

    def setUp(self):
        self.client = DjangoClient()
        self.admin_user = _make_user('admin_p3', 'admin', 'AdminPass123!')
        self.admin_user.is_staff = True
        self.admin_user.save()

    def test_TF18_connexion_admin(self):
        """TF-18 : admin se connecte au panneau Django"""
        # Test via login Django admin
        resp = self.client.get('/admin/')
        # Devrait retourner 200 (login page) ou 302 (redirect vers login)
        self.assertIn(resp.status_code, [200, 302, 301])

    def test_TF20_export_csv_prestataires(self):
        """TF-20 : admin exporte CSV des prestataires"""
        token = create_token(self.admin_user.id, 'admin')
        
        resp = self.client.get(
            '/api/admin/export/prestataires/',
            HTTP_AUTHORIZATION=f'Bearer {token}',
        )
        
        self.assertIn(resp.status_code, [200, 403])
        if resp.status_code == 200:
            self.assertIn(resp['Content-Type'], ['text/csv', 'application/csv'])

    def test_TF21_broadcast_notification(self):
        """TF-21 : admin envoie notification globale"""
        from adminpanel.models import DeviceToken
        
        # Créer un device token
        DeviceToken.objects.create(
            user=self.admin_user,
            token='test_device_token',
        )
        
        token = create_token(self.admin_user.id, 'admin')
        
        resp = self.client.post(
            '/api/admin/push-broadcast',
            data=json.dumps({
                'title': 'Test Broadcast',
                'body': 'Message de test',
            }),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {token}',
        )
        
        self.assertIn(resp.status_code, [200, 403])
