# 🚀 BABIFIX — Guide de déploiement Render + apps sur vrai téléphone

> But de ce fichier : pouvoir passer du **local (émulateurs + PC)** à la **production
> (backend Render + apps sur de vrais téléphones)** sans rien casser, et en gardant
> exactement le même comportement qu'en local.
>
> Règle d'or : **le code ne change pas**. Ce qui change, c'est l'**environnement**
> (URL backend, base de données, variables d'env, mode paiement). Tout est déjà
> prévu dans le code — il suffit de bien aligner les réglages ci-dessous.

---

## 0. Architecture (rappel)

| Composant | Local (actuel) | Production (Render) |
|---|---|---|
| Backend Django | `manage.py runserver 0.0.0.0:8002` | `daphne` (ASGI) sur Render |
| Base de données | MySQL local | PostgreSQL Render |
| Temps réel (chat/appels/notifs) | Daphne local + Redis | Daphne + Redis Render |
| Fichiers médias (photos) | dossier `media/` du PC | ⚠️ voir §5 (disque éphémère) |
| App cliente | APK **debug** → `http://10.0.2.2:8002` | APK **release** → URL Render (auto) |
| App prestataire | APK **debug** → `http://10.0.2.2:8002` | APK **release** → URL Render (auto) |
| Paiement GeniusPay | sandbox auto-validé (`DEBUG=True`) | **réel** (`DEBUG=False`) |

Le **même code** tourne dans les deux cas. Le basculement d'URL est **automatique**
selon le type de build (voir §3).

---

## 1. ⚠️ À CORRIGER EN PREMIER : l'URL doit être cohérente partout

Aujourd'hui il y a un **décalage** :

| Endroit | Valeur actuelle |
|---|---|
| App Flutter (`babifix_client_flutter/lib/babifix_api_config.dart`, const `kBabifixProdUrl`) | `https://new-babifixbuild.onrender.com` |
| `render.yaml` (nom du service `babifix-api`) | déploierait sur `https://babifix-api.onrender.com` |
| `render.yaml` → `DJANGO_ALLOWED_HOSTS` | `babifix-api.onrender.com` |
| `render.yaml` → `GENIUSPAY_WEBHOOK_URL` | `https://babifix-api.onrender.com/api/paiements/geniuspay/webhook/` |
| `render.yaml` → `CORS_ALLOWED_ORIGINS` | `https://babifix-api.onrender.com` |

👉 **Choisis UNE seule URL** et mets-la partout. Deux options :

**Option A — garder `new-babifixbuild.onrender.com`** (l'URL déjà dans les apps)
- Dans `render.yaml` : remplacer les 3 valeurs `babifix-api.onrender.com` par `new-babifixbuild.onrender.com`
  (lignes `DJANGO_ALLOWED_HOSTS`, `GENIUSPAY_WEBHOOK_URL`, `CORS_ALLOWED_ORIGINS`).
- Rien à changer côté apps.

**Option B — garder `babifix-api.onrender.com`** (le nom du `render.yaml`)
- Dans les **deux** apps Flutter : changer `kBabifixProdUrl` →
  `'https://babifix-api.onrender.com'`
  - `babifix_client_flutter/lib/babifix_api_config.dart`
  - `babifix_prestataire_flutter/lib/babifix_api_config.dart`
- Rebuilder les apps en release.

> Note : `DJANGO_ALLOWED_HOSTS` est de toute façon complété automatiquement par
> Render via `RENDER_EXTERNAL_HOSTNAME` (voir `settings.py`), donc l'app répondra.
> Mais le **webhook GeniusPay** et le **CORS**, eux, doivent pointer sur la **vraie**
> URL — sinon les paiements et le panel web casseront. D'où l'importance d'aligner.

---

## 2. Backend sur Render — étape par étape

Ton `render.yaml` (Infrastructure as Code) crée tout d'un coup : service web + Postgres + Redis.

### 2.1 Première création (Blueprint)
1. Push le projet sur GitHub (le `render.yaml` est à la racine de `babifix_admin_django/`).
2. Sur Render → **New → Blueprint** → sélectionne le repo.
3. Render lit `render.yaml` et crée : `babifix-api` (web), `babifix-db` (Postgres), `babifix-redis`.

### 2.2 Commandes (déjà dans `render.yaml`)
- **Build** : `pip install -r requirements.txt && python manage.py collectstatic --no-input && python manage.py migrate`
- **Start** : `daphne -b 0.0.0.0 -p $PORT config.asgi:application`
  - ✅ `daphne` = serveur **ASGI** → le chat, les appels et les notifs temps réel marchent.
  - ❌ Ne PAS remplacer par `gunicorn config.wsgi` seul, sinon plus de temps réel.

### 2.3 Variables d'environnement (voir tableau complet §7)
- Celles marquées `sync: false` dans `render.yaml` **ne sont pas** dans le fichier :
  tu dois les saisir **à la main** dans le dashboard Render (secrets) :
  - `GENIUSPAY_PUBLIC_KEY`
  - `GENIUSPAY_SECRET_KEY`
  - `EMAIL_HOST_PASSWORD` (mot de passe d'application Gmail)
- `DJANGO_SECRET_KEY` est généré automatiquement (`generateValue: true`). 👍

### 2.4 Migrations + premier admin + données de base
Le `migrate` tourne au build. Ensuite, **une seule fois**, via le **Shell Render**
(onglet "Shell" du service) :
```bash
python manage.py createsuperuser          # crée ton compte admin
# (optionnel) python manage.py loaddata <fixture>  # si tu as un seed
```
> ⚠️ La base Render démarre **vide** : tes données de test locales (RES-069,
> e2e_presta, prestataires de test…) **n'y sont pas**. C'est normal — en prod,
> ce sont tes vraies données. `_bootstrap_data()` initialise certaines bases
> (catégories, méthodes de paiement) au premier appel API.

---

## 3. Apps Flutter — builder pour un vrai téléphone

### 3.1 Comment l'URL est choisie (déjà codé, rien à faire)
`babifix_api_config.dart` → `babifixApiBaseUrl()` décide dans cet ordre :
1. Override runtime (réglage in-app) — si présent
2. `--dart-define=BABIFIX_API_BASE=https://...` — override total
3. `BABIFIX_LOCAL_IP` (tél réel sur le Wi-Fi du PC, en dev)
4. **Build DEBUG** → `http://10.0.2.2:8002` (émulateur) / `localhost`
5. **Build RELEASE** sans override → `kBabifixProdUrl` (**Render**) ✅

➡️ **Donc pour un vrai téléphone en production : il suffit de builder en `--release`.**
Le WebSocket suit tout seul (`https` → `wss`).

> ⚠️ Les APK **debug** installés sur les émulateurs pointent sur `10.0.2.2` =
> une adresse qui n'existe QUE dans l'émulateur. **Sur un vrai téléphone, un APK
> debug ne se connecte à rien.** Il faut un build release (ou un dart-define).

### 3.2 Commandes de build (production)
```bash
# App cliente
cd babifix_client_flutter
flutter build apk --release
#   → build/app/outputs/flutter-apk/app-release.apk

# App prestataire
cd babifix_prestataire_flutter
flutter build apk --release
#   → build/app/outputs/flutter-apk/app-release.apk
```
Variante "forcer une URL précise" (utile pour tester un autre backend) :
```bash
flutter build apk --release --dart-define=BABIFIX_API_BASE=https://babifix-api.onrender.com
```
Pour le **Play Store**, builder un App Bundle signé :
```bash
flutter build appbundle --release
#   → nécessite une clé de signature (key.properties + keystore) — voir doc Flutter
```

### 3.3 Tester un vrai téléphone AVANT Render (optionnel)
Téléphone + PC sur le **même Wi-Fi**, puis :
```bash
flutter run --release --dart-define=BABIFIX_LOCAL_IP=192.168.X.X
```
(remplace par l'IP locale de ton PC ; le backend doit tourner en `0.0.0.0:8002`).

---

## 4. Paiements GeniusPay : sandbox (local) vs réel (prod)

- **Local** (`DJANGO_DEBUG=True`) → mode **sandbox** : les paiements sont
  **auto-validés** (référence `SANDBOX_...`). C'est ce que tu vois sur l'émulateur.
- **Prod** (`DJANGO_DEBUG=False` + clés GeniusPay présentes) → **paiements réels** :
  vraie demande Mobile Money (USSD), vrai argent, validation par **webhook**.

À vérifier en prod :
1. `GENIUSPAY_PUBLIC_KEY` et `GENIUSPAY_SECRET_KEY` saisies dans Render (secrets).
2. `GENIUSPAY_WEBHOOK_URL` = `https://<TON-URL>/api/paiements/geniuspay/webhook/`
   et **cette même URL configurée dans ton tableau de bord GeniusPay**.
3. Tester d'abord avec un **petit montant réel**.

> Base API GeniusPay (déjà dans le code) : `https://geniuspay.ci/api/v1/merchant`.

---

## 5. ⚠️ Médias (photos) — point critique en prod

Aujourd'hui : `MEDIA_ROOT = media/` sur le disque.
Sur Render (plan gratuit), **le disque est éphémère** → **les photos uploadées
(devis, avant/après, portraits) sont PERDUES à chaque redéploiement**.

Solutions (à choisir le jour du déploiement réel) :
- **Stockage objet** (recommandé) : AWS S3 / Cloudflare R2 / Cloudinary, via
  `django-storages`. Les uploads vont dans le cloud (persistants).
- **Disque persistant Render** : ajouter un *Disk* monté sur `media/` (payant).

> Le **static** (CSS/JS/images du panel) est déjà géré par **WhiteNoise**
> (`collectstatic` au build) → OK, rien à faire.

---

## 6. Différences local ↔ prod (récap)

| Aspect | Local émulateur | Render + vrai téléphone |
|---|---|---|
| Code / fonctionnalités | ✅ | ✅ identique |
| URL backend | `10.0.2.2:8002` (auto debug) | URL Render (auto release) |
| Base de données | MySQL local, tes données de test | Postgres Render, **vide au départ** |
| Paiements | sandbox auto-validé | **réels** (USSD + webhook) |
| Médias | disque PC | ⚠️ stockage externe requis |
| Temps réel | Daphne local + Redis | Daphne + Redis Render |
| `DEBUG` | `True` | `False` |
| Emails | console (dev) | SMTP Gmail (configuré) |

---

## 7. Tableau complet des variables d'environnement (Render)

| Variable | Rôle | Valeur prod | Source |
|---|---|---|---|
| `DJANGO_ENV` | Mode | `production` | render.yaml |
| `DJANGO_DEBUG` | Debug off | `False` | render.yaml |
| `DJANGO_SECRET_KEY` | Clé Django | (généré) | render.yaml `generateValue` |
| `DJANGO_ALLOWED_HOSTS` | Hôtes autorisés | **ton-url.onrender.com** | render.yaml (à aligner §1) |
| `DATABASE_URL` *(ou `POSTGRES_*`)* | Connexion DB | (auto) | `fromDatabase` |
| `POSTGRES_DB/USER/PASSWORD/HOST/PORT` | DB Postgres | (auto) | `fromDatabase` |
| `REDIS_URL` | Channels temps réel | (auto) | `fromService` |
| `GENIUSPAY_PUBLIC_KEY` | Paiement | 🔑 secret | **à saisir (sync:false)** |
| `GENIUSPAY_SECRET_KEY` | Signature HMAC | 🔑 secret | **à saisir (sync:false)** |
| `GENIUSPAY_WEBHOOK_URL` | Callback paiement | `https://<ton-url>/api/paiements/geniuspay/webhook/` | render.yaml (à aligner §1) |
| `CORS_ALLOWED_ORIGINS` | Panel web | `https://<ton-url>` | render.yaml (à aligner §1) |
| `EMAIL_BACKEND/HOST/PORT/USE_TLS` | Emails | SMTP Gmail | render.yaml |
| `EMAIL_HOST_USER` | Expéditeur | `kouayavana20@gmail.com` | render.yaml |
| `EMAIL_HOST_PASSWORD` | Mot de passe appli Gmail | 🔑 secret | **à saisir (sync:false)** |
| `DEFAULT_FROM_EMAIL` | From | `kouayavana20@gmail.com` | render.yaml |
| `FIREBASE_CREDENTIALS_JSON_PATH` *(ou `GOOGLE_APPLICATION_CREDENTIALS`)* | Push FCM | chemin du JSON | à ajouter si push prod |

> 🔒 **Jamais** de clés/secrets dans le code ou sur GitHub — uniquement en
> variables d'env Render. Le `.env` local reste gitignoré.

---

## 8. Checklist de mise en ligne (à cocher le jour J)

**Backend**
- [ ] URL unique choisie et alignée partout (§1)
- [ ] `render.yaml` poussé sur GitHub
- [ ] Blueprint créé sur Render (web + Postgres + Redis)
- [ ] `GENIUSPAY_PUBLIC_KEY`, `GENIUSPAY_SECRET_KEY`, `EMAIL_HOST_PASSWORD` saisies (secrets)
- [ ] Build OK (logs : `collectstatic` + `migrate` réussis)
- [ ] Start = `daphne ... config.asgi:application`
- [ ] `createsuperuser` fait via le Shell Render
- [ ] Webhook GeniusPay = URL Render, configuré aussi côté GeniusPay
- [ ] (Si photos en prod) stockage médias externe configuré (§5)

**Vérifications**
- [ ] `https://<ton-url>/` répond (panel admin accessible)
- [ ] `https://<ton-url>/api/public/providers/` renvoie du JSON
- [ ] Connexion app OK (login client + prestataire)
- [ ] Chat/notif temps réel OK (preuve que l'ASGI + Redis marchent)
- [ ] Un paiement test (petit montant réel) passe et le webhook valide

**Apps**
- [ ] `flutter build apk --release` (client) → installé sur le tél
- [ ] `flutter build apk --release` (prestataire) → installé sur le tél
- [ ] Parcours complet testé sur tél réel : réservation → devis → acompte →
      démarrer → terminer → confirmer → noter → reçu

---

## 9. Commandes utiles (mémo)

```bash
# --- Backend local (comme actuellement) ---
cd babifix_admin_django
python manage.py runserver 0.0.0.0:8002

# --- Builds apps (prod) ---
cd babifix_client_flutter && flutter build apk --release
cd babifix_prestataire_flutter && flutter build apk --release

# --- Install sur appareil branché en USB ---
flutter install                          # ou :
adb install -r build/app/outputs/flutter-apk/app-release.apk

# --- Sur Render (onglet Shell du service web) ---
python manage.py migrate
python manage.py createsuperuser
python manage.py collectstatic --no-input
```

---

*Dernière mise à jour : généré d'après l'état réel du projet
(`render.yaml`, `config/settings.py`, `babifix_api_config.dart`, `geniuspay.py`).*
*Le code n'a pas été modifié par ce guide — c'est une référence à utiliser le jour du déploiement.*
