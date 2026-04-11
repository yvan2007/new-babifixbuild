# BABIFIX BUILD

**Important :** tout ce que vous lancez au quotidien doit être **ici** (`BABIFIX_BUILD`), pas dans le dossier parent `BABIFIX`.  
Le dossier `BABIFIX\APP&site web babifix\` (projets **React / Vite / .tsx**) est un **export séparé** : ce n’est **pas** la vitrine ni l’admin officiels. La vitrine et l’admin **production** sont en **Django + templates HTML** dans ce dépôt :
je vois
- `babifix_vitrine_django` — landing (Tailwind/CSS custom, Lucide CDN, pas de SPA React obligatoire).
- `babifix_admin_django` — panel + **API REST** consommée par les apps Flutter.

---

Ce dossier contient la reconstruction complete hors du dossier source `BABIFIX`, avec separation par type de produit :

- `babifix_client_flutter` : application mobile client (Flutter).
- `babifix_prestataire_flutter` : application mobile prestataire (Flutter).
- `babifix_admin_django` : panneau d'administration web (Django).
- `babifix_vitrine_django` : site vitrine web (Django).

**Rôle des 4 interfaces, admin (sans saisie clients/prestataires), FCFA & Mobile Money CI :**  
→ `docs/QUATRE_INTERFACES_ROLE_ADMIN_ET_PAIEMENTS_CI.md`  
**Spécification dynamique (zéro démo, PostgreSQL, KPI, logos) :**  
→ `docs/SPEC_OBJECTIFS_CI_DYNAMIQUE.md`  
**Panel admin** : recherche par section (`q=`), export CSV (`/export/csv/<kind>/`), rafraîchissement KPI **HTMX** sur le dashboard — voir la même spec.

## Lancer les projets

### 1) Application client Flutter
```bash
cd C:\Users\YVXN20\Downloads\BABIFIX_BUILD\babifix_client_flutter
flutter run
```

### 2) Application prestataire Flutter
```bash
cd C:\Users\YVXN20\Downloads\BABIFIX_BUILD\babifix_prestataire_flutter
flutter run
```

### 3) Admin Django (API + dashboard — port **8002** pour les apps Flutter)

Active un environnement virtuel qui contient **`daphne`**, **`channels`** et le reste du `requirements.txt` (évite d’utiliser le `.venv` de la vitrine sans avoir installé ces paquets) :

```bash
cd C:\Users\YVXN20\Downloads\BABIFIX_BUILD\babifix_admin_django
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
python manage.py runserver 0.0.0.0:8002
```

Si tu vois **`No module named 'daphne'`**, installe toutes les dépendances : **`pip install -r requirements.txt`** dans le **même** venv (`babifix_admin_django\.venv`).  
Base **MySQL (WAMP)**, utilisateur `root` sans mot de passe : voir **`docs/WAMP_MYSQL.md`** et le fichier **`babifix_admin_django/.env.example`** (`MYSQL_DATABASE`, etc.).

### 4) Site vitrine Django (autre port si l’admin tourne déjà sur 8002)

**Ordre recommandé :** démarrer d’abord l’**admin** sur le port **8002**, puis la **vitrine**.  
La vitrine appelle `http://127.0.0.1:8002/api/public/vitrine/` et `/api/public/categories/` (variable `BABIFIX_ADMIN_API_BASE`, défaut **8002** — aligné sur Flutter). Si l’admin n’est pas démarré, les catégories restent vides et un message d’aide s’affiche.

```bash
cd C:\Users\YVXN20\Downloads\BABIFIX_BUILD\babifix_vitrine_django
python manage.py migrate
python manage.py runserver 8003
```

Copiez `.env.example` vers `.env` si besoin et vérifiez `BABIFIX_ADMIN_API_BASE=http://127.0.0.1:8002`.

Guide détaillé Flutter / FCM / téléphone physique : **`docs/PARTIE_B_C_D_FLUTTER_DJANGO.md`**

### Le panel admin « ne change pas » ?

1. **Dossier** : l’interface décrite dans les docs est celle de **`BABIFIX_BUILD/babifix_admin_django`** (template `templates/adminpanel/dashboard.html`). Le dossier racine **`BABIFIX`** (sans `_BUILD`) ou l’app **React** « ADMIN BABIFIX » est un **autre** projet : les modifications n’y apparaissent pas.
2. **URL** : ouvre **`http://127.0.0.1:8002/`** (pas `0.0.0.0`) après `runserver` depuis **`babifix_admin_django`**.
3. **Cache** : rafraîchissement forcé (**Ctrl+F5**) — les fichiers statiques (`static/adminpanel/style.css`) peuvent être mis en cache.
4. **Repère visuel** : le panel mis à jour affiche une bannière violette **« Rôle administrateur (rappel) »**, le badge **🇨🇮 FCFA** en haut à droite, et en bas de barre latérale la ligne **« Build panel · CI / FCFA · fév. 2026 »**. Si tu ne les vois pas, ce n’est pas ce serveur / ce code.

## Verifications effectuees

- `flutter analyze` passe sur les 2 projets Flutter.
- `python manage.py check` passe sur les 2 projets Django.

## Adaptations globales BABIFIX

- Identite mobile harmonisee (suppression de `com.example`) :
  - Client : `com.babifix.client`
  - Prestataire : `com.babifix.prestataire`
- CTA du site vitrine relies a des routes dediees (`/telecharger-app-client`, `/devenir-prestataire`, `/creer-un-compte`).
- Configuration Django externalisee via variables d environnement :
  - `DJANGO_SECRET_KEY`
  - `DJANGO_DEBUG`
  - `DJANGO_ALLOWED_HOSTS`
- Fichiers `.env.example` et `requirements.txt` ajoutes dans :
  - `babifix_admin_django`
  - `babifix_vitrine_django`
