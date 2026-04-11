# BABIFIX — Objectifs production (CI, FCFA, 4 interfaces, zéro démo)

Ce document aligne le dépôt **`BABIFIX_BUILD`** sur les exigences métier et techniques (Objectif 2 : **Django** + Flutter).

## Principes

1. **Aucune donnée de démo en base** par défaut : le seed optionnel est **`BABIFIX_ENABLE_DEMO_SEED=1`** (tests locaux uniquement).
2. **Montants** : francs CFA (**XOF**), affichage **`12 500 FCFA`** (espaces fines entre milliers côté Django `format_fcfa` / Flutter `formatFcfa`).
3. **Fuseau & langue** : `Africa/Abidjan`, interface **français** (messages d’erreur à harmoniser progressivement).
4. **Quatre interfaces** : app client Flutter, app prestataire Flutter, vitrine Django, panel admin Django (API + WebSocket + FCM push).
5. **Administrateur** : ne crée pas clients/prestataires « à la main » comme guichet ; le panel masque l’ajout direct (formulaires réservés au support / correction). Catégories, paramètres, validation des dossiers, paiements, stats.
6. **Discussions privées** : non exposées dans le panel admin (règle métier).

## Stack retenue (Objectif 2)

| Composant | Technologie |
|-----------|-------------|
| API + temps réel | Django 5.x, **Django Channels**, Redis (ou InMemory en dev) |
| Base | SQLite (dev) ou **PostgreSQL** (`POSTGRES_*` dans `.env`) |
| Panel + vitrine | Templates Django, CSS, **Alpine.js**, **Chart.js** (KPI), mode clair/sombre |
| Mobile | Deux apps Flutter (client / prestataire) — **flavors** : évolution possible (un seul repo) |
| Push | **FCM** (voir `docs/FCM_SETUP.md`) |

**Implémenté dans le panel admin (`babifix_admin_django`)** :
- **HTMX** : fragment KPI (`partial=stats`) rafraîchi toutes les ~60 s sur la section Dashboard ; indicateur visuel ; graphique Chart.js réinitialisé après swap.
- **Recherche** : champ « Filtrer cette section » (`q=`) sur chaque section (filtre sur les champs principaux des listes).
- **Export CSV** : `GET /export/csv/<kind>/` avec `kind` ∈ `reservations`, `payments`, `providers`, `clients`, `litiges`, `categories` ; paramètre optionnel `q=` pour reprendre le filtre.

**Roadmap (hors périmètre code actuel)** : build **Tailwind 3** dédié (voir `babifix_admin_django/static_src/tailwind/README.md` si présent), **django-allauth** + **OTP SMS** (fournisseur CI), **agrégateur de paiement** réel (CinetPay, etc.), **un seul repo Flutter + flavors** (guide `docs/FLUTTER_FLAVORS.md`).

## Fichiers importants

- Logos paiement (placeholders + README) : `babifix_admin_django/static/payment-logos/`
- Filtre monnaie : `adminpanel/templatetags/babifix_tags.py`
- Services API sans fallback fictif : `adminpanel/views.py` → `_services_from_db()`

## Prestataire Flutter — session

- Jeton JWT : clé partagée **`babifix_api_token`** (SharedPreferences).
- Écran **Connexion** après l’étape « validation » : l’utilisateur saisit identifiants **créés côté serveur** (compte Django + profil prestataire).

## Vérifications

```bash
cd babifix_admin_django
python manage.py check
python manage.py migrate
```

PostgreSQL (exemple) :

```env
POSTGRES_DB=babifix
POSTGRES_USER=babifix
POSTGRES_PASSWORD=secret
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
```
