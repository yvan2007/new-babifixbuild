"""Tests unitaires pour le regime SENSIBLE_CASIER, Option A (MetierPropose),
la recherche universelle (/api/public/search/) et le devis adapte metier.
"""

import base64
import io
import json

from django.contrib.auth.models import User
from django.test import Client as DjangoClient
from django.test import TestCase
from PIL import Image, ImageDraw

from adminpanel.auth import create_token
from adminpanel.models import Category, MetierPropose, Provider, UserProfile


def _make_distinct_img_b64(seed: int, size=(680, 440)) -> str:
    img = Image.new("RGB", size, ((seed * 53) % 180 + 40, (seed * 97) % 180 + 40, (seed * 31) % 180 + 40))
    draw = ImageDraw.Draw(img)
    for idx in range(12):
        x0 = (idx * 47 + seed * 19) % (size[0] - 80)
        y0 = (idx * 37 + seed * 23) % (size[1] - 60)
        draw.rectangle([x0, y0, x0 + 60, y0 + 45], fill=((idx * 41 + seed * 17) % 220, 120, 90))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=88)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode("ascii")


PNG_1X1_B64 = _make_distinct_img_b64(1)


class SensitiveSearchOptionATests(TestCase):
    def setUp(self):
        self.http = DjangoClient()
        self.cat_nounou = Category.objects.create(
            nom="Nounou & Garde Enfants",
            icone_slug="nounou",
            groupe="Famille & Soins",
            regime_kyc=Category.RegimeKyc.SENSIBLE_CASIER,
            profil_devis=Category.ProfilDevis.FORFAIT,
            search_keywords=["babysitting", "garde", "bebe"],
            registration_questions=[
                {"key": "secourisme", "label": "Gestes premiers secours", "type": "bool", "required": True}
            ],
        )
        self.cat_plomb = Category.objects.create(
            nom="Plomberie",
            icone_slug="tuyau",
            groupe="Maison & Depannage",
            regime_kyc=Category.RegimeKyc.STANDARD_TERRAIN,
            profil_devis=Category.ProfilDevis.DIAGNOSTIC,
            search_keywords=["fuite", "evier", "robinetterie"],
        )

        # Prestataire sensible
        self.u_sens = User.objects.create_user("nounou1", password="Pwd12345!", email="n1@babifix.ci")
        UserProfile.objects.create(user=self.u_sens, role="prestataire", active=True)
        self.tok_sens = create_token(self.u_sens.id, "prestataire")
        self.p_sens = Provider.objects.create(
            user=self.u_sens,
            nom="Awa Garde",
            specialite="Nounou & Garde Enfants",
            ville="Abidjan - Cocody",
            category=self.cat_nounou,
            statut=Provider.Status.PENDING,
        )

        # Prestataire standard
        self.u_std = User.objects.create_user("plomb1", password="Pwd12345!", email="p1@babifix.ci")
        UserProfile.objects.create(user=self.u_std, role="prestataire", active=True)
        self.tok_std = create_token(self.u_std.id, "prestataire")
        self.p_std = Provider.objects.create(
            user=self.u_std,
            nom="Koffi Plombier",
            specialite="Plomberie",
            ville="Abidjan - Yopougon",
            category=self.cat_plomb,
            statut=Provider.Status.VALID,
            disponible=True,
        )

        # Admin staff
        self.admin_user = User.objects.create_superuser("admin_t", "adm@babifix.ci", "AdmPwd123!")

    def _base_kyc_payload(self, cni_number="CI00112233", seed_offset=0):
        return {
            "artisan_tier": "palier_1_proximite",
            "commune_rattachement": "Cocody",
            "whatsapp_interview_requested": False,
            "cni_number": cni_number,
            "cni_expiry": "2030-12-31",
            "cni_recto_b64": _make_distinct_img_b64(10 + seed_offset),
            "cni_verso_b64": _make_distinct_img_b64(20 + seed_offset),
            "selfie_b64": _make_distinct_img_b64(30 + seed_offset, size=(500, 620)),
        }

    def test_sensible_casier_enforced_and_standard_not_blocked(self):
        # 1) Sensible sans casier/reference -> 400 avec champs attendus
        r_fail = self.http.post(
            "/api/prestataire/kyc/submit/",
            data=json.dumps(self._base_kyc_payload()),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {self.tok_sens}",
        )
        self.assertEqual(r_fail.status_code, 400)
        fields = r_fail.json().get("fields", {})
        self.assertIn("casier_judiciaire_b64", fields)
        self.assertIn("reference_contact_nom", fields)
        self.assertIn("reference_contact_tel", fields)

        # 2) Sensible avec casier + contact -> 200 et entretien superviseur active
        ok_payload = self._base_kyc_payload()
        ok_payload.update({
            "casier_judiciaire_b64": PNG_1X1_B64,
            "reference_contact_nom": "Mme Kouame Claire",
            "reference_contact_tel": "+2250701020304",
        })
        r_ok = self.http.post(
            "/api/prestataire/kyc/submit/",
            data=json.dumps(ok_payload),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {self.tok_sens}",
        )
        self.assertEqual(r_ok.status_code, 200)
        self.p_sens.refresh_from_db()
        self.assertTrue(bool(self.p_sens.casier_judiciaire_url))
        self.assertEqual(self.p_sens.reference_contact_nom, "Mme Kouame Claire")
        self.assertTrue(self.p_sens.whatsapp_interview_requested)

        # Valide le presta et verifie le badge casier_verifie sur /api/public/providers/
        self.p_sens.statut = Provider.Status.VALID
        self.p_sens.save(update_fields=["statut"])
        pub = self.http.get("/api/public/providers/?all=1")
        self.assertEqual(pub.status_code, 200)
        found = [x for x in pub.json().get("providers", []) if x["id"] == self.p_sens.id]
        self.assertTrue(found)
        self.assertEqual(found[0]["regime_kyc"], "SENSIBLE_CASIER")
        self.assertTrue(found[0]["casier_verifie"])

        # 3) Standard sans casier/RCCM/CNMCI -> 200 sans blocage
        r_std = self.http.post(
            "/api/prestataire/kyc/submit/",
            data=json.dumps(self._base_kyc_payload(cni_number="CI00998877", seed_offset=50)),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {self.tok_std}",
        )
        self.assertEqual(r_std.status_code, 200)

    def test_option_a_register_metier_propose_and_admin_approve_attaches(self):
        u_new = User.objects.create_user("pisc_user", password="Pwd12345!", email="pisc@babifix.ci")
        UserProfile.objects.create(user=u_new, role="prestataire", active=True)
        tok_new = create_token(u_new.id, "prestataire")

        r = self.http.post(
            "/api/prestataire/register",
            data=json.dumps({
                "nom": "Benoit Piscine",
                "specialite": "Pisciniste Aquatech",
                "metier_propose": "Pisciniste Aquatech",
                "spec_answers": {"experience_bassin": "5 ans"},
                "ville": "Abidjan - Cocody",
                "years_experience": 5,
            }),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {tok_new}",
        )
        self.assertIn(r.status_code, (200, 201))
        body = r.json()
        self.assertEqual((body.get("metier_propose") or {}).get("nom"), "Pisciniste Aquatech")

        mp = MetierPropose.objects.filter(nom__iexact="Pisciniste Aquatech").first()
        self.assertIsNotNone(mp)
        prov = Provider.objects.get(user=u_new)
        self.assertEqual(prov.metier_propose_id, mp.id)
        self.assertIsNone(prov.category_id)
        self.assertEqual(prov.spec_answers.get("experience_bassin"), "5 ans")

        # Admin approuve Option A et cree la categorie
        self.http.force_login(self.admin_user)
        adm = self.http.post(
            "/?section=categories",
            {
                "action": "metier_approve",
                "pk": str(mp.id),
                "create_category": "1",
                "regime_kyc": Category.RegimeKyc.STANDARD_TERRAIN,
                "return_section": "categories",
            },
        )
        self.assertEqual(adm.status_code, 302)
        prov.refresh_from_db()
        self.assertIsNotNone(prov.category_id)
        self.assertEqual(prov.category.nom, "Pisciniste Aquatech")

    def test_universal_search_and_smart_devis_assist(self):
        # Recherche par mot-cle sans accent ("bebe" -> Nounou, "evier" -> Plomberie)
        r_bebe = self.http.get("/api/public/search/?q=bebe")
        self.assertEqual(r_bebe.status_code, 200)
        cats_bebe = [c["nom"] for c in r_bebe.json().get("categories", [])]
        self.assertIn("Nounou & Garde Enfants", cats_bebe)

        r_plomb = self.http.get("/api/public/search/?q=evier")
        self.assertEqual(r_plomb.status_code, 200)
        cats_plomb = [c["nom"] for c in r_plomb.json().get("categories", [])]
        self.assertIn("Plomberie", cats_plomb)

        r_prov = self.http.get("/api/public/search/?q=Koffi")
        self.assertEqual(r_prov.status_code, 200)
        provs = [p["nom"] for p in r_prov.json().get("providers", [])]
        self.assertIn("Koffi Plombier", provs)

        # Smart devis assist renvoie profil, units et regime
        r_dev = self.http.get(
            f"/api/prestataire/smart/devis-assist/?category_id={self.cat_nounou.id}",
            HTTP_AUTHORIZATION=f"Bearer {self.tok_sens}",
        )
        self.assertEqual(r_dev.status_code, 200)
        dd = r_dev.json()
        self.assertEqual(dd["profil_devis"], "FORFAIT")
        self.assertEqual(dd["regime_kyc"], "SENSIBLE_CASIER")
        self.assertTrue(len(dd.get("recommended_units", [])) > 0)
