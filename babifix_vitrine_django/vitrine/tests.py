"""Tests Site Vitrine BABIFIX : footer social/paiement sans contour blanc, erreurs animées et sécurité."""
import json
import struct
import zlib
from pathlib import Path

from django.conf import settings
from django.core.cache import cache
from django.test import Client as DjangoClient, TestCase, override_settings


def _png_top_left_alpha(path: Path) -> int:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise AssertionError(f"{path.name} n'est pas un PNG valide")
    pos = 8
    color_type = None
    idat_chunks = []
    while pos + 8 <= len(data):
        length, ctype = struct.unpack(">I4s", data[pos : pos + 8])
        chunk_data = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if ctype == b"IHDR":
            _w, _h, bit_depth, color_type, _comp, _flt, _inter = struct.unpack(">IIBBBBB", chunk_data)
            if bit_depth != 8:
                raise AssertionError(f"{path.name} bit_depth inattendu: {bit_depth}")
        elif ctype == b"IDAT":
            idat_chunks.append(chunk_data)
        elif ctype == b"IEND":
            break
    if color_type != 6:
        raise AssertionError(f"{path.name} doit etre RGBA (color_type=6), recu {color_type}")
    raw = zlib.decompress(b"".join(idat_chunks))
    # Row 0 filter byte + R, G, B, A -> pixel (0,0) a gauche/haut a left=0 et above=0 donc alpha brut = exact
    return raw[4]


