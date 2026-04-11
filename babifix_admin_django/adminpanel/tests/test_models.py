"""
Tests unitaires — Modèles BABIFIX
Cible : adminpanel/models.py
Run : python manage.py test adminpanel.tests.test_models
"""
import pytest
from django.test import TestCase
from django.contrib.auth.models import User

from adminpanel.models import (
    AdminAuditLog,
    Category,
    Client,
    Conversation,
    Dispute,
    Message,
    Payment,
    Provider,
    Reservation,
)


class ProviderModelTest(TestCase):
    """Tests unitaires du modèle Provider (Prestataire)."""

    def setUp(self):
        self.user = User.objects.create_user(
            username='prest_test', password='Pwd12345!'
        )
        self.category = Category.objects.create(nom='Plomberie', icone_slug='plumber')

    # ── is_approved auto-set ──────────────────────────────────────────────────
    def test_is_approved_false_when_pending(self):
        p = Provider.objects.create(
            user=self.user,
            nom='Koffi Yao',
            specialite='Plomberie',
            ville='Abidjan',
            statut=Provider.Status.PENDING,
        )
        self.assertFalse(p.is_approved)

    def test_is_approved_true_when_valid(self):
        p = Provider.objects.create(
            user=self.user,
            nom='Koffi Yao',
            specialite='Plomberie',
            ville='Abidjan',
            statut=Provider.Status.VALID,
        )
        self.assertTrue(p.is_approved)

    def test_is_approved_toggled_on_save(self):
        p = Provider.objects.create(
            user=self.user,
            nom='Koffi Yao',
            specialite='Plomberie',
            ville='Abidjan',
            statut=Provider.Status.PENDING,
        )
        self.assertFalse(p.is_approved)
        p.statut = Provider.Status.VALID
        p.save()
        p.refresh_from_db()
        self.assertTrue(p.is_approved)

    def test_is_approved_false_when_refused(self):
        p = Provider.objects.create(
            user=self.user,
            nom='Koffi Yao',
            specialite='Plomberie',
            ville='Abidjan',
            statut=Provider.Status.REFUSED,
        )
        self.assertFalse(p.is_approved)

    def test_is_approved_false_when_suspended(self):
        p = Provider.objects.create(
            user=self.user,
            nom='Koffi Yao',
            specialite='Plomberie',
            ville='Abidjan',
            statut=Provider.Status.SUSPENDED,
        )
        self.assertFalse(p.is_approved)

    def test_str_returns_nom(self):
        p = Provider.objects.create(
            nom='Aya Coulibaly',
            specialite='Ménage',
            ville='Bouaké',
        )
        self.assertEqual(str(p), 'Aya Coulibaly')

    def test_default_disponible_true(self):
        p = Provider.objects.create(
            nom='Ibrahim',
            specialite='Électricité',
            ville='Abidjan',
        )
        self.assertTrue(p.disponible)

    def test_category_fk(self):
        p = Provider.objects.create(
            nom='Jean',
            specialite='Plomberie',
            ville='Abidjan',
            category=self.category,
        )
        self.assertEqual(p.category.nom, 'Plomberie')

    def test_update_fields_preserves_is_approved(self):
        """update_fields doit inclure is_approved automatiquement."""
        p = Provider.objects.create(
            user=self.user,
            nom='Test',
            specialite='Test',
            ville='Abidjan',
            statut=Provider.Status.PENDING,
        )
        p.statut = Provider.Status.VALID
        p.save(update_fields=['statut'])
        p.refresh_from_db()
        self.assertTrue(p.is_approved)


class ReservationModelTest(TestCase):
    """Tests unitaires du modèle Reservation."""

    def test_create_minimal_reservation(self):
        r = Reservation.objects.create(
            reference='RES-001',
            client='Aminata',
            prestataire='Koffi',
            montant='25000 FCFA',
        )
        self.assertEqual(r.reference, 'RES-001')
        self.assertEqual(r.statut, Reservation.Status.PENDING)
        self.assertEqual(r.payment_type, Reservation.PaymentType.ESPECES)

    def test_reference_unique(self):
        Reservation.objects.create(
            reference='RES-UNIQUE',
            client='A',
            prestataire='B',
            montant='0',
        )
        from django.db import IntegrityError
        with self.assertRaises(IntegrityError):
            Reservation.objects.create(
                reference='RES-UNIQUE',
                client='C',
                prestataire='D',
                montant='0',
            )

    def test_str_returns_reference(self):
        r = Reservation.objects.create(
            reference='RES-STR',
            client='A',
            prestataire='B',
            montant='1000',
        )
        self.assertEqual(str(r), 'RES-STR')

    def test_cash_flow_status_default_na(self):
        r = Reservation.objects.create(
            reference='RES-CF',
            client='A',
            prestataire='B',
            montant='1000',
        )
        self.assertEqual(r.cash_flow_status, '')

    def test_mobile_money_operator_choices(self):
        r = Reservation.objects.create(
            reference='RES-MM',
            client='A',
            prestataire='B',
            montant='1000',
            payment_type=Reservation.PaymentType.MOBILE_MONEY,
            mobile_money_operator=Reservation.MobileMoneyOperator.ORANGE_MONEY,
        )
        self.assertEqual(r.mobile_money_operator, 'ORANGE_MONEY')


