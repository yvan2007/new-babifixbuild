"""Tests unitaires Smart V2 : KYC ONECI/MRZ + Vision Pillow, Pre-inscription Express,
Devis adaptatif 1-clic, Quota 5, Anti-exorbitant, Sequestre plafond non-bloquant,
Passage Niveau 2 au merite, Caution GeniusPay, Coupure appel bidirectionnelle et STT audio.
"""

import base64
from datetime import date, timedelta
import io
import json
from unittest.mock import patch

from django.contrib.auth.models import User
from django.test import Client as DjangoClient
from django.test import TestCase
from django.utils import timezone
from PIL import Image, ImageDraw

from adminpanel.auth import create_token
from adminpanel.kyc_engine import (
    mrz_check_digit,
    parse_and_validate_mrz_td1,
)
from adminpanel.models import (
    Call,
    Category,
    Conversation,
    Devis,
    Message,
    PlatformConfig,
    PlatformRevenue,
    Provider,
    Reservation,
    UserProfile,
)
from adminpanel.services.intelligence_service import (
    check_and_apply_merit_upgrade,
    get_merit_progress,
)


def _distinct_jpeg_b64(seed: int, size=(720, 460)) -> str:
    img = Image.new(
        "RGB",
        size,
        ((seed * 47) % 160 + 50, (seed * 83) % 160 + 50, (seed * 29) % 160 + 50),
    )
    draw = ImageDraw.Draw(img)
    for i in range(18):
        x0 = (i * 39 + seed * 17) % (size[0] - 90)
        y0 = (i * 29 + seed * 23) % (size[1] - 70)
        col = ((i * 59 + seed * 13) % 210 + 25, (i * 31 + seed * 7) % 200 + 30, 120)
        draw.rectangle([x0, y0, x0 + 68, y0 + 48], fill=col)
        draw.line([x0, y0, x0 + 68, y0 + 48], fill=(20, 20, 20), width=2)
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=88)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode("ascii")


def _build_valid_civ_td1_mrz(
    doc_num: str = "C01234567",
    birth: str = "920514",
    expiry: str = "321231",
    surname: str = "KOUAME",
    given: str = "JEAN<PAUL",
) -> str:
    doc9 = doc_num.upper().ljust(9, "<")[:9]
    doc_cd = mrz_check_digit(doc9)
    l1 = f"IDCIV{doc9}{doc_cd}" + "<" * 15
    b_cd = mrz_check_digit(birth)
    e_cd = mrz_check_digit(expiry)
    opt2 = "<" * 11
    comp_in = l1[5:30] + birth + b_cd + expiry + e_cd + opt2
    comp_cd = mrz_check_digit(comp_in)
    l2 = f"{birth}{b_cd}M{expiry}{e_cd}CIV{opt2}{comp_cd}"
    l3 = f"{surname}<<{given}".ljust(30, "<")[:30]
    return f"{l1}\n{l2}\n{l3}"


