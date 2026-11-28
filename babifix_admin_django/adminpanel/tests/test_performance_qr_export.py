"""Tests de verification pour les optimisations perf/ASGI, export sante, QR Wallet et KYC 60s."""

from __future__ import annotations

import json
import os
from unittest.mock import MagicMock, patch

from django.contrib.auth.models import User
from django.test import Client as DjangoClient, TestCase, override_settings

from adminpanel.auth import create_token
from adminpanel.models import Category, Notification, Provider, Reservation, SystemEventLog, UserProfile
from adminpanel.views_verify import build_wallet_qr_url, sign_wallet_qr_code


class PerformanceQrExportAndKycTests(TestCase):
    def setUp(self):
        self.http = DjangoClient()
        self.admin = User.objects.create_superuser("admin_perf", "admin_perf@babifix.ci", "Pwd12345!")
        self.cat = Category.objects.create(nom="Electricite", icone_slug="electricite")

    def test_asgi_app_imports_concurrent_wrapper(self):
        from config import asgi

        self.assertTrue(hasattr(asgi, "ConcurrentWsgiToAsgi"))
        self.assertIsNotNone(asgi.application)

    def test_partial_section_and_sidebar_counts_admin(self):
        self.http.force_login(self.admin)
        for sec in ("dashboard", "observability", "prestataires"):
            r = self.http.get(f"/?section={sec}&partial=section")
            self.assertEqual(r.status_code, 200, msg=sec)
            self.assertContains(r, "bx-partial-meta-json")
        rc = self.http.get("/api/admin/sidebar-counts/")
        self.assertEqual(rc.status_code, 200)
        self.assertTrue(rc.json().get("ok"))
        self.assertIn("pending_providers", rc.json().get("counts", {}))

    def test_observability_export_json_and_csv(self):
        SystemEventLog.objects.create(
            source="backend",
            level="slow",
            endpoint="/api/public/providers/",
            method="GET",
            status_code=200,
            duration_ms=1250.0,
            message="=HYPERLINK(\"http://evil\") Latence test",
        )
        # Non-connecte bloque
        self.assertIn(self.http.get("/api/admin/observability/export/").status_code, (302, 403))

        self.http.force_login(self.admin)
        rj = self.http.get("/api/admin/observability/export/?format=json")
        self.assertEqual(rj.status_code, 200)
        data = json.loads(rj.content.decode("utf-8"))
        self.assertIn("summary_24h", data)
        self.assertIn("top_slow_endpoints", data)
        self.assertEqual(len(data["events"]), 1)

        rc = self.http.get("/api/admin/observability/export/?format=csv")
        self.assertEqual(rc.status_code, 200)
        csv_txt = rc.content.decode("utf-8")
        # Anti-injection formule Excel (= precede d'une apostrophe)
        self.assertIn("'=HYPERLINK", csv_txt)

    def test_wallet_qr_verification_signed_and_no_pii(self):
        u_pro = User.objects.create_user("pro_qr", email="secret_pro@babifix.ci", password="x")
        UserProfile.objects.create(user=u_pro, role="prestataire", phone_e164="+2250709998877", active=True)
        prov = Provider.objects.create(
            user=u_pro,
            nom="Kouassi Jean",
            specialite="Electricite",
            category=self.cat,
            ville="Cocody",
            statut=Provider.Status.VALID,
            kyc_status="approved",
            cni_recto_url="/media/kyc/secret_cni.jpg",
            kyc_cni_number="CI-SECRET-9988",
        )
        code = sign_wallet_qr_code("pro", prov.pk)
        r_ok = self.http.get(f"/verify/pro/{code}/")
        self.assertEqual(r_ok.status_code, 200)
        html = r_ok.content.decode("utf-8")
        self.assertIn("Kouassi J.", html)
        self.assertNotIn("0709998877", html)
        self.assertNotIn("CI-SECRET-9988", html)
        self.assertNotIn("secret_pro@babifix.ci", html)

        # Signature falsifiee rejetee
        r_bad = self.http.get(f"/verify/pro/{prov.pk}-0000000000/")
        self.assertEqual(r_bad.status_code, 404)

        # Demo vitrine valide
        r_demo = self.http.get("/verify/demo/gold/")
        self.assertEqual(r_demo.status_code, 200)
        self.assertIn("CARTE OFFICIELLE", r_demo.content.decode("utf-8"))

        # URL generee sur fidelite & wallet
        u_cli = User.objects.create_user("cli_qr", password="x")
        UserProfile.objects.create(user=u_cli, role="client", active=True)
        tok_cli = create_token(u_cli.id, "client")
        tok_pro = create_token(u_pro.id, "prestataire")
        rf = self.http.get("/api/client/fidelite/", HTTP_AUTHORIZATION=f"Bearer {tok_cli}")
        self.assertEqual(rf.status_code, 200)
        self.assertIn("/verify/client/", rf.json().get("verify_qr_url", ""))
        rw = self.http.get("/api/prestataire/wallet/", HTTP_AUTHORIZATION=f"Bearer {tok_pro}")
        self.assertEqual(rw.status_code, 200)
        self.assertIn("/verify/pro/", rw.json().get("verify_qr_url", ""))

    def test_express_60s_provider_cannot_be_validated_without_kyc_by_mistake(self):
        u = User.objects.create_user("exp60_u", password="x")
        UserProfile.objects.create(user=u, role="prestataire", active=True)
        prov = Provider.objects.create(
            user=u,
            nom="Express Artisan",
            specialite="Plomberie",
            ville="Abidjan",
            statut=Provider.Status.PENDING,
            kyc_status="not_submitted",
        )
        self.http.force_login(self.admin)
        self.http.post(
            "/",
            data={"action": "provider_status", "provider_id": str(prov.pk), "next_status": "Valide"},
        )
        prov.refresh_from_db()
        self.assertEqual(prov.statut, Provider.Status.PENDING)
        self.assertEqual(prov.kyc_status, "not_submitted")
        self.assertTrue(Notification.objects.filter(user=u, reference=f"KYC-REQ-{prov.pk}").exists())

        # Une fois les pieces fournies, la validation passe aussi kyc_status a approved
        prov.cni_recto_url = "/media/kyc/cni.jpg"
        prov.kyc_status = "pending"
        prov.save(update_fields=["cni_recto_url", "kyc_status"])
        self.http.post(
            "/",
            data={"action": "provider_status", "provider_id": str(prov.pk), "next_status": "Valide"},
        )
        prov.refresh_from_db()
        self.assertEqual(prov.statut, Provider.Status.VALID)
        self.assertEqual(prov.kyc_status, "approved")

    @override_settings(GOOGLE_CLIENT_ID="test-web-id.apps.googleusercontent.com")
    @patch("urllib.request.urlopen")
    def test_google_auth_pro_creates_provider_and_blocks_cross_role(self, mock_urlopen):
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps({
            "aud": "test-web-id.apps.googleusercontent.com",
            "email": "newpro@babifix.ci",
            "email_verified": "true",
            "name": "Artisan Google",
        }).encode("utf-8")
        mock_urlopen.return_value.__enter__ = MagicMock(return_value=mock_resp)
        mock_urlopen.return_value.__exit__ = MagicMock(return_value=False)

        r_pro = self.http.post(
            "/api/auth/google/",
            data=json.dumps({"id_token": "tok", "role": "prestataire"}),
            content_type="application/json",
        )
        self.assertEqual(r_pro.status_code, 200)
        self.assertEqual(r_pro.json().get("role"), "prestataire")
        self.assertTrue(Provider.objects.filter(user__email="newpro@babifix.ci").exists())

        # Connexion du meme compte Google comme client -> rejet 403 wrong_app_role
        r_cross = self.http.post(
            "/api/auth/google/",
            data=json.dumps({"id_token": "tok", "role": "client"}),
            content_type="application/json",
        )
        self.assertEqual(r_cross.status_code, 403)
        self.assertEqual(r_cross.json().get("error"), "wrong_app_role")

    def test_fcm_status_reads_json_env(self):
        from adminpanel.fcm_backend import _load_firebase_json_env

        with patch.dict(os.environ, {"FIREBASE_CREDENTIALS_JSON": '{"project_id":"babifix-b6454","private_key":"k"}'}):
            parsed = _load_firebase_json_env()
            self.assertIsNotNone(parsed)
            self.assertEqual(parsed.get("project_id"), "babifix-b6454")

    def test_e2e_media_audio_video_cash_and_mobile_money_workflows(self):
        u_cli = User.objects.create_user("cli_media_e2e", password="x")
        UserProfile.objects.create(user=u_cli, role="client", active=True)
        u_pro = User.objects.create_user("pro_media_e2e", password="x")
        UserProfile.objects.create(user=u_pro, role="prestataire", active=True)
        prov = Provider.objects.create(
            user=u_pro,
            nom="Pro Media E2E",
            specialite="Plomberie",
            category=self.cat,
            ville="Cocody",
            statut=Provider.Status.VALID,
            kyc_status="approved",
        )
        tok_cli = create_token(u_cli.id, "client")
        tok_pro = create_token(u_pro.id, "prestataire")

        # 1. Creation reservation Especes avec photo, audio, video et date planifiee
        res_cash = self.http.post(
            "/api/client/reservations",
            data=json.dumps({
                "provider_id": prov.id,
                "title": "Fuite canalisation cuisine",
                "price_fcfa": 20000,
                "payment_type": "ESPECES",
                "address_label": "Cocody Riviera 2",
                "latitude": 5.348,
                "longitude": -3.987,
                "scheduled_date": "2026-12-05",
                "demande_type": "DEVIS",
                "audio_probleme": "/media/uploads/voice_note.m4a",
                "video_probleme": "/media/uploads/leak_video.mp4",
                "photo_attachments": ["/media/uploads/photo_1.jpg"],
            }),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {tok_cli}",
        )
        self.assertEqual(res_cash.status_code, 201)
        ref_cash = res_cash.json().get("reference")
        self.assertTrue(ref_cash)

        # Le prestataire retrouve audio, video, photos et date planifiee
        req_list = self.http.get(
            "/api/prestataire/requests/",
            HTTP_AUTHORIZATION=f"Bearer {tok_pro}",
        )
        self.assertEqual(req_list.status_code, 200)
        items = req_list.json().get("items", [])
        match = next((x for x in items if x.get("reference") == ref_cash), None)
        self.assertIsNotNone(match)
        self.assertEqual(match.get("audio_probleme"), "/media/uploads/voice_note.m4a")
        self.assertEqual(match.get("video_probleme"), "/media/uploads/leak_video.mp4")

        # Flux Especes : termine + confirme par client -> client declare cash -> pro confirme
        from django.utils import timezone

        obj = Reservation.objects.get(reference=ref_cash)
        obj.statut = Reservation.Status.DONE
        obj.client_confirme_prestation_at = timezone.now()
        obj.save(update_fields=["statut", "client_confirme_prestation_at"])
        dec = self.http.post(
            f"/api/client/reservations/{ref_cash}/cash-declare",
            data="{}",
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {tok_cli}",
        )
        self.assertEqual(dec.status_code, 200)
        self.assertEqual(dec.json().get("cash_flow_status"), Reservation.CashFlowStatus.PENDING_PRESTATAIRE)
        conf = self.http.post(
            f"/api/prestataire/requests/{ref_cash}/cash-confirm",
            data="{}",
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {tok_pro}",
        )
        self.assertEqual(conf.status_code, 200)
        self.assertEqual(conf.json().get("cash_flow_status"), Reservation.CashFlowStatus.VALIDATED)

        # 2. Creation reservation Mobile Money (Wave) avec audio et video
        res_mm = self.http.post(
            "/api/client/reservations",
            data=json.dumps({
                "provider_id": prov.id,
                "title": "Pose chauffe-eau",
                "price_fcfa": 35000,
                "payment_type": "MOBILE_MONEY",
                "mobile_money_operator": "wave",
                "audio_probleme": "/media/uploads/mm_voice.m4a",
                "video_probleme": "/media/uploads/mm_video.mp4",
            }),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {tok_cli}",
        )
        self.assertEqual(res_mm.status_code, 201)

    def test_prestataire_me_kyc_verified_flag(self):
        u_pro = User.objects.create_user("pro_kyc_flag", password="x")
        UserProfile.objects.create(user=u_pro, role="prestataire", active=True)
        prov = Provider.objects.create(
            user=u_pro,
            nom="Pro Express Flag",
            specialite="Peinture",
            category=self.cat,
            ville="Yopougon",
            statut=Provider.Status.PENDING,
            kyc_status="not_submitted",
        )
        tok = create_token(u_pro.id, "prestataire")
        r1 = self.http.get("/api/prestataire/me", HTTP_AUTHORIZATION=f"Bearer {tok}")
        self.assertEqual(r1.status_code, 200)
        p1 = r1.json().get("provider", {})
        self.assertFalse(p1.get("kyc_verified"))
        self.assertTrue(p1.get("pre_registered"))

        prov.statut = Provider.Status.VALID
        prov.kyc_status = "approved"
        prov.save(update_fields=["statut", "kyc_status"])
        r2 = self.http.get("/api/prestataire/me", HTTP_AUTHORIZATION=f"Bearer {tok}")
        self.assertEqual(r2.status_code, 200)
        p2 = r2.json().get("provider", {})
        self.assertTrue(p2.get("kyc_verified"))
        self.assertFalse(p2.get("pre_registered"))
