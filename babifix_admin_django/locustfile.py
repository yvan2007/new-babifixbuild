# locustfile.py — Tests de performance BABIFIX
"""
Tests de performance avec Locust
Usage : locust -f locustfile.py --host=http://localhost:8000
Pour headless : locust -f locustfile.py --headless -u 10 -r 10 -t 60s --host=http://localhost:8000
"""
import random
import string
from locust import HttpUser, task, between, events


def random_string(length=8):
    return ''.join(random.choices(string.ascii_lowercase, k=length))


class BabifixUser(HttpUser):
    wait_time = between(1, 3)
    token = None

    def on_start(self):
        """Login au debut de chaque session utilisateur."""
        username = f"testuser_{random_string()}"
        
        # Creer un utilisateur de test (ou utiliser un existant)
        resp = self.client.post(
            "/api/auth/register",
            json={
                "username": username,
                "password": "TestPass123!",
                "role": "client",
            }
        )
        
        if resp.status_code in [200, 201]:
            data = resp.json()
            self.token = data.get("token") or data.get("access")
        else:
            # Tenter login avec utilisateur existant
            login_resp = self.client.post(
                "/api/auth/login",
                json={
                    "username": "test_client",
                    "password": "Secure123!",
                }
            )
            if login_resp.status_code == 200:
                data = login_resp.json()
                self.token = data.get("token") or data.get("access")

    @task(3)
    def liste_prestataires(self):
        """TP-01 : Liste des prestataires."""
        headers = {}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        
        self.client.get("/api/client/prestataires", headers=headers)

    @task(2)
    def liste_reservations(self):
        """TP-01 : Liste des reservations."""
        headers = {}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        
        self.client.get("/api/client/reservations/list", headers=headers)

    @task(1)
    def detail_reservation(self):
        """TP-01 : Detail d'une reservation."""
        headers = {}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        
        self.client.get("/api/client/reservations/RES-001/detail", headers=headers)

    @task(1)
    def home_client(self):
        """TP-01 : Home client."""
        headers = {}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        
        self.client.get("/api/client/home", headers=headers)

    @task(2)
    def flux_reservation_paiement(self):
        """FLUX CRITIQUE : creer reservation -> devis -> payer."""
        headers = {"Authorization": f"Bearer {self.token}"} if self.token else {}
        ref = f"PERF-{random_string(12)}"
        
        # Step 1: Creer reservation
        res = self.client.post(
            "/api/client/reservations/create",
            headers=headers,
            json={
                "prestataire": "Konan Jean",
                "category": 1,
                "title": f"Test mission {ref}",
                "description": "Mission de performance test",
                "address": "Abidjan Cocody",
            }
        )
        if res.status_code not in [200, 201]:
            return  # Skip si echec
        
        # Step 2: Confirmer devis (simule)
        res_id = res.json().get("reference", ref)
        devis = self.client.post(
            f"/api/prestataire/create-devis/{res_id}",
            headers=headers,
            json={
                "diagnostic": "Test devis",
                "date_proposee": "2026-05-01",
                "lignes": [
                    {"description": "Fournitures", "type_ligne": "FOURNITURE", "quantite": 1, "prix_unitaire": 5000},
                    {"description": "Main oeuvre", "type_ligne": "MAIN_OEUVRE", "quantite": 2, "prix_unitaire": 10000},
                ]
            }
        )
        
        # Step 3: Accepter devis
        accept = self.client.post(
            f"/api/client/accept-devis/{res_id}",
            headers=headers,
            json={"decision": "accept"}
        )
        
        # Step 4: Enregistrer paiement
        pay = self.client.post(
            f"/api/client/pay-post-prestation/{res_id}",
            headers=headers,
            json={
                "payment_method_id": "ESPECES",
                "message": "Paiement test performance",
            }
        )


class BabifixPrestataire(HttpUser):
    wait_time = between(2, 5)
    token = None

    def on_start(self):
        """Login prestataire."""
        resp = self.client.post(
            "/api/auth/login",
            json={
                "username": "test_prestataire",
                "password": "Secure123!",
            }
        )
        if resp.status_code == 200:
            data = resp.json()
            self.token = data.get("token") or data.get("access")

    @task(2)
    def liste_missions(self):
        """TP-01 : Liste des missions prestataire."""
        headers = {}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        
        self.client.get("/api/prestataire/requests", headers=headers)

    @task(1)
    def stats_prestataire(self):
        """TP-01 : Stats prestataire."""
        headers = {}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        
        self.client.get("/api/prestataire/stats/", headers=headers)

    @task(1)
    def earnings(self):
        """TP-01 : Revenus prestataire."""
        headers = {}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        
        self.client.get("/api/prestataire/earnings", headers=headers)


class BabifixAdmin(HttpUser):
    wait_time = between(5, 10)
    token = None

    def on_start(self):
        """Login admin."""
        resp = self.client.post(
            "/api/auth/login",
            json={
                "username": "admin",
                "password": "AdminPass123!",
            }
        )
        if resp.status_code == 200:
            data = resp.json()
            self.token = data.get("token") or data.get("access")

    @task(1)
    def dashboard(self):
        """TP-01 : Dashboard admin."""
        headers = {}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        
        self.client.get("/api/admin/dashboard/", headers=headers)

    @task(1)
    def liste_prestataires_admin(self):
        """TP-01 : Liste prestataires admin."""
        headers = {}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        
        self.client.get("/api/admin/prestataires/", headers=headers)


class BabifixPublic(HttpUser):
    """Utilisateurs publics (pas d'auth requise)."""
    wait_time = between(2, 5)

    @task(5)
    def categories(self):
        """Endpoints publics : categories (cache 5min)."""
        self.client.get("/api/public/categories/")

    @task(3)
    def payment_methods(self):
        """Endpoints publics : methodes paiement."""
        self.client.get("/api/public/payment-methods/")

    @task(2)
    def prestataires_public(self):
        """Endpoints publics : liste prestataires (paginee)."""
        self.client.get("/api/public/providers/?page=1&page_size=20")

    @task(1)
    def home_public(self):
        """Endpoints publics : home vitrine."""
        self.client.get("/api/home/")

    @task(1)
    def search_prestataires(self):
        """Recherche prestataire avec filtres."""
        self.client.get("/api/client/prestataires?q=plomberie&sort=rating&page=1")


# evenements pour tracking des failures
@events.request.add_listener
def on_request(request_type, name, response_time, response_length, response, context, exception, **kwargs):
    """Track les requetes lentes ou echouees."""
    if response and response.status_code >= 500:
        print(f"ERREUR SERVER: {request_type} {name} - Status {response.status_code}")
    elif response_time > 1000:
        print(f"LENT: {request_type} {name} - {response_time}ms")


@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    print("=== DEBUT TEST CHARGE BABIFIX ===")
    print(f"Host: {environment.host}")
    print("Endpoints critiques testes:")
    print("  - /api/public/categories/ (cache, haut traffic)")
    print("  - /api/client/prestataires/ (pagination)")
    print("  - Flux: reservation -> devis -> paiement")
    print("==========================")


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    print("=== FIN TEST CHARGE BABIFIX ===")
    print(f"Total requests: {environment.stats.total.num_requests}")
    print(f"Failures: {environment.stats.total.num_failures}")
    print(f"RPS moyen: {environment.stats.total.rps:.2f}")