class VitrineSecurityAndUiTests(TestCase):
    def setUp(self):
        cache.clear()
        self.client = DjangoClient()

    def test_payment_logos_have_transparent_corners_and_no_white_chip_bg(self):
        logos_dir = Path(settings.BASE_DIR) / "static" / "vitrine" / "payment-logos"
        for name in ("orange-money.png", "mtn-momo.png", "wave.png", "moov-money.png"):
            self.assertEqual(
                _png_top_left_alpha(logos_dir / name),
                0,
                f"{name} doit avoir des coins transparents sans détour blanc",
            )

        css = (Path(settings.BASE_DIR) / "static" / "vitrine" / "vitrine-shell.css").read_text(encoding="utf-8")
        # Aucun background blanc sur .bx-pay-chip
        chip_block = css.split(".bx-pay-chip {")[1].split("}")[0]
        self.assertIn("background: transparent", chip_block)
        self.assertNotIn("#ffffff", chip_block)

    def test_footer_contains_social_icons_tiktok_facebook_instagram_linkedin(self):
        resp = self.client.get("/")
        self.assertEqual(resp.status_code, 200)
        html = resp.content.decode("utf-8")
        self.assertIn('id="SocailIcons"', html)
        for label in ("TikTok", "Facebook", "Instagram", "LinkedIn"):
            self.assertIn(label, html)
        self.assertNotIn("\u2014", html)
        self.assertNotIn("\u2013", html)

    @override_settings(DEBUG=False)
    def test_vitrine_error_pages_animated_train_and_404_handler(self):
        for code in (400, 403, 404, 500, 505):
            r = self.client.get(f"/erreur/{code}/")
            self.assertEqual(r.status_code, code)
            html = r.content.decode("utf-8")
            self.assertIn("not_found_svg", html)
            self.assertIn("not_found_car-layers", html)
            self.assertIn(str(code), html)
            self.assertNotIn("\u2014", html)
            self.assertNotIn("\u2013", html)

        r404 = self.client.get("/page-qui-nexiste-pas-babifix")
        self.assertEqual(r404.status_code, 404)
        self.assertIn("not_found_svg", r404.content.decode("utf-8"))

    def test_vitrine_proxy_blocks_admin_and_path_traversal(self):
        for bad_path in (
            "/api/admin/providers/",
            "/api/internal/run-reminders/",
            "/api/public/categories/../../admin/",
            "/media/../../.env",
        ):
            r = self.client.get(bad_path)
            self.assertEqual(r.status_code, 403, f"Le proxy vitrine doit bloquer {bad_path}")

    def test_vitrine_newsletter_validation_and_rate_limit_anti_spoof(self):
        r_bad = self.client.post(
            "/api/newsletter/subscribe/",
            data=json.dumps({"email": "not-an-email"}),
            content_type="application/json",
        )
        self.assertEqual(r_bad.status_code, 400)

        # Spoofer X-Forwarded-For en dev DEBUG ne doit pas contourner la limite
        for i in range(5):
            r = self.client.post(
                "/api/newsletter/subscribe/",
                data=json.dumps({"email": f"user{i}@babifix.ci"}),
                content_type="application/json",
                HTTP_X_FORWARDED_FOR=f"10.0.0.{i+1}",
            )
            self.assertEqual(r.status_code, 200)

        r6 = self.client.post(
            "/api/newsletter/subscribe/",
            data=json.dumps({"email": "user5@babifix.ci"}),
            content_type="application/json",
            HTTP_X_FORWARDED_FOR="10.0.0.99",
        )
        self.assertEqual(r6.status_code, 429)

    def test_vitrine_security_headers_present(self):
        r = self.client.get("/")
        self.assertIn("Content-Security-Policy", r)
        self.assertIn("Permissions-Policy", r)
        self.assertEqual(r["X-Content-Type-Options"], "nosniff")
        self.assertEqual(r["X-Frame-Options"], "DENY")
        self.assertEqual(r["Referrer-Policy"], "strict-origin-when-cross-origin")
        self.assertIn("X-Request-ID", r)
        self.assertIn("X-Response-Time-Ms", r)

    def test_vitrine_healthz_and_gzip_and_csrf_isolation(self):
        from django.test import Client

        h = self.client.get("/healthz/")
        self.assertEqual(h.status_code, 200)
        self.assertEqual(h.json()["status"], "ok")

        c1 = Client()
        c2 = Client()
        r1 = c1.get("/", HTTP_ACCEPT_ENCODING="gzip")
        r2 = c2.get("/", HTTP_ACCEPT_ENCODING="gzip")
        self.assertEqual(r1.status_code, 200)
        self.assertEqual(r2.status_code, 200)
        self.assertIn("Vary", r1)
        tok1 = r1.cookies.get("csrftoken")
        tok2 = r2.cookies.get("csrftoken")
        if tok1 and tok2:
            self.assertNotEqual(tok1.value, tok2.value)

    def test_vitrine_seo_robots_sitemap_jsonld_and_local_service_pages(self):
        # 1. robots.txt propre avec Disallow API/admin + Sitemap
        r_rob = self.client.get("/robots.txt")
        self.assertEqual(r_rob.status_code, 200)
        rob_txt = r_rob.content.decode("utf-8")
        self.assertIn("Disallow: /api/", rob_txt)
        self.assertIn("Disallow: /admin/", rob_txt)
        self.assertIn("Sitemap:", rob_txt)

        # 2. sitemap.xml riche (pages metiers + pages locales communes)
        r_map = self.client.get("/sitemap.xml")
        self.assertEqual(r_map.status_code, 200)
        xml = r_map.content.decode("utf-8")
        self.assertIn("/services/plomberie/", xml)
        self.assertIn("/services/plomberie/cocody/", xml)
        self.assertIn("/services/climatisation/marcory/", xml)
        self.assertIn("/services/nounou-garde-enfants/abidjan/", xml)
        self.assertIn("<lastmod>", xml)

        # 3. Home JSON-LD valide sans faux aggregateRating (reviewCount 2500 supprime)
        r_home = self.client.get("/")
        self.assertEqual(r_home.status_code, 200)
        home_html = r_home.content.decode("utf-8")
        self.assertNotIn('"reviewCount": "2500"', home_html)
        self.assertIn("HomeAndConstructionBusiness", home_html)
        self.assertIn("SearchAction", home_html)

        # 4. Annuaire /services/ et pages locales /services/plomberie/cocody/
        for url, must_contain in (
            ("/services/", "Plomberie"),
            ("/services/plomberie/", "Plomberie"),
            ("/services/plomberie/cocody/", "Plombier verifie a Cocody"),
            ("/services/nounou-garde-enfants/abidjan/", "Nounou verifiee a Abidjan"),
        ):
            resp = self.client.get(url)
            self.assertEqual(resp.status_code, 200, f"Echec SEO sur {url}")
            body = resp.content.decode("utf-8")
            self.assertIn(must_contain, body)
            self.assertIn('application/ld+json', body)
            self.assertIn("BreadcrumbList", body)
            if url != "/services/":
                self.assertIn("FAQPage", body)
            else:
                self.assertIn("ItemList", body)
            self.assertNotIn("\u2014", body)
            self.assertNotIn("\u2013", body)

        # 5. Slug inconnu -> 404 propre (anti soft-404 / anti injection)
        r_bad = self.client.get("/services/metier-inconnu/cocody/")
        self.assertEqual(r_bad.status_code, 404)

    def test_vitrine_live_console_cash_logo_and_header_responsive(self):
        from unittest.mock import patch

        mock_vitrine = {
            "hero_title": "",
            "hero_subtitle": "",
            "stats": {"providers_count": 16, "reservations_total": 46, "active_cities_count": 2},
            "kpis": [
                {"label": "Prestataires vérifiés", "value": "16", "kind": "providers", "sub": "Identité CNI contrôlée · 2 ville(s)"},
                {"label": "Missions & demandes", "value": "46", "kind": "services", "sub": "6 terminée(s) · 40 en suivi"},
                {"label": "Note moyenne client", "value": "4,8 / 5", "kind": "rating", "stars": 5, "sub": "12 avis client(s)"},
                {"label": "Clients satisfaits", "value": "96 %", "kind": "satisfaction", "gauge_pct": 96, "sub": "Basé sur 12 avis vérifié(s)"},
            ],
            "cities": [
                {"key": "abidjan", "name": "Abidjan", "svg_x": 755, "svg_y": 864, "label_x": 784, "label_y": 875, "anchor": "start", "color": "#4CC9F0", "is_hub": True, "providers_count": 14, "reservations_count": 40, "has_activity": True, "intensity": "high", "pulse_sec": 1.6},
                {"key": "bouake", "name": "Bouaké", "svg_x": 594, "svg_y": 488, "label_x": 623, "label_y": 499, "anchor": "start", "color": "#10B981", "is_hub": True, "providers_count": 2, "reservations_count": 6, "has_activity": True, "intensity": "medium", "pulse_sec": 2.2},
            ],
            "live_feed": [
                {"text": "Plomberie · Cocody (Abidjan) · Terminée il y a 2 h", "city_key": "abidjan", "city_name": "Abidjan", "status": "Terminée"}
            ],
        }
        with patch("vitrine.views.fetch_admin_public_vitrine", return_value=mock_vitrine):
            r = self.client.get("/")
            self.assertEqual(r.status_code, 200)
            html = r.content.decode("utf-8")
            self.assertIn("babifix-live-cities-data", html)
            self.assertIn("babifix-live-feed-data", html)
            self.assertIn("Plomberie · Cocody (Abidjan)", html)
            self.assertIn('data-kpi-val>16<', html.replace('data-kpi-val>16<', 'data-kpi-val>16<'))
            self.assertNotIn("10,000+", html)
            self.assertNotIn("50,000+", html)
            self.assertIn('fill="#059669"', html)
            self.assertIn('fill="#F59E0B"', html)

            r_api = self.client.get("/api/live-console/")
            self.assertEqual(r_api.status_code, 200)
            payload = r_api.json()
            self.assertEqual(payload["kpis"][0]["value"], "16")
            self.assertEqual(payload["cities"][1]["key"], "bouake")

        css = (Path(settings.BASE_DIR) / "static" / "vitrine" / "vitrine-shell.css").read_text(encoding="utf-8")
        self.assertIn("overflow-x: clip", css)
        self.assertIn("@media (max-width: 1240px)", css)
        self.assertIn("@media (max-width: 1120px)", css)
