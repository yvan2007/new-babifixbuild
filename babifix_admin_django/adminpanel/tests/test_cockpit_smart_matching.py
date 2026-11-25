"""
Tests complets du Cockpit Admin Unifie et du Smart Matching reel BABIFIX :
- MatchingService (GPS Haversine adaptatif, creneaux reels, conges, fiabilite, tiers Gold/Silver/Standard)
- Finance KPIs reels (_dashboard_kpi_payload sans donnees synthetiques ni fallbacks factices)
- Transcription complete de reservation sans exposition du chat prive (Loi n° 2013-450)
- Endpoints admin securises (simulate, assign, push-stats, transcription -> 403 si non-staff)
- Sections HTML du cockpit (kpis, ecosysteme, finances, reservations, notifications, parametres)
- Actions POST consolidees (params_update, metier_approve, supervisor_verify_provider)
- Respect strict de la regle zero modification de categories_section.html et zero tiret cadratin
"""

from datetime import date, time, timedelta
from decimal import Decimal
from pathlib import Path

from django.conf import settings
from django.contrib.auth.models import User
from django.test import Client as DjangoClient
from django.test import TestCase
from django.utils import timezone

from adminpanel.models import (
    Category,
    Conversation,
    Devis,
    DeviceToken,
    LigneDevis,
    Message,
    MetierPropose,
    Notification,
    Payment,
    PlatformConfig,
    PlatformRevenue,
    PrestataireAvailabilitySlot,
    PrestataireUnavailability,
    ProAccount,
    Provider,
    Rating,
    Reservation,
    ReservationStatusHistory,
    SystemSetting,
    UserProfile,
)
from adminpanel.services.matching_service import MatchingCriteria, MatchingService
from adminpanel.views import _dashboard_kpi_payload


class SmartMatchingRealEngineTests(TestCase):
    def setUp(self):
        self.cat_plomb = Category.objects.create(nom="Plomberie", icone_slug="tuyau")
        self.now = timezone.now()

        # Prestataire 1 : Gold, proche (Cocody), fiable, disponible avec creneau reel
        self.u_gold = User.objects.create_user("pro_gold", password="Pwd123!")
        self.p_gold = Provider.objects.create(
            user=self.u_gold,
            nom="Kouame Gold",
            specialite="Plomberie",
            ville="Abidjan - Cocody",
            category=self.cat_plomb,
            statut=Provider.Status.VALID,
            disponible=True,
            average_rating=4.9,
            rating_count=22,
            fiabilite_score=98,
            tarif_horaire=Decimal("10000"),
            latitude=5.3490,
            longitude=-3.9880,
            is_certified=True,
            is_premium=True,
            premium_tier="gold",
            premium_until=self.now + timedelta(days=30),
        )
        PrestataireAvailabilitySlot.objects.create(
            provider=self.p_gold,
            jour_semaine=self.now.weekday(),
            heure_debut=time(7, 0),
            heure_fin=time(20, 0),
            actif=True,
        )

        # Prestataire 2 : Standard, lointain, fiabilite plus basse
        self.u_std = User.objects.create_user("pro_std", password="Pwd123!")
        self.p_std = Provider.objects.create(
            user=self.u_std,
            nom="Bamba Standard",
            specialite="Plomberie",
            ville="Abidjan - Yopougon",
            category=self.cat_plomb,
            statut=Provider.Status.VALID,
            disponible=True,
            average_rating=4.2,
            rating_count=6,
            fiabilite_score=72,
            tarif_horaire=Decimal("12000"),
            latitude=5.3360,
            longitude=-4.0950,
            is_premium=False,
            premium_tier="standard",
        )

        # Prestataire 3 : en conge aujourd'hui (doit etre exclu en mode only_available=True)
        self.u_off = User.objects.create_user("pro_off", password="Pwd123!")
        self.p_off = Provider.objects.create(
            user=self.u_off,
            nom="Diallo En Conge",
            specialite="Plomberie",
            ville="Abidjan - Cocody",
            category=self.cat_plomb,
            statut=Provider.Status.VALID,
            disponible=True,
            average_rating=4.9,
            rating_count=30,
            fiabilite_score=99,
            latitude=5.3492,
            longitude=-3.9881,
            is_premium=True,
            premium_tier="gold",
            premium_until=self.now + timedelta(days=30),
        )
        PrestataireUnavailability.objects.create(
            provider=self.p_off,
            date_debut=date.today() - timedelta(days=1),
            date_fin=date.today() + timedelta(days=2),
            motif="Deplacement",
        )

    def test_matching_ranks_gold_nearby_and_excludes_unavailable(self):
        criteria = MatchingCriteria(
            category_id=self.cat_plomb.id,
            query="fuite tuyau",
            lat=5.3485,
            lon=-3.9875,
            client_city="Cocody",
            price_max=15000,
            only_available=True,
        )
        ranked = MatchingService.recommend_providers(criteria, limit=5)
        returned_ids = [item.provider.id for item in ranked]

        self.assertNotIn(self.p_off.id, returned_ids)
        self.assertEqual(returned_ids[0], self.p_gold.id)
        self.assertEqual(ranked[0].tier, "gold")
        self.assertEqual(ranked[0].commission_pct, 8)
        self.assertIsNotNone(ranked[0].distance_km)
        self.assertIn("availability", ranked[0].breakdown)
        self.assertTrue(any("Gold" in r or "certifie" in r for r in ranked[0].reasons))

    def test_recommend_for_reservation_urgent_uses_geo_and_budget(self):
        cli = User.objects.create_user("cli_urg", password="Pwd123!")
        res = Reservation.objects.create(
            reference="RES-URG-001",
            client="cli_urg",
            prestataire="A affecter",
            title="Fuite urgente cuisine",
            montant=Decimal("0"),
            client_user=cli,
            description_probleme="Plomberie tuyau evier casse",
            address_ville="Cocody",
            latitude=5.3485,
            longitude=-3.9875,
            prix_propose=Decimal("15000"),
            is_urgent=True,
        )
        ranked = MatchingService.recommend_for_reservation(res, limit=3)
        self.assertGreaterEqual(len(ranked), 1)
        self.assertEqual(ranked[0].provider.id, self.p_gold.id)


