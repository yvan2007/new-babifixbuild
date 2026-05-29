"""
Debug e2e : cree des comptes de test, parcourt tous les flux et appelle chaque
endpoint API en verifiant qu'aucune 500 ne survient.

Usage : python manage.py e2e_debug
Classement :
  2xx        -> OK
  4xx        -> attendu/validation (note)
  5xx        -> ERREUR SERVEUR (a corriger)
"""
import json

from django.contrib.auth.models import User
from django.core.management.base import BaseCommand
from django.test import Client
from django.utils import timezone

from decimal import Decimal

from adminpanel.auth import create_token, create_refresh_token
from adminpanel.models import (
    Category, Provider, UserProfile, Reservation, ProAccount,
    Devis, LigneDevis, WalletTransaction, ProSite,
)


class Command(BaseCommand):
    help = "Teste tous les endpoints API de bout en bout (detection des 500)."

    def handle(self, *args, **opts):
        self.c = Client()
        self.results = []  # (method, path, role, status)
        self._setup()
        try:
            self._auth_endpoints()
            self._public_endpoints()
            self._client_get()
            self._prestataire_get()
            self._admin_get()
            self._lifecycle()
            self._features()
            self._remaining()
        finally:
            self._report()
            self._teardown()

    # ---------------------------------------------------------------- helpers
    def _tok(self, role):
        return {"client": self.tok_client, "prestataire": self.tok_presta, "admin": self.tok_admin}.get(role)

    def hit(self, method, path, role=None, body=None, label=""):
        headers = {}
        if role:
            headers["HTTP_AUTHORIZATION"] = "Bearer " + self._tok(role)
        try:
            if method == "GET":
                r = self.c.get(path, **headers)
            elif method == "POST":
                r = self.c.post(path, data=json.dumps(body or {}),
                                content_type="application/json", **headers)
            elif method == "DELETE":
                r = self.c.delete(path, data=json.dumps(body or {}),
                                  content_type="application/json", **headers)
            else:
                r = self.c.generic(method, path, **headers)
            status = r.status_code
            snippet = ""
            if status >= 400:
                try:
                    snippet = r.content.decode("utf-8", "replace")[:140].replace("\n", " ")
                except Exception:
                    snippet = ""
        except Exception as e:  # une exception = 500 de fait
            status = 599
            snippet = str(e)[:140]
            self.stdout.write(self.style.ERROR(f"  EXC {method} {path} -> {e}"))
        self.results.append((method, path, role or "-", status, label, snippet))
        return status

    # ---------------------------------------------------------------- setup
    def _setup(self):
        self.cat, _ = Category.objects.get_or_create(
            nom="_E2E_Plomberie", defaults={"actif": True}
        )
        self.cat.actif = True
        self.cat.save()

        def mkuser(uname, role):
            u, _ = User.objects.get_or_create(username=uname, defaults={"email": uname + "@e2e.ci"})
            UserProfile.objects.get_or_create(user=u, defaults={"role": role, "active": True})
            return u

        self.u_client = mkuser("_e2e_client", "client")
        self.u_presta = mkuser("_e2e_presta", "prestataire")
        self.u_admin = mkuser("_e2e_admin", "admin")
        self.u_admin.is_staff = True
        self.u_admin.is_superuser = True
        self.u_admin.save()

        self.provider, _ = Provider.objects.get_or_create(
            user=self.u_presta,
            defaults={"nom": "E2E Plombier", "statut": "Valide", "specialite": "Plomberie", "ville": "Cocody"},
        )
        self.provider.statut = "Valide"
        self.provider.category = self.cat
        self.provider.save()

        self.tok_client = create_token(self.u_client.id, "client")
        self.tok_presta = create_token(self.u_presta.id, "prestataire")
        self.tok_admin = create_token(self.u_admin.id, "admin")
        self.ref = None
        self.stdout.write(self.style.MIGRATE_HEADING("== Setup OK (client/presta/admin + provider + categorie) =="))

    # ---------------------------------------------------------------- groups
    def _auth_endpoints(self):
        self.hit("GET", "/api/auth/me", "client", label="auth me")
        self.hit("POST", "/api/auth/login", body={"email": "_e2e_client@e2e.ci", "password": "x"}, label="login (bad pw attendu)")
        self.hit("POST", "/api/auth/register", body={
            "email": "_e2e_new@e2e.ci", "password": "Passw0rd!", "name": "New E2E",
            "phone": "+2250700000001", "countryCode": "CI", "role": "client",
        }, label="register")
        self.hit("POST", "/api/auth/fcm-token", "client", body={"token": "FAKE_TOKEN_E2E", "platform": "android"}, label="fcm register")

    def _public_endpoints(self):
        for p in ["/api/public/vitrine/", "/api/public/categories/", "/api/public/providers/", "/api/health/"]:
            self.hit("GET", p, label="public")

    def _client_get(self):
        paths = [
            "/api/client/home", "/api/client/actualites",
            f"/api/client/actualites", "/api/client/prestataires",
            f"/api/client/prestataires/{self.provider.id}/",
            f"/api/client/prestataires/{self.provider.id}/portfolio",
            "/api/client/favorites/", "/api/client/payments/",
            "/api/client/fidelite/", "/api/client/reservations/list",
            "/api/client/invoices/", "/api/notifications", "/api/auth/referral/",
            "/api/messages",
        ]
        for p in paths:
            self.hit("GET", p, "client", label="client GET")

    def _prestataire_get(self):
        paths = [
            "/api/prestataire/me", "/api/prestataire/stats/", "/api/prestataire/requests",
            "/api/prestataire/wallet/", "/api/prestataire/contrat/",
            "/api/prestataire/premium/tiers/", "/api/prestataire/premium/subscribe/",
            "/api/prestataire/premium/calculator/", "/api/prestataire/kyc/status/",
        ]
        for p in paths:
            self.hit("GET", p, "prestataire", label="presta GET")
        self.hit("GET", "/api/pro/formules/", label="pro formules")
        self.hit("GET", "/api/pro/account/", "client", label="pro account (none)")

    def _admin_get(self):
        for p in ["/api/admin/audit-log/", "/api/admin/platform-revenue/", "/api/admin/business-kpis/"]:
            self.hit("GET", p, "admin", label="admin GET")

    # ---------------------------------------------------------------- lifecycle
    def _lifecycle(self):
        # 1) Client cree une reservation
        st = self.hit("POST", "/api/client/reservations", "client", body={
            "title": "Fuite robinet", "category_id": self.cat.id,
            "provider_id": self.provider.id,
            "description": "Fuite sous l'evier",
            "description_probleme": "Fuite sous l'evier de la cuisine",  # déclenche le flux devis
            "address_label": "Cocody Riviera", "payment_type": "ESPECES",
        }, label="creer reservation")
        # recuperer la reference creee (celle de NOTRE client)
        res = Reservation.objects.filter(client_user_id=self.u_client.id).order_by("-id").first()
        if res:
            self.ref = res.reference
            # s'assurer qu'elle est bien assignee a notre prestataire pour le flux
            if res.assigned_provider_id != self.provider.id:
                res.assigned_provider = self.provider
                res.save(update_fields=["assigned_provider"])
        if not self.ref:
            self.stdout.write(self.style.WARNING("  (pas de reference -> lifecycle partiel)"))
            return
        ref = self.ref
        self.hit("GET", f"/api/client/reservations/{ref}/detail", "client", label="detail resa")
        # 2) Prestataire envoie un devis
        self.hit("POST", f"/api/prestataire/requests/{ref}/devis", "prestataire", body={
            "diagnostic": "Remplacement joint", "validite_jours": 7,
            "lignes": [{"type_ligne": "MAIN_OEUVRE", "description": "Main d'oeuvre", "quantite": 1, "prix_unitaire": 10000}],
        }, label="creer devis")
        self.hit("GET", f"/api/client/reservations/{ref}/devis", "client", label="lire devis")
        self.hit("GET", f"/api/client/reservations/{ref}/devis/compare/", "client", label="comparer devis")
        # 3) Client accepte
        self.hit("POST", f"/api/client/reservations/{ref}/devis/accept", "client", label="accepter devis")
        # 4) Prestataire demarre puis termine
        self.hit("POST", f"/api/prestataire/requests/{ref}/demarrer", "prestataire", label="demarrer")
        self.hit("POST", f"/api/prestataire/requests/{ref}/terminer", "prestataire", label="terminer")
        # 5) Client confirme + paie + note
        self.hit("POST", f"/api/client/reservations/{ref}/confirm-prestation", "client", label="confirmer")
        self.hit("POST", f"/api/client/reservations/{ref}/pay-post-prestation", "client", body={"method_id": "ESPECES"}, label="payer")
        self.hit("POST", f"/api/client/reservations/{ref}/rating", "client", body={"note": 5, "commentaire": "Parfait"}, label="noter")
        # messages
        self.hit("GET", f"/api/messages/{ref}", "client", label="messages resa")

    # ---------------------------------------------------------------- features
    def _features(self):
        # Premium (probable 402 solde insuffisant -> pas 500)
        self.hit("POST", "/api/prestataire/premium/subscribe/", "prestataire", body={"tier": "silver"}, label="souscrire premium")
        # B2B
        self.hit("POST", "/api/pro/account/", "client", body={"raison_sociale": "Syndic E2E", "formule": "starter"}, label="creer compte pro")
        self.hit("GET", "/api/pro/sites/", "client", label="sites pro")
        self.hit("POST", "/api/pro/sites/", "client", body={"nom": "Immeuble A", "commune": "Cocody"}, label="ajouter site")
        self.hit("GET", "/api/pro/invoice/", "client", label="facture pro")
        # Referral (GET = obtenir le code)
        self.hit("GET", "/api/auth/referral/", "client", label="referral code")
        # Urgence preview (GET)
        self.hit("GET", "/api/client/reservations/urgence-preview/?montant=10000", "client", label="urgence preview")
        # Wallet info (POST = mise a jour)
        self.hit("POST", "/api/prestataire/wallet/info/", "prestataire", body={"phone": "+2250700000000", "operator": "orange"}, label="wallet info update")

    # ---------------------------------------------------------------- remaining
    def _mkres(self, statut, ref=None):
        import uuid
        ref = ref or ("E2E-" + uuid.uuid4().hex[:8])
        return Reservation.objects.create(
            reference=ref, title="Test e2e", client="_e2e_client", prestataire="E2E Plombier",
            montant=Decimal("10000"), statut=statut, assigned_provider=self.provider,
            client_user=self.u_client, prestataire_user_id=self.u_presta.id,
            payment_type=Reservation.PaymentType.ESPECES,
            description_probleme="Probleme test",
        )

    def _remaining(self):
        S = Reservation.Status
        # --- Prestataire: accept / refuse / decision / photos / status sur des demandes ---
        r_acc = self._mkres(S.DEMANDE_ENVOYEE)
        self.hit("GET", f"/api/prestataire/requests/{r_acc.reference}/status", "prestataire", label="req status")
        self.hit("POST", f"/api/prestataire/requests/{r_acc.reference}/accept", "prestataire", label="req accept")
        r_ref = self._mkres(S.DEMANDE_ENVOYEE)
        self.hit("POST", f"/api/prestataire/requests/{r_ref.reference}/refuse", "prestataire", body={"motif": "Indisponible"}, label="req refuse")
        r_dec = self._mkres(S.DEMANDE_ENVOYEE)
        self.hit("POST", f"/api/prestataire/requests/{r_dec.reference}/decision", "prestataire", body={"decision": "accept"}, label="req decision")
        r_ph = self._mkres(S.INTERVENTION_EN_COURS)
        self.hit("POST", f"/api/prestataire/requests/{r_ph.reference}/photos", "prestataire", body={"photos": ["data:image/png;base64,iVBORw0KGgo="]}, label="req photos")

        # --- Refus de devis (client) ---
        r_dev = self._mkres(S.DEVIS_ENVOYE)
        d = Devis.objects.create(reservation=r_dev, prestataire=self.provider, diagnostic="diag", statut=Devis.Statut.ENVOYE)
        LigneDevis.objects.create(devis=d, type_ligne="MAIN_OEUVRE", description="MO", quantite=1, prix_unitaire=10000)
        self.hit("POST", f"/api/client/reservations/{r_dev.reference}/devis/refuse", "client", label="refuser devis")

        # --- Espèces : declare (client) -> confirm (presta) -> validate (admin) ---
        r_cash = self._mkres(S.INTERVENTION_EN_COURS)
        self.hit("POST", f"/api/client/reservations/{r_cash.reference}/cash-declare", "client", body={"montant": 10000}, label="cash declare")
        self.hit("POST", f"/api/prestataire/requests/{r_cash.reference}/cash-confirm", "prestataire", body={"montant": 10000}, label="cash confirm")
        self.hit("POST", f"/api/admin/reservations/{r_cash.reference}/cash-validate", "admin", label="cash validate (admin)")

        # --- Litige + annulation ---
        r_lit = self._mkres(S.DEVIS_ACCEPTE)
        self.hit("POST", f"/api/client/reservations/{r_lit.reference}/dispute", "client", body={"motif": "Travail non conforme"}, label="ouvrir litige")
        r_can = self._mkres(S.DEMANDE_ENVOYEE)
        self.hit("POST", f"/api/client/reservations/{r_can.reference}/cancel", "client", label="annuler resa")

        # --- Prestataire note le client (resa terminee) ---
        r_done = self._mkres(S.DONE)
        self.hit("POST", f"/api/prestataire/reservations/{r_done.reference}/rate-client", "prestataire", body={"note": 5, "commentaire": "Bon client"}, label="noter client")
        self.hit("POST", f"/api/client/reservations/{r_done.reference}/rating-voice/", "client", body={}, label="rating voice (vide)")

        # --- Admin : status / move / export ---
        r_adm = self._mkres(S.DEMANDE_ENVOYEE)
        self.hit("POST", f"/api/admin/reservation/{r_adm.id}/status", "admin", body={"statut": "Annulee"}, label="admin status")
        self.hit("POST", "/api/admin/reservation/move", "admin", body={"reference": r_adm.reference, "statut": "DEMANDE_ENVOYEE"}, label="admin move")
        for kind in ["reservations", "prestataires", "paiements"]:
            self.hit("GET", f"/api/admin/export/{kind}/", "admin", label=f"export {kind}")

        # --- Paiements : GeniusPay + acompte/solde ---
        r_pay = self._mkres(S.DEVIS_ACCEPTE)
        self.hit("POST", "/api/paiements/geniuspay/initiate/", "client", body={"reservation": r_pay.reference, "montant": 10000, "operator": "orange", "phone": "+2250700000000"}, label="geniuspay initiate")
        self.hit("GET", f"/api/paiements/geniuspay/status/{r_pay.reference}/", "client", label="geniuspay status")
        self.hit("POST", "/api/paiements/geniuspay/webhook/", body={"reference": r_pay.reference, "status": "SUCCESS"}, label="geniuspay webhook")
        self.hit("POST", "/api/reservation/paiement-acompte/", "client", body={"reference": r_pay.reference, "montant": 3000}, label="paiement acompte")
        self.hit("POST", "/api/reservation/paiement-solde/", "client", body={"reference": r_pay.reference, "montant": 7000}, label="paiement solde")

        # --- KYC submit / contrat sign / favoris / withdraw / disputes / refresh ---
        self.hit("POST", "/api/prestataire/kyc/submit/", "prestataire", body={"cni_number": "CI012345678", "cni_expiry": "2030-01-01", "cni_recto_b64": "data:image/png;base64,iVBORw0KGgo=", "cni_verso_b64": "data:image/png;base64,iVBORw0KGgo=", "selfie_b64": "data:image/png;base64,iVBORw0KGgo="}, label="kyc submit")
        self.hit("POST", "/api/prestataire/contrat/sign/", "prestataire", body={"signature": "data:image/png;base64,iVBORw0KGgo=", "version": "1.0"}, label="contrat sign")
        self.hit("GET", "/api/prestataire/disputes/", "prestataire", label="presta disputes")
        self.hit("POST", "/api/client/favorites/", "client", body={"provider_id": self.provider.id}, label="ajouter favori")
        self.hit("DELETE", "/api/client/favorites/", "client", body={"provider_id": self.provider.id}, label="retirer favori")
        self.hit("POST", "/api/prestataire/wallet/withdraw/", "prestataire", body={"amount": 500, "phone": "+2250700000000", "operator": "orange"}, label="retrait (montant<min attendu)")
        # admin valide un retrait (on cree une tx pending)
        tx = WalletTransaction.objects.create(provider=self.provider, tx_type="debit", amount_fcfa=Decimal("1000"), status="pending", phone="+2250700000000", operator="orange")
        self.hit("POST", f"/api/admin/wallet/withdrawals/{tx.id}/validate/", "admin", label="admin valide retrait")
        # refresh token
        self.hit("POST", "/api/auth/refresh", body={"refresh": create_refresh_token(self.u_client.id, "client")}, label="refresh token")
        # portfolio + pdf invoices
        self.hit("GET", f"/api/client/prestataires/{self.provider.id}/portfolio", "client", label="portfolio")
        # intervention B2B (si compte pro cree par _features)
        acc = ProAccount.objects.filter(user=self.u_client).first()
        site = ProSite.objects.filter(pro_account=acc).first() if acc else None
        if site:
            self.hit("POST", "/api/pro/interventions/", "client", body={"site_id": site.id, "description": "Panne ascenseur"}, label="intervention B2B")

    # ---------------------------------------------------------------- report
    def _report(self):
        ok = [r for r in self.results if 200 <= r[3] < 300]
        c4 = [r for r in self.results if 400 <= r[3] < 500]
        c5 = [r for r in self.results if r[3] >= 500]
        self.stdout.write("\n" + "=" * 60)
        self.stdout.write(self.style.MIGRATE_HEADING(
            f"RESULTAT : {len(self.results)} appels | {len(ok)} OK(2xx) | {len(c4)} 4xx | {len(c5)} 5xx"
        ))
        self.stdout.write("--- 4xx (a verifier, souvent normal: validation/etat) ---")
        for m, p, role, st, lbl, snip in c4:
            self.stdout.write(f"  {st} {m} {p} [{role}] {lbl} :: {snip}")
        if c5:
            self.stdout.write(self.style.ERROR("--- 5xx (ERREURS SERVEUR a corriger) ---"))
            for m, p, role, st, lbl, snip in c5:
                self.stdout.write(self.style.ERROR(f"  {st} {m} {p} [{role}] {lbl} :: {snip}"))
        else:
            self.stdout.write(self.style.SUCCESS("--- 0 erreur 500 : aucun plantage serveur ---"))

    def _teardown(self):
        try:
            Reservation.objects.filter(assigned_provider=self.provider).delete()
            Reservation.objects.filter(client_user_id=self.u_client.id).delete()
            ProAccount.objects.filter(user=self.u_client).delete()
            self.provider.delete()
            for u in (self.u_client, self.u_presta, self.u_admin):
                User.objects.filter(pk=u.pk).delete()
            User.objects.filter(email="_e2e_new@e2e.ci").delete()
            self.cat.delete()
            self.stdout.write("Cleanup OK")
        except Exception as e:
            self.stdout.write(self.style.WARNING(f"Cleanup partiel: {e}"))
