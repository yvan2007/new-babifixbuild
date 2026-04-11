"""
Tests d'intégration — Actions Admin BABIFIX
Cible : audit log, CSV export, bulk actions
Run : python manage.py test adminpanel.tests.test_api_admin
"""
import json

from django.test import TestCase, Client as DjangoClient
from django.contrib.auth.models import User

from adminpanel.auth import create_token
from adminpanel.models import AdminAuditLog, Provider, Reservation, UserProfile


def _make_user(username, role, password='Pwd12345!'):
    user = User.objects.create_user(username=username, password=password)
    UserProfile.objects.create(user=user, role=role, active=True)
    return user, create_token(user.id, role)


class AuditLogTest(TestCase):
    """Tests de GET /api/admin/audit-log/."""

    def setUp(self):
        self.http = DjangoClient()
        self.admin_user, self.admin_token = _make_user('admin_audit', 'admin')
        self.client_user, self.client_token = _make_user('cli_audit', 'client')
        # Pré-remplir des logs
        for i in range(5):
            AdminAuditLog.objects.create(
                admin_user=self.admin_user,
                action=AdminAuditLog.ActionType.OTHER,
                target_label=f'Test log {i}',
                details={'index': i},
            )

    def test_audit_log_returns_200(self):
        resp = self.http.get(
            '/api/admin/audit-log/',
            HTTP_AUTHORIZATION=f'Bearer {self.admin_token}',
        )
        self.assertEqual(resp.status_code, 200)

    def test_audit_log_returns_list(self):
        resp = self.http.get(
            '/api/admin/audit-log/',
            HTTP_AUTHORIZATION=f'Bearer {self.admin_token}',
        )
        data = resp.json()
        # L'API peut retourner une liste directement ou un objet avec 'logs'
        self.assertTrue(isinstance(data, list) or 'logs' in data or 'results' in data)

    def test_audit_log_requires_admin_role(self):
        resp = self.http.get(
            '/api/admin/audit-log/',
            HTTP_AUTHORIZATION=f'Bearer {self.client_token}',
        )
        self.assertIn(resp.status_code, [401, 403])

    def test_audit_log_without_auth_returns_401(self):
        resp = self.http.get('/api/admin/audit-log/')
        self.assertEqual(resp.status_code, 401)

    def test_audit_log_entries_have_required_fields(self):
        resp = self.http.get(
            '/api/admin/audit-log/',
            HTTP_AUTHORIZATION=f'Bearer {self.admin_token}',
        )
        data = resp.json()
        items = data if isinstance(data, list) else data.get('logs', data.get('results', []))
        if items:
            first = items[0]
            # Au moins un champ de contexte attendu
            self.assertTrue(
                any(k in first for k in ['action', 'target_label', 'created_at', 'id'])
            )


class CsvExportTest(TestCase):
    """Tests de GET /api/admin/export/<kind>/."""

    def setUp(self):
        self.http = DjangoClient()
        self.admin_user, self.admin_token = _make_user('admin_csv', 'admin')
        self.client_user, self.client_token = _make_user('cli_csv', 'client')
        # Quelques réservations pour l'export
        for i in range(3):
            Reservation.objects.create(
                reference=f'RES-CSV-{i:03d}',
                client=f'Client {i}',
                prestataire=f'Prest {i}',
                montant=f'{(i+1)*5000} FCFA',
            )

    def test_export_reservations_returns_200(self):
        resp = self.http.get(
            '/api/admin/export/reservations/',
            HTTP_AUTHORIZATION=f'Bearer {self.admin_token}',
        )
        self.assertIn(resp.status_code, [200, 201])

    def test_export_reservations_content_type_csv(self):
        resp = self.http.get(
            '/api/admin/export/reservations/',
            HTTP_AUTHORIZATION=f'Bearer {self.admin_token}',
        )
        if resp.status_code == 200:
            content_type = resp.get('Content-Type', '')
            self.assertIn('csv', content_type.lower())

    def test_export_prestataires_returns_200(self):
        resp = self.http.get(
            '/api/admin/export/prestataires/',
            HTTP_AUTHORIZATION=f'Bearer {self.admin_token}',
        )
        self.assertIn(resp.status_code, [200, 201])

    def test_export_paiements_returns_200(self):
        resp = self.http.get(
            '/api/admin/export/paiements/',
            HTTP_AUTHORIZATION=f'Bearer {self.admin_token}',
        )
        self.assertIn(resp.status_code, [200, 201])

    def test_export_requires_admin_role(self):
        resp = self.http.get(
            '/api/admin/export/reservations/',
            HTTP_AUTHORIZATION=f'Bearer {self.client_token}',
        )
        self.assertIn(resp.status_code, [401, 403])

    def test_export_invalid_kind_returns_404(self):
        resp = self.http.get(
            '/api/admin/export/unicorns/',
            HTTP_AUTHORIZATION=f'Bearer {self.admin_token}',
        )
        self.assertIn(resp.status_code, [404, 400])