class AdminCockpitAndFinanceTests(TestCase):
    def setUp(self):
        self.admin = User.objects.create_superuser("adm_cockpit", "adm@babifix.ci", "Pwd123!")
        self.client_user = User.objects.create_user("cli_cockpit", password="Pwd123!")
        UserProfile.objects.create(user=self.client_user, role="client", active=True, points_fidelite=250)
        self.pro_user = User.objects.create_user("pro_cockpit", password="Pwd123!")
        UserProfile.objects.create(user=self.pro_user, role="prestataire", active=True)

        self.http = DjangoClient()
        self.http.force_login(self.admin)

        self.cat = Category.objects.create(nom="Electricite", icone_slug="eclair")
        self.prov = Provider.objects.create(
            user=self.pro_user,
            nom="Kone Electric",
            specialite="Electricite",
            ville="Abidjan - Marcory",
            category=self.cat,
            statut=Provider.Status.VALID,
            disponible=True,
            average_rating=4.8,
            rating_count=10,
            fiabilite_score=95,
            whatsapp_interview_requested=True,
        )

    def test_kpi_payload_returns_zero_without_fake_fallback(self):
        _stats, _kpi, _kpi_chart, fk = _dashboard_kpi_payload()
        self.assertEqual(fk["gmv_total"], 0.0)
        self.assertEqual(fk["escrow_total"], 0.0)
        self.assertEqual(fk["total_cash"], 0)
        self.assertEqual(fk["total_mm"], 0)

    def test_kpi_payload_computes_real_escrow_and_effective_takerate(self):
        res_done = Reservation.objects.create(
            reference="RES-FIN-1",
            client="cli_cockpit",
            prestataire="Kone Electric",
            montant=Decimal("100000"),
            statut="Terminee",
            client_user=self.client_user,
            assigned_provider=self.prov,
            prestataire_user=self.pro_user,
            payment_type="MOBILE_MONEY",
            funds_released_at=timezone.now(),
        )
        Payment.objects.create(
            reference="PAY-FIN-1",
            client="cli_cockpit",
            prestataire="Kone Electric",
            montant=Decimal("100000"),
            commission=Decimal("13000"),
            etat=Payment.State.COMPLETE,
            reservation=res_done,
            type_paiement=Payment.TypePaiement.MOBILE_MONEY,
        )
        Reservation.objects.create(
            reference="RES-ESC-2",
            client="cli_cockpit",
            prestataire="Kone Electric",
            montant=Decimal("40000"),
            montant_verse=Decimal("25000"),
            caution_montant=Decimal("2000"),
            caution_payee=True,
            caution_deduite=False,
            statut="INTERVENTION_EN_COURS",
            client_user=self.client_user,
            assigned_provider=self.prov,
        )

        _stats, _kpi, _kpi_chart, fk = _dashboard_kpi_payload()
        self.assertEqual(fk["gmv_total"], 100000.0)
        self.assertEqual(fk["commission_total"], 13000.0)
        self.assertEqual(fk["take_rate_pct"], 13.0)
        self.assertEqual(fk["escrow_total"], 27000.0)

    def test_transcription_api_enforces_privacy_and_staff_auth(self):
        res = Reservation.objects.create(
            reference="RES-TR-01",
            client="cli_cockpit",
            prestataire="A affecter",
            title="Panne tableau electrique",
            montant=Decimal("25000"),
            statut="DEMANDE_ENVOYEE",
            client_user=self.client_user,
            description_probleme="Disjoncteur saute sans cesse",
            address_ville="Marcory",
        )
        ReservationStatusHistory.objects.create(
            reservation=res, old_status="", new_status="DEMANDE_ENVOYEE", changed_by=self.client_user
        )
        Devis.objects.create(
            reservation=res,
            prestataire=self.prov,
            reference="DV-TR-01",
            statut="ENVOYE",
            sous_total=Decimal("25000"),
            total_ttc=Decimal("25000"),
            commission_rate=18,
            commission_montant=Decimal("4500"),
            net_prestataire=Decimal("20500"),
            diagnostic="Remplacement disjoncteur",
        )
        # Message prive de chat qui NE DOIT JAMAIS apparaitre dans la reponse transcription
        secret_msg = "SECRET_CHAT_PRIVE_NE_DOIT_PAS_FUITER"
        conv = Conversation.objects.create(
            client=self.client_user, prestataire=self.pro_user, reservation=res
        )
        Message.objects.create(conversation=conv, sender=self.client_user, body=secret_msg)

        # Un non-staff authentifie doit recevoir 403
        non_staff = DjangoClient()
        non_staff.force_login(self.client_user)
        r_forb = non_staff.get(f"/api/admin/reservations/{res.reference}/transcription/")
        self.assertEqual(r_forb.status_code, 403)

        # Le superuser obtient la transcription complete sans message prive
        r_ok = self.http.get(f"/api/admin/reservations/{res.reference}/transcription/")
        self.assertEqual(r_ok.status_code, 200)
        self.assertNotIn(secret_msg, r_ok.content.decode("utf-8"))
        data = r_ok.json()
        self.assertEqual(data["reservation"]["reference"], "RES-TR-01")
        self.assertEqual(len(data["history"]), 1)
        self.assertEqual(len(data["devis"]), 1)
        self.assertIn("coherence", data["devis"][0])
        self.assertGreaterEqual(len(data["smart_matches"]), 1)

    def test_matching_simulate_assign_and_push_stats_apis(self):
        res = Reservation.objects.create(
            reference="RES-MATCH-02",
            client="cli_cockpit",
            prestataire="A affecter",
            title="Prise brulee",
            montant=Decimal("0"),
            statut="DEMANDE_ENVOYEE",
            client_user=self.client_user,
            address_ville="Marcory",
        )
        DeviceToken.objects.create(
            user=self.client_user, token="fcm-cli-001", platform="android", app="client"
        )
        DeviceToken.objects.create(
            user=self.pro_user, token="fcm-pro-001", platform="ios", app="pro"
        )

        r_sim = self.http.get(f"/api/admin/matching/simulate/?reservation_ref={res.reference}")
        self.assertEqual(r_sim.status_code, 200)
        sim_data = r_sim.json()
        self.assertTrue(sim_data["ok"])
        self.assertEqual(sim_data["results"][0]["provider_id"], self.prov.id)

        r_assign = self.http.post(
            f"/api/admin/reservations/{res.reference}/assign/",
            data='{"auto": true}',
            content_type="application/json",
        )
        self.assertEqual(r_assign.status_code, 200)
        res.refresh_from_db()
        self.assertEqual(res.assigned_provider_id, self.prov.id)

        r_push = self.http.get("/api/admin/push-stats/?role=client")
        self.assertEqual(r_push.status_code, 200)
        self.assertEqual(r_push.json()["estimated_fcm_devices"], 1)

    def test_unified_params_update_and_cockpit_sections(self):
        # 1. Parametres unifies SystemSetting + PlatformConfig
        r_post = self.http.post(
            "/?section=parametres",
            data={
                "action": "params_update",
                "commission": "16",
                "mode_paiement": "Wave, Orange Money, Especes",
                "auto_validation": "on",
                "maintenance": "on",
                "platform_config_present": "1",
                "frais_mise_en_relation_fcfa": "1500",
                "fiabilite_gating_actif": "on",
                "fiabilite_seuil": "70",
                "radar_visite_sans_devis_jours": "4",
                "auto_suspension_actif": "on",
                "suspension_score_seuil": "30",
                "suspension_visites_suspectes": "5",
            },
        )
        self.assertEqual(r_post.status_code, 302)
        s = SystemSetting.objects.get(pk=1)
        cfg = PlatformConfig.get_solo()
        self.assertEqual(s.commission, 16)
        self.assertTrue(s.auto_validation)
        self.assertTrue(s.maintenance)
        self.assertEqual(cfg.frais_mise_en_relation_fcfa, 1500)
        self.assertTrue(cfg.fiabilite_gating_actif)
        self.assertEqual(cfg.fiabilite_seuil, 70)

        # 2. Ecosysteme : MetierPropose + ProAccount + Rating avec note vocale
        metier = MetierPropose.objects.create(
            nom="Domotique",
            nom_normalise="domotique",
            emails=["a@ci.test", "b@ci.test", "c@ci.test", "d@ci.test", "e@ci.test"],
        )
        ProAccount.objects.create(
            user=self.client_user,
            raison_sociale="Residence Riviera B2B",
            contact_nom="Directeur Technique",
        )
        res_rev = Reservation.objects.create(
            reference="RES-REV-1",
            client="cli_cockpit",
            prestataire="Kone Electric",
            montant=Decimal("30000"),
            statut="Terminee",
            client_user=self.client_user,
            assigned_provider=self.prov,
        )
        Rating.objects.create(
            reservation=res_rev,
            client=self.client_user,
            provider=self.prov,
            note=5,
            commentaire="Travail impeccable",
            voice_note_url="https://cdn.babifix.ci/voice/note1.m4a",
        )

        self.assertEqual(self.http.get("/?section=kpis").status_code, 200)
        r_eco = self.http.get("/?section=ecosysteme")
        self.assertEqual(r_eco.status_code, 200)
        self.assertContains(r_eco, "Domotique")
        self.assertContains(r_eco, "Residence Riviera B2B")
        self.assertContains(r_eco, "<audio")

        # 3. Approbation metier + creation categorie active
        self.http.post(
            "/?section=ecosysteme",
            data={"action": "metier_approve", "pk": str(metier.id), "create_category": "1"},
        )
        metier.refresh_from_db()
        self.assertEqual(metier.statut, MetierPropose.Statut.DISPONIBLE)
        self.assertTrue(Category.objects.filter(nom="Domotique", actif=True).exists())

        # 4. Entretien superviseur
        self.http.post(
            "/?section=prestataires",
            data={
                "action": "supervisor_verify_provider",
                "provider_id": str(self.prov.id),
                "certify": "on",
            },
        )
        self.prov.refresh_from_db()
        self.assertIsNotNone(self.prov.supervisor_verified_at)
        self.assertTrue(self.prov.is_certified)
        self.assertFalse(self.prov.whatsapp_interview_requested)

        # 5. Notifications : Tout marquer lu
        Notification.objects.create(user=self.client_user, title="Alert 1", lu=False)
        self.http.post("/?section=notifications", data={"action": "notifications_mark_all_read"})
        self.assertEqual(Notification.objects.filter(lu=False).count(), 0)

        # 6. Finances & Categories intactes
        self.assertContains(self.http.get("/?section=finances"), "BABIFIX PRO GOLD")
        self.assertEqual(self.http.get("/?section=categories").status_code, 200)

    def test_all_sidebar_sections_render_200(self):
        sections = [
            "dashboard", "kpis", "prestataires", "reservations", "kanban",
            "litiges", "clients", "categories", "catalogue", "paiements",
            "finances", "payouts", "ecosysteme", "notifications", "actualites",
            "parametres", "audit",
        ]
        for s in sections:
            resp = self.http.get(f"/?section={s}")
            self.assertEqual(resp.status_code, 200, f"Echec HTTP sur ?section={s}")
        for url in ("/dashboard/kpis/", "/kpi-dashboard/", "/api/admin/business-kpis/"):
            self.assertEqual(self.http.get(url).status_code, 200, f"Echec HTTP sur {url}")

    def test_dynamic_platform_config_api_and_live_services(self):
        from adminpanel.services.provider_subscription_service import (
            ProviderSubscriptionService,
            get_tier_config,
        )
        from adminpanel.services.wallet_service import WalletService

        r_post = self.http.post(
            "/?section=parametres",
            data={
                "action": "params_update",
                "platform_config_present": "1",
                "platform_apps_sync_present": "1",
                "commission": "20",
                "commission_floor_pct": "5",
                "silver_commission_reduction": "6",
                "gold_commission_reduction": "12",
                "silver_price_fcfa": "9000",
                "gold_price_fcfa": "19000",
                "standard_max_devis": "4",
                "silver_max_devis": "20",
                "silver_visibility_boost_pct": "35",
                "gold_visibility_boost_pct": "70",
                "min_withdrawal_fcfa": "2500",
                "daily_withdrawal_cap_fcfa": "300000",
                "frais_mise_en_relation_fcfa": "1000",
                "urgency_surcharge_pct": "20",
                "escrow_auto_confirm_hours": "48",
                "matching_radius_km": "22",
                "enabled_operators": ["wave", "orange"],
                "allow_mobile_money_payments": "on",
                "maintenance": "on",
                "support_phone": "+225 01 02 03 04 05",
                "support_whatsapp": "+225 05 04 03 02 01",
            },
        )
        self.assertEqual(r_post.status_code, 302)

        r_cfg = self.client.get("/api/public/config/")
        self.assertEqual(r_cfg.status_code, 200)
        payload = r_cfg.json()
        self.assertEqual(payload["commission_base_pct"], 20)
        self.assertEqual(payload["tiers"]["standard"]["commission_pct"], 20)
        self.assertEqual(payload["tiers"]["silver"]["commission_pct"], 14)
        self.assertEqual(payload["tiers"]["silver"]["price_fcfa"], 9000)
        self.assertEqual(payload["tiers"]["gold"]["commission_pct"], 8)
        self.assertEqual(payload["tiers"]["gold"]["price_fcfa"], 19000)
        self.assertEqual(payload["wallet"]["min_withdrawal_fcfa"], 2500)
        self.assertEqual(payload["escrow"]["frais_mise_en_relation_fcfa"], 1000)
        self.assertTrue(payload["apps"]["maintenance"])
        self.assertEqual(payload["payment_modes"]["operators"], ["wave", "orange"])

        # Moteur financier Backend synchronise sans redemarrage
        self.assertEqual(ProviderSubscriptionService.base_commission_rate(self.prov), 20)
        self.assertEqual(
            ProviderSubscriptionService.calculate_effective_commission(self.prov),
            20,
        )
        silver_cfg = get_tier_config("silver")
        self.assertEqual(silver_cfg["price"], 9000)
        self.assertEqual(silver_cfg["commission_effective_pct"], 14)

        self.prov.solde_fcfa = Decimal("5000")
        self.prov.save(update_fields=["solde_fcfa"])
        wd_res = WalletService.request_withdrawal(
            provider_id=self.prov.id,
            amount_fcfa=Decimal("1500"),
            phone="+2250700000000",
            operator="wave",
        )
        self.assertEqual(wd_res.get("error"), "min_amount")
        self.assertIn("2500", wd_res.get("detail", ""))

        wd_op = WalletService.request_withdrawal(
            provider_id=self.prov.id,
            amount_fcfa=Decimal("3000"),
            phone="+2250700000000",
            operator="mtn",
        )
        self.assertEqual(wd_op.get("error"), "invalid_operator")

    def test_no_em_or_en_dash_in_cockpit_deliverables(self):
        base = Path(settings.BASE_DIR)
        checked_paths = [
            base / "adminpanel" / "services" / "matching_service.py",
            base / "adminpanel" / "services" / "platform_config_service.py",
            base / "adminpanel" / "views_admin_cockpit.py",
            base / "static" / "adminpanel" / "admin-pro.css",
            base / "static" / "adminpanel" / "admin-pro.js",
            base / "templates" / "adminpanel" / "partials" / "kpis_section.html",
            base / "templates" / "adminpanel" / "partials" / "ecosysteme_section.html",
            base / "templates" / "adminpanel" / "partials" / "finances_section.html",
            base / "templates" / "adminpanel" / "partials" / "parametres_section.html",
            base / "templates" / "adminpanel" / "partials" / "categories_section.html",
            base / "templates" / "adminpanel" / "partials" / "catalogue_section.html",
            base / "templates" / "adminpanel" / "partials" / "dashboard_stats.html",
            base / "templates" / "adminpanel" / "kpi_dashboard.html",
            base / "templates" / "adminpanel" / "dashboard.html",
        ]
        for p in checked_paths:
            txt = p.read_text(encoding="utf-8")
            self.assertNotIn("\u2014", txt, f"Tiret cadratin detecte dans {p}")
            self.assertNotIn("\u2013", txt, f"Tiret semi-cadratin detecte dans {p}")
            self.assertNotIn("&mdash;", txt, f"&mdash; detecte dans {p}")
            self.assertNotIn("&ndash;", txt, f"&ndash; detecte dans {p}")
