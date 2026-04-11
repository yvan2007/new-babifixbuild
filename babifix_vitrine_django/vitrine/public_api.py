import json
import os
import urllib.error
import urllib.request


def fetch_admin_public_vitrine():
    """Récupère le JSON public depuis babifix_admin_django."""
    # Aligné sur babifix_client_flutter (kBabifixApiPort = 8002) et README BABIFIX_BUILD.
    base = os.getenv('BABIFIX_ADMIN_API_BASE', 'http://127.0.0.1:8002').rstrip('/')
    url = f'{base}/api/public/vitrine/'
    try:
        with urllib.request.urlopen(url, timeout=4) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError):
        return {}


def fetch_admin_public_categories():
    """Catégories actives (aligné diagramme UML Categorie)."""
    base = os.getenv('BABIFIX_ADMIN_API_BASE', 'http://127.0.0.1:8002').rstrip('/')
    url = f'{base}/api/public/categories/'
    try:
        with urllib.request.urlopen(url, timeout=4) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError):
        return {'categories': []}
