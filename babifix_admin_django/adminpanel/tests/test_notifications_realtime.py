"""
Tests du systeme complet de notifications temps reel BABIFIX :
- Persistance DB + routage WS/FCM pour Dispute, Reservation (demande, DEVIS_ENVOYE, DEVIS_ACCEPTE),
  Provider (demande d'inscription), MetierPropose, Message.
- Endpoints Admin (/api/admin/notifications/feed, mark-read, mark-all-read) avec acquittement.
- Endpoints Apps (/api/notifications, /api/notifications/mark-read) et compteur non-lus exact.
"""

from decimal import Decimal
from unittest.mock import patch

from django.contrib.auth.models import User
from django.test import Client as DjangoClient
from django.test import TestCase

from adminpanel.auth import create_token
from adminpanel.models import (
    Dispute,
    MetierPropose,
    Notification,
    Provider,
    Reservation,
    UserProfile,
)


class NotificationsRealtimeFlowTests(TestCase):
    def setUp(self):
        self.staff_user = User.objects.create_user(
            "admin_notif", password="Pwd123!", is_staff=True, is_superuser=True
        )
        self.client_user = User.objects.create_user("client_notif", password="Pwd123!")
        UserProfile.objects.create(user=self.client_user, role=UserProfile.Role.CLIENT)

        self.pro_user = User.objects.create_user("pro_notif", password="Pwd123!")
        UserProfile.objects.create(user=self.pro_user, role=UserProfile.Role.PRESTATAIRE)
        self.prov = Provider.objects.create(
            user=self.pro_user,
            nom="Yao Plombier",
            specialite="Plomberie",
            ville="Cocody",
            statut=Provider.Status.VALID,
        )

        self.staff_http = DjangoClient()
        self.staff_http.force_login(self.staff_user)

        self.client_token = create_token(self.client_user.id, "client")
        self.pro_token = create_token(self.pro_user.id, "prestataire")

    def test_provider_and_metier_create_admin_notifications(self):
        self.assertTrue(
            Notification.objects.filter(
                user__isnull=True,
                notif_type=Notification.NotifType.VALIDATION,
                reference=f"PROV-{self.prov.pk}",
                lu=False,
            ).exists()
        )
        metier = MetierPropose.objects.create(nom="Fibre optique")
        self.assertTrue(
            Notification.objects.filter(
                user__isnull=True,
                reference=f"METIER-{metier.pk}",
                lu=False,
            ).exists()
        )

    def test_reservation_lifecycle_and_devis_recu_notifications(self):
        res = Reservation.objects.create(
            reference="RES-NOTIF-01",
            title="Fuite tuyauterie",
            client="Kouame Client",
            prestataire=self.prov.nom,
            montant=Decimal("15000.00"),
            address_ville="Cocody",
            statut=Reservation.Status.PENDING,
            client_user=self.client_user,
            prestataire_user=self.pro_user,
        )
        # Admin + Prestataire notifies a la creation
        self.assertTrue(
            Notification.objects.filter(
                user__isnull=True,
                notif_type=Notification.NotifType.RESERVATION,
                reference="RES-NOTIF-01",
                lu=False,
            ).exists()
        )
        self.assertTrue(
            Notification.objects.filter(
                user=self.pro_user,
                notif_type=Notification.NotifType.RESERVATION,
                reference="RES-NOTIF-01",
                lu=False,
            ).exists()
        )

        # Devis envoye -> le client recoit "Devis recu"
        res.statut = Reservation.Status.DEVIS_ENVOYE
        res.save(update_fields=["statut"])
        self.assertTrue(
            Notification.objects.filter(
                user=self.client_user,
                notif_type=Notification.NotifType.RESERVATION,
                reference="RES-NOTIF-01",
                title__icontains="Devis recu",
                lu=False,
            ).exists()
        )

        # Devis accepte -> le prestataire recoit "Devis accepte"
        res.statut = Reservation.Status.DEVIS_ACCEPTE
        res.save(update_fields=["statut"])
        self.assertTrue(
            Notification.objects.filter(
                user=self.pro_user,
                notif_type=Notification.NotifType.RESERVATION,
                reference="RES-NOTIF-01",
                title__icontains="Devis accepte",
                lu=False,
            ).exists()
        )

    @patch("adminpanel.realtime.broadcast_prestataire_user")
    @patch("adminpanel.realtime.broadcast_client_user")
    def test_dispute_notifies_admin_client_and_prestataire(self, mock_client_ws, mock_pro_ws):
        res = Reservation.objects.create(
            reference="RES-DISP-01",
            title="Reparation chauffe eau",
            client="Kouame Client",
            prestataire=self.prov.nom,
            montant=Decimal("25000.00"),
            address_ville="Marcory",
            statut=Reservation.Status.IN_PROGRESS,
            client_user=self.client_user,
            prestataire_user=self.pro_user,
        )
        Dispute.objects.create(
            reference="LIT-9001",
            motif="Retard intervention",
            client="Kouame Client",
            prestataire=self.prov.nom,
            reservation=res,
        )
        self.assertTrue(
            Notification.objects.filter(
                user__isnull=True,
                notif_type=Notification.NotifType.DISPUTE,
                reference="LIT-9001",
                lu=False,
            ).exists()
        )
        self.assertTrue(
            Notification.objects.filter(
                user=self.client_user,
                notif_type=Notification.NotifType.DISPUTE,
                reference="LIT-9001",
                lu=False,
            ).exists()
        )
        self.assertTrue(
            Notification.objects.filter(
                user=self.pro_user,
                notif_type=Notification.NotifType.DISPUTE,
                reference="LIT-9001",
                lu=False,
            ).exists()
        )
        self.assertTrue(
            any(call.args[1] == "dispute.created" for call in mock_client_ws.call_args_list)
        )
        self.assertTrue(
            any(call.args[1] == "dispute.created" for call in mock_pro_ws.call_args_list)
        )

    def test_admin_notifications_feed_and_click_to_disappear(self):
        # Non-staff refuse
        anon = DjangoClient()
        self.assertEqual(anon.get("/api/admin/notifications/feed").status_code, 403)

        Notification.objects.filter(user__isnull=True).update(lu=True)
        n_dispute = Notification.objects.create(
            user=None,
            title="Litige urgent test",
            notif_type=Notification.NotifType.DISPUTE,
            reference="LIT-FEED-1",
            lu=False,
        )
        res = self.staff_http.get("/api/admin/notifications/feed")
        self.assertEqual(res.status_code, 200)
        payload = res.json()
        self.assertEqual(payload["unread_count"], 1)
        self.assertEqual(payload["notifications"][0]["id"], n_dispute.id)
        self.assertEqual(payload["notifications"][0]["target_url"], "/?section=litiges")

        # Clic sur la notif -> acquittement individuel + disparition du feed
        mark_res = self.staff_http.post(
            "/api/admin/notifications/mark-read",
            data={"id": n_dispute.id},
            content_type="application/json",
        )
        self.assertEqual(mark_res.status_code, 200)
        self.assertEqual(mark_res.json()["unread_count"], 0)
        self.assertEqual(self.staff_http.get("/api/admin/notifications/feed").json()["unread_count"], 0)

        # Nouvelle notification + Tout marquer lu
        Notification.objects.create(
            user=None,
            title="Autre alerte",
            notif_type=Notification.NotifType.PAYMENT,
            reference="PAY-1",
            lu=False,
        )
        mark_all = self.staff_http.post("/api/admin/notifications/mark-all-read")
        self.assertEqual(mark_all.status_code, 200)
        self.assertEqual(mark_all.json()["unread_count"], 0)

    def test_user_api_notifications_unread_count_and_mark_read(self):
        n1 = Notification.objects.create(
            user=self.client_user,
            title="Devis recu RES-1",
            notif_type=Notification.NotifType.RESERVATION,
            reference="RES-1",
            lu=False,
        )
        n2 = Notification.objects.create(
            user=self.client_user,
            title="Paiement valide",
            notif_type=Notification.NotifType.PAYMENT,
            reference="PAY-2",
            lu=False,
        )
        headers = {"HTTP_AUTHORIZATION": f"Bearer {self.client_token}"}
        http_client = DjangoClient()

        r_list = http_client.get("/api/notifications", **headers)
        self.assertEqual(r_list.status_code, 200)
        self.assertEqual(r_list.json()["unread"], 2)

        r_mark1 = http_client.post(
            "/api/notifications/mark-read",
            data={"ids": [n1.id]},
            content_type="application/json",
            **headers,
        )
        self.assertEqual(r_mark1.status_code, 200)
        self.assertEqual(r_mark1.json()["unread"], 1)

        r_unread_only = http_client.get("/api/notifications?unread_only=1", **headers)
        self.assertEqual(r_unread_only.status_code, 200)
        ids_left = [item["id"] for item in r_unread_only.json()["notifications"]]
        self.assertEqual(ids_left, [n2.id])

    @patch("adminpanel.realtime.broadcast_prestataire_user")
    @patch("adminpanel.realtime.broadcast_client_user")
    def test_targeted_ws_events_route_only_to_intended_recipient(self, mock_client_ws, mock_pro_ws):
        res = Reservation.objects.create(
            reference="RES-TARGET-01",
            title="Panne climatiseur",
            client="Kouame Client",
            prestataire=self.prov.nom,
            montant=Decimal("18000.00"),
            address_ville="Cocody",
            statut=Reservation.Status.DEMANDE_ENVOYEE,
            client_user=self.client_user,
            prestataire_user=self.pro_user,
        )
        pro_events_create = [c.args[1] for c in mock_pro_ws.call_args_list]
        cli_events_create = [c.args[1] for c in mock_client_ws.call_args_list]
        self.assertIn("reservation.created", pro_events_create)
        self.assertNotIn("reservation.created", cli_events_create)
        self.assertNotIn("reservation.updated", cli_events_create)
        self.assertIn("reservations.sync", cli_events_create)

        mock_client_ws.reset_mock()
        mock_pro_ws.reset_mock()
        res.statut = Reservation.Status.DEVIS_ENVOYE
        res.save(update_fields=["statut"])
        cli_events_quote = [c.args[1] for c in mock_client_ws.call_args_list]
        pro_events_quote = [c.args[1] for c in mock_pro_ws.call_args_list]
        self.assertIn("reservation.updated", cli_events_quote)
        self.assertNotIn("reservation.updated", pro_events_quote)
        self.assertIn("reservations.sync", pro_events_quote)

        mock_client_ws.reset_mock()
        mock_pro_ws.reset_mock()
        res.statut = Reservation.Status.DEVIS_ACCEPTE
        res.save(update_fields=["statut"])
        cli_events_acc = [c.args[1] for c in mock_client_ws.call_args_list]
        pro_events_acc = [c.args[1] for c in mock_pro_ws.call_args_list]
        self.assertIn("reservation.updated", pro_events_acc)
        self.assertNotIn("reservation.updated", cli_events_acc)
        self.assertIn("reservations.sync", cli_events_acc)
