# BABIFIX — Plateforme de Mise en Relation Prestataires & Clients

**BABIFIX** est une plateforme digitale ivoirienne connectant des clients à des prestataires de services qualifiés (plomberie, électricité, nettoyage, mécanique, etc.). Elle gère l'intégralité du cycle de vie d'une prestation : réservation, devis, paiement sécurisé, chat, appels, et litiges.

---

## 📦 Architecture du Projet

```
BABIFIX_BUILD/
├── babifix_admin_django/         ← Backend principal (Django REST API + Panel Admin)
├── babifix_client_flutter/       ← Application mobile client (Flutter)
├── babifix_prestataire_flutter/  ← Application mobile prestataire (Flutter)
├── babifix_shared/               ← Package Dart partagé
├── babifix_vitrine_django/       ← Site vitrine / page d'accueil publique
└── UML_DIAGRAMMES/               ← Diagrammes d'architecture (PlantUML)
```

### 🧩 Backend — `babifix_admin_django/`

| Technologie | Usage |
|-------------|-------|
| **Django 5.2** / Django REST Framework | API RESTful complète |
| **Django Channels 4.2** + Daphne | WebSocket temps réel (chat, notifications) |
| **Celery 5.4** | Tâches asynchrones (notifications, timeouts) |
| **PostgreSQL / MySQL / SQLite** | Base de données (selon environnement) |
| **Redis** | Cache, Channel Layer, Celery broker |
| **JWT (PyJWT)** | Authentification par tokens |
| **Firebase Admin SDK** | Notifications push FCM |
| **GeniusPay API** | Paiement Mobile Money (Wave, Orange Money, MTN MoMo) |
| **LiveKit Cloud** | Appels voix/vidéo |
| **HTMX + Alpine.js** | Interface d'administration dynamique |
| **Sentry** | Monitoring des erreurs |
| **ReportLab** | Génération de reçus PDF |

### 📱 Applications Mobile — `babifix_client_flutter` & `babifix_prestataire_flutter/`

| Technologie | Usage |
|-------------|-------|
| **Flutter ^3.8** (Dart ^3.8) | Framework cross-platform |
| **GoRouter** | Navigation et routage |
| **LiveKit Client ^2.7** | Appels audio/vidéo |
| **Firebase Messaging** | Notifications push |
| **flutter_dotenv** | Configuration par environnement |
| **web_socket_channel** | Communication WebSocket |
| **flutter_map + OpenStreetMap** | Cartographie et géolocalisation |
| **Google Sign-In / Apple Sign-In** | Authentification sociale |
| **Local Auth** | Authentification biométrique |
| **PDF + Printing** | Génération et impression de reçus |

---

## 🚀 Fonctionnalités Principales

### 🔐 Authentification & Comptes
- Inscription/connexion (email, Google, Apple)
- Profil client / prestataire
- KYC avec vérification automatique (CNI, selfie, vidéo)
- Authentification biométrique

### 📋 Réservations & Devis
1. **Client** : Crée une demande avec date, adresse, message et photos
2. **Prestataire** : Reçoit la demande → Accepte ou refuse
3. **Devis détaillé** : Le prestataire crée un devis structuré avec :
   - **Main-d'œuvre** (catégorie, description, tarif horaire, quantité)
   - **Fournitures** (nom, prix unitaire, quantité)
   - **Autres frais** (déplacement, location, etc.)
4. **Client** : Visualise le devis en format kanban → Accepte ou refuse avec message

### 💬 Messagerie Temps Réel
- Chat WebSocket avec indicateurs de saisie
- Messages texte, images, et messages système (devis, paiement, etc.)
- Notifications FCM hors-ligne
- Accès conditionné après acceptation du devis