class PaymentModelTest(TestCase):
    def test_create_payment(self):
        p = Payment.objects.create(
            reference='PAY-001',
            client='Aya',
            prestataire='Koffi',
            montant='25000 FCFA',
            commission='2500 FCFA',
            etat=Payment.State.PENDING,
            type_paiement=Payment.TypePaiement.MOBILE_MONEY,
        )
        self.assertEqual(p.etat, 'Pending')
        self.assertEqual(p.type_paiement, 'MOBILE_MONEY')

    def test_payment_state_complete(self):
        p = Payment.objects.create(
            reference='PAY-002',
            client='A',
            prestataire='B',
            montant='0',
            commission='0',
            etat=Payment.State.COMPLETE,
        )
        self.assertEqual(p.etat, 'Complete')


class AdminAuditLogTest(TestCase):
    def setUp(self):
        self.admin_user = User.objects.create_user(
            username='admin_test', password='AdminPwd1!'
        )

    def test_create_audit_log(self):
        log = AdminAuditLog.objects.create(
            admin_user=self.admin_user,
            action=AdminAuditLog.ActionType.PROVIDER_ACCEPTED,
            target_type='Provider',
            target_id=42,
            target_label='Koffi Yao',
            details={'motif': ''},
        )
        self.assertEqual(log.action, 'provider_accepted')
        self.assertEqual(log.target_label, 'Koffi Yao')

    def test_ordering_newest_first(self):
        for i in range(3):
            AdminAuditLog.objects.create(
                admin_user=self.admin_user,
                action=AdminAuditLog.ActionType.OTHER,
                target_label=f'Log {i}',
            )
        logs = list(AdminAuditLog.objects.all())
        self.assertGreater(logs[0].created_at, logs[-1].created_at)

    def test_null_admin_user_on_delete(self):
        """L'audit log survit si l'utilisateur admin est supprimé (SET_NULL)."""
        tmp_user = User.objects.create_user(username='tmp_admin', password='tmp')
        log = AdminAuditLog.objects.create(
            admin_user=tmp_user,
            action=AdminAuditLog.ActionType.OTHER,
        )
        tmp_user.delete()
        log.refresh_from_db()
        self.assertIsNone(log.admin_user)


class ConversationMessageTest(TestCase):
    def setUp(self):
        self.client_user = User.objects.create_user(username='cli', password='x')
        self.prest_user = User.objects.create_user(username='pres', password='x')
        self.reservation = Reservation.objects.create(
            reference='RES-CONV',
            client='cli',
            prestataire='pres',
            montant='0',
        )
        self.conv = Conversation.objects.create(
            client=self.client_user,
            prestataire=self.prest_user,
            reservation=self.reservation,
        )

    def test_message_default_not_read(self):
        msg = Message.objects.create(
            conversation=self.conv,
            sender=self.client_user,
            body='Bonjour !',
        )
        self.assertFalse(msg.lu)

    def test_message_mark_read(self):
        msg = Message.objects.create(
            conversation=self.conv,
            sender=self.client_user,
            body='Test',
        )
        msg.lu = True
        msg.save()
        msg.refresh_from_db()
        self.assertTrue(msg.lu)

    def test_message_not_deleted_by_default(self):
        msg = Message.objects.create(
            conversation=self.conv,
            sender=self.client_user,
            body='Pas supprimé',
        )
        self.assertFalse(msg.deleted)


class CategoryModelTest(TestCase):
    def test_create_category(self):
        cat = Category.objects.create(
            nom='Électricité',
            icone_slug='electricity',
            ordre_affichage=1,
        )
        self.assertEqual(str(cat) if hasattr(cat, '__str__') else cat.nom, cat.nom)
        self.assertTrue(cat.actif)

    def test_category_default_actif_true(self):
        cat = Category.objects.create(nom='Jardinage', icone_slug='garden')
        self.assertTrue(cat.actif)
