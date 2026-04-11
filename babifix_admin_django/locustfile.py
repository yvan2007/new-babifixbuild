# locustfile.py — Tests de performance BABIFIX
"""
Tests de performance avec Locust
Usage : locust -f locustfile.py --host=http://localhost:8000
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
        """Login au début de chaque session utilisateur."""
        username = f"testuser_{random_string()}"
        
        # Créer un utilisateur de test (ou utiliser un existant)
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
        """TP-01 : Liste des réservations."""
        headers = {}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        
        self.client.get("/api/client/reservations/list", headers=headers)

    @task(1)
    def detail_reservation(self):
        """TP-01 : Détail d'une réservation."""
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


# Événements pour tracking des failures
@events.request.add_listener
def on_request(request_type, name, response_time, response_length, response, context, exception, **kwargs):
    """Track les requêtes lentes ou échouées."""
    if response and response.status_code >= 500:
        print(f"ERREUR SERVER: {request_type} {name} - Status {response.status_code}")
    elif response_time > 1000:
        print(f"LENT: {request_type} {name} - {response_time}ms")