### 📞 Appels Audio/Vidéo (LiveKit)
- Appels directs depuis le chat
- Signalisation WebSocket (sonnerie, acceptation, refus, fin d'appel)
- Historique des appels

### 💳 Paiements & Escrow
- **Mobile Money** via GeniusPay (Wave, Orange Money, MTN MoMo)
- **Espèces** avec flux de validation à 3 niveaux (client → prestataire → admin)
- **Commission 18 %** automatique prélevée sur chaque transaction
- **Système d'escrow** : les fonds sont bloqués jusqu'à la confirmation des travaux
- Reçus PDF générés automatiquement

### ⚙️ Exécution des Prestations
- **Démarrer** → Prestataire lance l'intervention
- **Terminer** → Prestataire marque comme terminée
- **Confirmer** → Client valide les travaux effectués
- **Noter** → Évaluation 1–5 étoiles avec commentaire

### 🏦 Portefeuille Prestataire
- Suivi des gains en temps réel
- Voir les fonds en attente (escrow) et disponibles
- Demandes de retrait

### ⚖️ Litiges
- Ouverture de litige avec preuves (photos)
- Réponse du prestataire
- Décision admin (remboursement, partage, libération)
- Clôture automatique après 7 jours d'inactivité

### 🛠️ Administration
- Dashboard complet avec statistiques
- Gestion des catégories, prestataires, réservations
- Diffusion de notifications push à tous les utilisateurs
- Export CSV, logs d'audit, actions groupées

---

## 🛠️ Installation & Développement

### Prérequis
- Python 3.12+
- Flutter SDK ^3.8
- MySQL / PostgreSQL (optionnel — SQLite par défaut en dev)
- Redis (optionnel — channel layer en mémoire par défaut)

### 🖥️ Backend Django

```bash
# 1. Cloner le projet
git clone https://github.com/yvan2007/new-babifixbuild.git
cd BABIFIX_BUILD/babifix_admin_django

# 2. Environnement virtuel
python -m venv venv
# Windows : venv\Scripts\activate
# Linux/Mac : source venv/bin/activate

# 3. Dépendances
pip install -r requirements.txt

# 4. Configuration
cp .env.example .env   # Adapter les variables

# 5. Base de données
python manage.py migrate

# 6. Données de démonstration (optionnel)
python manage.py seed_catalogue
python manage.py seed_demo_data

# 7. Lancer le serveur
python manage.py runserver 0.0.0.0:8002
```

Les WebSocket nécessitent Daphne :
```bash
daphne -b 0.0.0.0 -p 8002 config.asgi:application
```

### 📱 Application Flutter Client

```bash
cd babifix_client_flutter
flutter pub get
# Configurer .env (voir section Variables d'Environnement)
flutter run
```

### 📱 Application Flutter Prestataire

```bash
cd babifix_prestataire_flutter
flutter pub get
# Configurer .env
flutter run
```

### 🌐 Site Vitrine

```bash
cd babifix_vitrine_django
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python manage.py runserver 0.0.0.0:8001
```

---

## 🔑 Variables d'Environnement

### Backend — `babifix_admin_django/.env`

| Variable | Description | Requise |
|----------|-------------|---------|
| `DJANGO_SECRET_KEY` | Clé secrète Django | Oui |
| `DJANGO_DEBUG` | Mode debug (True/False) | Oui |
| `DATABASE_URL` | URL complète de la base de données | Prod |
| `POSTGRES_DB` / `USER` / `PASSWORD` / `HOST` / `PORT` | Config PostgreSQL | Alternative |
| `MYSQL_DATABASE` / `USER` / `PASSWORD` / `HOST` / `PORT` | Config MySQL | Alternative |
| `REDIS_URL` | URL Redis (Channels + Celery) | Prod |
| `GENIUSPAY_PUBLIC_KEY` | Clé publique GeniusPay | Oui |
| `GENIUSPAY_SECRET_KEY` | Clé secrète GeniusPay | Oui |
| `LIVEKIT_URL` | URL du serveur LiveKit | Oui |
| `LIVEKIT_API_KEY` | Clé API LiveKit | Oui |
| `LIVEKIT_API_SECRET` | Clé secrète LiveKit | Oui |
| `FIREBASE_PROJECT_ID` | Projet Firebase (FCM) | Oui |
| `FIREBASE_CREDENTIALS_JSON_PATH` | Chemin fichier credentials Firebase | Oui |
| `EMAIL_HOST_USER` | Adresse email SMTP | Oui |
| `EMAIL_HOST_PASSWORD` | Mot de passe SMTP | Oui |
| `SENTRY_DSN` | DSN Sentry (monitoring) | Optionnel |
| `DJANGO_SUPERUSER_EMAIL` | Email superadmin | Optionnel |
| `DJANGO_SUPERUSER_PASSWORD` | Mot de passe superadmin | Optionnel |

### Flutter — `babifix_client_flutter/.env` & `babifix_prestataire_flutter/.env`

| Variable | Description | Exemple (dev) |
|----------|-------------|---------------|
| `BABIFIX_API_BASE` | URL de l'API | `http://10.0.2.2:8002` |
| `BABIFIX_WS_BASE` | URL WebSocket | `ws://10.0.2.2:8002` |
| `LIVEKIT_URL` | URL LiveKit | `wss://babifix-h1giwqew.livekit.cloud` |
| `LIVEKIT_API_KEY` | Clé API LiveKit | `APIHmepmCSoou3K` |
| `LIVEKIT_API_SECRET` | Clé secrète LiveKit | `Cets7RORRaNS61Ie4dyCY0rE33lyzxTBrG7NYQifs6IA` |
| `BABIFIX_ENV` | Environnement | `development` |

---

## 🚢 Déploiement (Render)

Le projet est configuré pour Render via `babifix_admin_django/render.yaml` :

```yaml
services:
  - type: web
    name: babifix-api
    buildCommand: |
      pip install -r requirements.txt
      python manage.py collectstatic --no-input
      python manage.py migrate
    startCommand: daphne -b 0.0.0.0 -p $PORT config.asgi:application
```

**Services associés :**
- PostgreSQL (gratuit)
- Redis (gratuit)

**Endpoints de monitoring :**
- `GET /api/health/` — Santé du serveur
- `GET /api/admin/health/config` — Configuration actuelle

---

## 🧪 Tests

```bash
# Tests Django (backend)
cd babifix_admin_django
python manage.py test adminpanel.tests.test_phase_f_to_b12 -v 2

# Analyse Flutter
cd babifix_client_flutter
flutter analyze

cd babifix_prestataire_flutter
flutter analyze
```

---

## 📚 Ressources

- [Diagrammes UML](UML_DIAGRAMMES/README.md) — Architecture complète (19 diagrammes)
- [Guide de Migration](babifix_admin_django/MIGRATION_GUIDE.md) — Migrations Phase A → G
- [Plan de Refactoring Flutter](babifix_client_flutter/REFACTORING%20PLAN.md)
- **Swagger / OpenAPI** : `http://localhost:8002/api/docs/`

---

## 📄 Licence

Projet privé — Tous droits réservés © BABIFIX CI