class SmartV2FeaturesTests(TestCase):
    def setUp(self):
        self.http = DjangoClient()
        cfg = PlatformConfig.get_solo()
        cfg.standard_max_devis = 5
        cfg.save(update_fields=["standard_max_devis"])

        self.cat_plomb = Category.objects.create(
            nom="Plomberie",
            icone_slug="tuyau",
            groupe="Maison & Depannage",
            regime_kyc=Category.RegimeKyc.STANDARD_TERRAIN,
            profil_devis=Category.ProfilDevis.DIAGNOSTIC,
        )
        self.cat_nounou = Category.objects.create(
            nom="Nounou & Garde d'enfants",
            icone_slug="nounou",
            groupe="Famille & Soins",
            regime_kyc=Category.RegimeKyc.SENSIBLE_CASIER,
            profil_devis=Category.ProfilDevis.FORFAIT,
        )

        # Client
        self.u_client = User.objects.create_user(
            "client_v2", password="Pwd12345!", email="c_v2@babifix.ci"
        )
        UserProfile.objects.create(
            user=self.u_client,
            role="client",
            active=True,
            phone_e164="+2250701112233",
        )
        self.tok_client = create_token(self.u_client.id, "client")

        # Outsider user (for auth checks)
        self.u_other = User.objects.create_user(
            "outsider_v2", password="Pwd12345!", email="out_v2@babifix.ci"
        )
        UserProfile.objects.create(user=self.u_other, role="client", active=True)
        self.tok_other = create_token(self.u_other.id, "client")

        # Validated Provider (Plomberie, Tier 1 = 100 000 FCFA)
        self.u_pro = User.objects.create_user(
            "pro_v2", password="Pwd12345!", email="pro_v2@babifix.ci"
        )
        UserProfile.objects.create(
            user=self.u_pro,
            role="prestataire",
            active=True,
            phone_e164="+2250702223344",
        )
        self.tok_pro = create_token(self.u_pro.id, "prestataire")
        self.p_pro = Provider.objects.create(
            user=self.u_pro,
            nom="Kouame Jean Paul",
            specialite="Plomberie",
            ville="Abidjan - Cocody",
            category=self.cat_plomb,
            statut=Provider.Status.VALID,
            kyc_status="approved",
            disponible=True,
            artisan_tier="palier_1_proximite",
            plafond_intervention_fcfa=100000,
        )

        # Validated Nounou provider
        self.u_nounou = User.objects.create_user(
            "nounou_v2", password="Pwd12345!", email="nn_v2@babifix.ci"
        )
        UserProfile.objects.create(user=self.u_nounou, role="prestataire", active=True)
        self.tok_nounou = create_token(self.u_nounou.id, "prestataire")
        self.p_nounou = Provider.objects.create(
            user=self.u_nounou,
            nom="Awa Traore",
            specialite="Nounou & Garde d'enfants",
            ville="Abidjan - Cocody",
            category=self.cat_nounou,
            statut=Provider.Status.VALID,
            kyc_status="approved",
            disponible=True,
        )

    def _make_reservation(self, ref: str, provider=None, statut="DEVIS_EN_COURS"):
        prov = provider or self.p_pro
        return Reservation.objects.create(
            reference=ref,
            title="Intervention plomberie",
            client_user=self.u_client,
            client="Client Test",
            prestataire_user=prov.user,
            assigned_provider=prov,
            prestataire=prov.nom,
            montant=0,
            statut=statut,
            address_label="Cocody Riviera 2",
        )

    # 1. Smart KYC & ICAO 9303 TD1 MRZ
    def test_mrz_td1_valid_and_tampered_checksum(self):
        mrz_ok = _build_valid_civ_td1_mrz()
        res_ok = parse_and_validate_mrz_td1(
            mrz_ok,
            expected_cni="C01234567",
            expected_expiry=date(2032, 12, 31),
            expected_name="Kouame Jean Paul",
        )
        self.assertTrue(res_ok["provided"])
        self.assertTrue(res_ok["valid"], msg=f"Unexpected MRZ errors: {res_ok['errors']}")
        self.assertEqual(res_ok["issuing_country"], "CIV")
        self.assertEqual(res_ok["doc_number"], "C01234567")

        # Tamper a single character in doc number without updating check digit
        tampered = mrz_ok.replace("C01234567", "C01234568")
        res_bad = parse_and_validate_mrz_td1(tampered)
        self.assertFalse(res_bad["valid"])
        self.assertTrue(any("ligne 1" in e for e in res_bad["errors"]))

    def test_kyc_submit_rejects_duplicate_images_and_duplicate_cni_accepts_valid(self):
        # Create a fresh pending provider for KYC submission
        u1 = User.objects.create_user("kyc_u1", password="Pwd12345!", email="k1@babifix.ci")
        UserProfile.objects.create(user=u1, role="prestataire", active=True)
        tok1 = create_token(u1.id, "prestataire")
        Provider.objects.create(
            user=u1,
            nom="Kouame Jean Paul",
            specialite="Plomberie",
            ville="Cocody",
            category=self.cat_plomb,
            statut=Provider.Status.PENDING,
        )

        # (a) Identical recto & verso -> 400 kyc_auto_rejected
        dup_img = _distinct_jpeg_b64(101)
        r_dup = self.http.post(
            "/api/prestataire/kyc/submit/",
            data=json.dumps({
                "artisan_tier": "palier_1_proximite",
                "commune_rattachement": "Cocody",
                "cni_number": "C01234567",
                "cni_expiry": "2032-12-31",
                "cni_recto_b64": dup_img,
                "cni_verso_b64": dup_img,
                "selfie_b64": _distinct_jpeg_b64(102, size=(520, 640)),
            }),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {tok1}",
        )
        self.assertEqual(r_dup.status_code, 400)
        self.assertEqual(r_dup.json().get("error"), "kyc_auto_rejected")

        # (b) Distinct realistic images + valid MRZ -> 200 with real score
        r_ok = self.http.post(
            "/api/prestataire/kyc/submit/",
            data=json.dumps({
                "artisan_tier": "palier_1_proximite",
                "commune_rattachement": "Cocody",
                "cni_number": "C01234567",
                "cni_mrz": _build_valid_civ_td1_mrz(),
                "cni_expiry": "2032-12-31",
                "cni_recto_b64": _distinct_jpeg_b64(201),
                "cni_verso_b64": _distinct_jpeg_b64(202),
                "selfie_b64": _distinct_jpeg_b64(203, size=(520, 640)),
            }),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {tok1}",
        )
        self.assertEqual(r_ok.status_code, 200, msg=r_ok.content.decode())
        data_ok = r_ok.json()
        self.assertGreaterEqual(data_ok.get("auto_check_score", 0), 50)

        # (c) Second account trying to reuse the exact same CNI number -> 400 kyc_auto_rejected
        u2 = User.objects.create_user("kyc_u2", password="Pwd12345!", email="k2@babifix.ci")
        UserProfile.objects.create(user=u2, role="prestataire", active=True)
        tok2 = create_token(u2.id, "prestataire")
        Provider.objects.create(
            user=u2,
            nom="Autre Artisan",
            specialite="Plomberie",
            ville="Marcory",
            category=self.cat_plomb,
            statut=Provider.Status.PENDING,
        )
        r_reuse = self.http.post(
            "/api/prestataire/kyc/submit/",
            data=json.dumps({
                "artisan_tier": "palier_1_proximite",
                "commune_rattachement": "Marcory",
                "cni_number": "C01234567",
                "cni_expiry": "2032-12-31",
                "cni_recto_b64": _distinct_jpeg_b64(301),
                "cni_verso_b64": _distinct_jpeg_b64(302),
                "selfie_b64": _distinct_jpeg_b64(303, size=(520, 640)),
            }),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {tok2}",
        )
        self.assertEqual(r_reuse.status_code, 400)
        self.assertEqual(r_reuse.json().get("error"), "kyc_auto_rejected")

    # 2. Express 60s Pre-Registration + strict server-side operational gate
    def test_express_preregistration_and_strict_kyc_gate(self):
        u_exp = User.objects.create_user("exp_u", password="Pwd12345!", email="exp@babifix.ci")
        UserProfile.objects.create(user=u_exp, role="prestataire", active=True)
        tok_exp = create_token(u_exp.id, "prestataire")

        r_reg = self.http.post(
            "/api/prestataire/register",
            data=json.dumps({
                "mode": "express",
                "nom": "Bamba Youssouf",
                "category_id": self.cat_plomb.id,
                "ville": "Cocody",
                "phone_e164": "+2250703334455",
                "email": "exp@babifix.ci",
            }),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {tok_exp}",
        )
        self.assertEqual(r_reg.status_code, 201, msg=r_reg.content.decode())
        body = r_reg.json()
        self.assertTrue(body.get("ok"))
        self.assertTrue(body.get("pre_registered"))

        prov_exp = Provider.objects.get(user=u_exp)
        res_exp = self._make_reservation("RES-EXP-01", provider=prov_exp, statut=Reservation.Status.DEMANDE_ENVOYEE)

        # Cannot accept, request visit, or create devis until KYC approved
        r_acc = self.http.post(
            f"/api/prestataire/requests/{res_exp.reference}/accept",
            HTTP_AUTHORIZATION=f"Bearer {tok_exp}",
        )
        self.assertEqual(r_acc.status_code, 403)
        self.assertEqual(r_acc.json().get("error"), "kyc_required_to_operate")

        r_vis = self.http.post(
            f"/api/prestataire/requests/{res_exp.reference}/request-visit",
            data=json.dumps({"caution_montant": 1500}),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {tok_exp}",
        )
        self.assertEqual(r_vis.status_code, 403)
        self.assertEqual(r_vis.json().get("error"), "kyc_required_to_operate")

        r_dev = self.http.post(
            f"/api/prestataire/requests/{res_exp.reference}/devis",
            data=json.dumps({
                "diagnostic": "Fuite evier",
                "lignes": [{"type_ligne": "MAIN_OEUVRE", "description": "Reparation", "quantite": 1, "prix_unitaire": 10000}],
            }),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {tok_exp}",
        )
        self.assertEqual(r_dev.status_code, 403)
        self.assertEqual(r_dev.json().get("error"), "kyc_required_to_operate")

    # 3. Adaptive Devis UI profile & 1-click quick templates for Nounou
    def test_adaptive_devis_assist_nounou_profile(self):
        r = self.http.get(
            f"/api/prestataire/smart/devis-assist/?category_id={self.cat_nounou.id}",
            HTTP_AUTHORIZATION=f"Bearer {self.tok_nounou}",
        )
        self.assertEqual(r.status_code, 200)
        d = r.json()
        prof = d.get("devis_ui_profile") or {}
        self.assertEqual(prof.get("mode"), "SERVICE_PERSONNE")
        self.assertFalse(prof.get("show_fournitures"))
        self.assertTrue(len(d.get("quick_templates") or []) >= 2)

    # 4. Standard active quote quota = 5
    def test_standard_active_devis_quota_is_five(self):
        for i in range(1, 6):
            res = self._make_reservation(f"RES-Q-{i}")
            r = self.http.post(
                f"/api/prestataire/requests/{res.reference}/devis",
                data=json.dumps({
                    "diagnostic": f"Reparation fuite #{i}",
                    "lignes": [
                        {"type_ligne": "MAIN_OEUVRE", "description": "Intervention", "quantite": 1, "prix_unitaire": 12000}
                    ],
                }),
                content_type="application/json",
                HTTP_AUTHORIZATION=f"Bearer {self.tok_pro}",
            )
            self.assertEqual(r.status_code, 200, msg=f"Devis #{i} failed: {r.content.decode()}")

        # 6th active quote blocked
        res6 = self._make_reservation("RES-Q-6")
        r6 = self.http.post(
            f"/api/prestataire/requests/{res6.reference}/devis",
            data=json.dumps({
                "diagnostic": "Reparation fuite #6",
                "lignes": [
                    {"type_ligne": "MAIN_OEUVRE", "description": "Intervention", "quantite": 1, "prix_unitaire": 12000}
                ],
            }),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {self.tok_pro}",
        )
        self.assertEqual(r6.status_code, 403)
        self.assertEqual(r6.json().get("error"), "devis_quota_reached")

    # 5 & 6. Anti-exorbitant breakdown rule + Non-blocking ceiling escrow
    def test_anti_exorbitant_breakdown_and_non_blocking_ceiling_escrow(self):
        res = self._make_reservation("RES-CEIL-01")
        # High single lump sum without note -> 400 detail_required_high_amount
        r_single = self.http.post(
            f"/api/prestataire/requests/{res.reference}/devis",
            data=json.dumps({
                "diagnostic": "Travaux importants",
                "lignes": [
                    {"type_ligne": "MAIN_OEUVRE", "description": "Forfait global", "quantite": 1, "prix_unitaire": 150000}
                ],
            }),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {self.tok_pro}",
        )
        self.assertEqual(r_single.status_code, 400)
        self.assertEqual(r_single.json().get("error"), "detail_required_high_amount")

        # Properly itemized > 100 000 FCFA (above Tier 1 ceiling) -> 200 NOT blocked + Mobile Money escrow enforced!
        r_ok = self.http.post(
            f"/api/prestataire/requests/{res.reference}/devis",
            data=json.dumps({
                "diagnostic": "Remplacement complet colonne montante + chauffe-eau",
                "note_prestataire": "Garantie 6 mois pieces et main d'oeuvre incluse.",
                "lignes": [
                    {"type_ligne": "FOURNITURE", "description": "Chauffe-eau 100L + raccords", "quantite": 1, "prix_unitaire": 95000},
                    {"type_ligne": "MAIN_OEUVRE", "description": "Depose et pose complete", "quantite": 1, "prix_unitaire": 45000},
                ],
            }),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {self.tok_pro}",
        )
        self.assertEqual(r_ok.status_code, 200, msg=r_ok.content.decode())
        body = r_ok.json()
        self.assertTrue(body.get("above_ceiling_escrow_enforced"))
        res.refresh_from_db()
        self.assertEqual(res.payment_type, "MOBILE_MONEY")

        # Client reading devis sees price_vigilance & above_ceiling_escrow_enforced
        r_get = self.http.get(
            f"/api/client/reservations/{res.reference}/devis",
            HTTP_AUTHORIZATION=f"Bearer {self.tok_client}",
        )
        self.assertEqual(r_get.status_code, 200)
        devis_payload = r_get.json().get("devis") or {}
        self.assertTrue(devis_payload.get("above_ceiling_escrow_enforced"))
        self.assertTrue((devis_payload.get("price_vigilance") or {}).get("is_high"))

    # 7. Automatic Merit Tier 2 upgrade
    def test_automatic_merit_upgrade_to_tier_2(self):
        self.p_pro.average_rating = 4.8
        self.p_pro.rating_count = 10
        self.p_pro.save(update_fields=["average_rating", "rating_count"])
        for i in range(10):
            self._make_reservation(f"RES-MERIT-{i}", statut=Reservation.Status.DONE)
        prog = get_merit_progress(self.p_pro)
        self.assertTrue(prog["eligible_for_tier2"], msg=f"Merit prog: {prog}")
        upgraded = check_and_apply_merit_upgrade(self.p_pro)
        self.assertTrue(upgraded)
        self.p_pro.refresh_from_db()
        self.assertEqual(self.p_pro.artisan_tier, "palier_2_maitre")
        self.assertEqual(self.p_pro.plafond_intervention_fcfa, 500000)

    # 8. GeniusPay kind="caution" server-side calculation & unlocking
    @patch("adminpanel.geniuspay.GENIUSPAY_SANDBOX", True)
    def test_geniuspay_caution_payment_unlocks_visit(self):
        res = self._make_reservation("RES-CAUT-01", statut=Reservation.Status.VISITE_DIAGNOSTIC)
        res.caution_montant = 2000
        res.frais_mise_en_relation_fcfa = 500
        res.address_is_approximate = True
        res.save()

        r = self.http.post(
            "/api/paiements/geniuspay/initiate/",
            data=json.dumps({
                "reservation": res.reference,
                "kind": "caution",
                "payment_method": "WAVE",
                "phone": "0701112233",
                # Malicious client-supplied amount must be ignored!
                "amount": 1,
            }),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {self.tok_client}",
        )
        self.assertEqual(r.status_code, 200, msg=r.content.decode())
        body = r.json()
        self.assertEqual(int(body.get("amount", 0)), 2500)
        res.refresh_from_db()
        self.assertTrue(res.caution_payee)
        self.assertFalse(res.address_is_approximate)
        self.assertEqual(res.statut, Reservation.Status.DEVIS_EN_COURS)
        self.assertTrue(PlatformRevenue.objects.filter(reference=res.reference).exists())

    # 9. Bidirectional call hangup + public config calls_enabled
    @patch("adminpanel.views_calls._broadcast_call_signal")
    @patch("adminpanel.views_calls.delete_room_best_effort")
    def test_bidirectional_call_end_and_public_config(self, _mock_del, mock_ws):
        res = self._make_reservation("RES-CALL-01", statut=Reservation.Status.DEVIS_ACCEPTE)
        call = Call.objects.create(
            reservation=res,
            caller=self.u_pro,
            callee=self.u_client,
            room_name="babifix-res-call-01",
            status="ANSWERED",
            answered_at=timezone.now() - timedelta(seconds=12),
        )
        r_end = self.http.post(
            f"/api/calls/{call.id}/end",
            HTTP_AUTHORIZATION=f"Bearer {self.tok_pro}",
        )
        self.assertEqual(r_end.status_code, 200)
        call.refresh_from_db()
        self.assertEqual(call.status, "ENDED")
        self.assertGreaterEqual(call.duration_seconds, 10)
        # Verify WS broadcast fired for BOTH caller and callee
        self.assertTrue(mock_ws.called)
        args, _kwargs = mock_ws.call_args
        self.assertEqual(args[1], "call.ended")

        r_cfg = self.http.get("/api/public/config/")
        self.assertEqual(r_cfg.status_code, 200)
        apps_cfg = r_cfg.json().get("apps") or {}
        self.assertIn("calls_enabled", apps_cfg)
        self.assertIn("audio_transcription_enabled", apps_cfg)

    # 10. Audio transcription endpoint authorization & graceful fallback
    def test_audio_transcribe_auth_and_graceful_fallback(self):
        res = self._make_reservation("RES-AUD-01")
        conv = Conversation.objects.create(
            client=self.u_client,
            prestataire=self.u_pro,
            reservation=res,
        )
        msg = Message.objects.create(
            conversation=conv,
            sender=self.u_client,
            body="",
            audio="babifix_chat_audio/sample.m4a",
            audio_duration=8,
        )
        # Outsider must get 403
        r_out = self.http.post(
            "/api/audio/transcribe/",
            data=json.dumps({"message_id": msg.id}),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {self.tok_other}",
        )
        self.assertEqual(r_out.status_code, 403)

        # Participant with no STT key gets graceful response (no 500 crash)
        with patch.dict("os.environ", {"GROQ_API_KEY": "", "OPENAI_API_KEY": "", "GEMINI_API_KEY": ""}, clear=False):
            r_part = self.http.post(
                "/api/audio/transcribe/",
                data=json.dumps({"message_id": msg.id}),
                content_type="application/json",
                HTTP_AUTHORIZATION=f"Bearer {self.tok_pro}",
            )
            self.assertIn(r_part.status_code, (200, 503))
            self.assertIn("detail", r_part.json())