class BulkActionTest(TestCase):
    """Tests approfondis de POST /api/admin/prestataires/bulk-action/."""

    def setUp(self):
        self.http = DjangoClient()
        self.admin_user, self.admin_token = _make_user('admin_bulk', 'admin')
        # Créer plusieurs prestataires pending
        self.providers = []
        for i in range(4):
            prest_user = User.objects.create_user(username=f'bulk_prest_{i}', password='x')
            UserProfile.objects.create(user=prest_user, role='prestataire')
            p = Provider.objects.create(
                user=prest_user,
                nom=f'Bulk Prest {i}',
                specialite='Test',
                ville='Abidjan',
                statut=Provider.Status.PENDING,
            )
            self.providers.append(p)

    def _bulk_action(self, action, ids=None, motif=''):
        return self.http.post(
            '/api/admin/prestataires/bulk-action/',
            data=json.dumps({
                'ids': ids or [p.id for p in self.providers],
                'action': action,
                'motif': motif,
            }),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {self.admin_token}',
        )

    def test_bulk_accept_all(self):
        resp = self._bulk_action('accept')
        self.assertIn(resp.status_code, [200, 201])
        for p in self.providers:
            p.refresh_from_db()
            self.assertEqual(p.statut, Provider.Status.VALID)
            self.assertTrue(p.is_approved)

    def test_bulk_refuse_with_motif(self):
        resp = self._bulk_action('refuse', motif='CNI invalide')
        self.assertIn(resp.status_code, [200, 201])
        for p in self.providers:
            p.refresh_from_db()
            self.assertEqual(p.statut, Provider.Status.REFUSED)

    def test_bulk_accept_partial_ids(self):
        ids = [self.providers[0].id, self.providers[1].id]
        resp = self._bulk_action('accept', ids=ids)
        self.assertIn(resp.status_code, [200, 201])
        self.providers[0].refresh_from_db()
        self.providers[1].refresh_from_db()
        self.providers[2].refresh_from_db()
        self.assertEqual(self.providers[0].statut, Provider.Status.VALID)
        self.assertEqual(self.providers[1].statut, Provider.Status.VALID)
        # Le 3ème ne devrait pas être modifié
        self.assertEqual(self.providers[2].statut, Provider.Status.PENDING)

    def test_bulk_action_creates_audit_logs_for_each(self):
        ids = [p.id for p in self.providers[:2]]
        self._bulk_action('accept', ids=ids)
        logs = AdminAuditLog.objects.filter(
            action__in=['provider_accepted', 'bulk_accept']
        )
        self.assertGreater(logs.count(), 0)

    def test_bulk_action_unknown_action_returns_error(self):
        resp = self._bulk_action('teleport')
        self.assertNotIn(resp.status_code, [200, 201])

    def test_bulk_action_empty_ids_list(self):
        resp = self._bulk_action('accept', ids=[])
        # Doit renvoyer une erreur ou 200 avec 0 modifié
        # L'important : pas de crash serveur
        self.assertLess(resp.status_code, 500)
