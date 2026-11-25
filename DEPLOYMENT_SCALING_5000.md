# Guide de Passage a l Echelle BABIFIX (5 000+ Utilisateurs & Pics Simultanes)

Ce document recapitule l architecture mise en place et les reglages indispensables en ligne (Render / VPS Docker + Nginx) pour garantir la stabilite RAM, la fluidite reseau, et la detection instantanee des erreurs.

---

## 1. Observabilite "Sante & Erreurs Live"

1. **Cockpit Admin** : section `?section=observability` dans le menu lateral ("Sante & Erreurs Live").
2. **Backend Django (`babifix_admin_django`)** : `BabifixObservabilityMiddleware` capture :
   * Toute exception 500 avec fichier et numero de ligne exacts (`source_file:source_line`) + traceback masqué.
   * Les reponses `4xx`/`5xx` suspectes ou echouees (hors scans automatiques de bots type `/wp-login.php`, `/.env`).
   * Toute requete depassant `BABIFIX_SLOW_REQUEST_MS` (defaut `800 ms`).
   * Chaque reponse expose `X-Request-ID` et `X-Response-Time-Ms`.
3. **Site Vitrine (`babifix_vitrine_django`)** : `BabifixVitrineObservabilityMiddleware` transmet les incidents et lenteurs vers `POST /api/telemetry/vitrine/` signe par `HMAC-SHA256` (`VITRINE_TELEMETRY_SECRET`, anti-rejeu 120s).
4. **Apps Flutter Client & Prestataire** : `BabifixErrorReporter` capture les exceptions UI/Zone non gerees ET toute requete HTTP `>= 500` ou `>= 1500 ms` vers `POST /api/app/log-error` (rate-limite 20/min/IP).
5. **Conformite Loi CI n° 2013-450** : tout mot de passe, PIN, JWT Bearer, cookie, CNI/selfie base64 est automatiquement remplace par `[MASQUE]` avant persistence dans `SystemEventLog`.

---

## 2. Optimisations RAM, SQL & Concurrence

| Goulot identifie (Avant) | Correction appliquee (Apres) | Gain |
|---|---|---|
| `_bootstrap_data()` appelant 8 `get_or_create` SQL a chaque requete API publique | Cache worker `babifix:bootstrapped:v1` (TTL 300s) | 0 requete SQL par hit |
| Chargement complet des colonnes `cni_*`, `selfie_url`, `video_intro_url`, `auto_check_result`, `before/after_photos` dans les listes `Provider` | `.defer(*PROVIDER_HEAVY_B64_FIELDS)` systematique sur toutes les listes | Empreinte RAM reduite sous charge |
| `api_public_providers` & `api_public_categories` frappant SQL + scoring + reseau Nominatim sur chaque GET | Cache versionne O(1) (`get_catalog_cache_version()` invalide sur `post_save`/`post_delete`) + lookup cache local geocode O(1) sans HTTP bloquant | Suppression blocage worker + RPS multiplie |
| `api_client_home` avec 3 requetes N+1 par reservation (`Rating`, `Devis`, `Payment`) | 3 requetes en masse (`in` / `select_related`) avant la boucle | De `3*N` SQL a `3` SQL fixes |
| `api_admin_financial_summary` bouclant tous les `Payment` + 8 `.count()` | Agregation SQL `Sum` + `.values("statut").annotate(cnt=Count("id"))` | Temps constant O(1) Python |
| Vitrine `home` non compresse (`258 Ko`) + 4 appels DB/API synchrones par vue | `GZipMiddleware` + cache `vitrine:home:editorial_ctx_v1` (60s) + SQLite WAL / Redis partage | Bande passante /~7 + reponses instantanees |
| SQLite lock en concurrence locale | `PRAGMA journal_mode=WAL; busy_timeout=5000;` a la connexion | Lectures/ecritures non bloquantes |

---

## 3. Dimensionnement Cible Production (5 000+ Utilisateurs)

### Pour 5 000 utilisateurs inscrits (jusqu a ~200 a 500 simultanes en pointe)
* **API Admin & WebSockets (`new-babifixbuild`)** : `Gunicorn + UvicornWorker`, `WEB_CONCURRENCY=3` a `4`, `--max-requests 1200` (recyclage memoire preventif), plan Render `standard` (2 Go RAM / 1 CPU) ou VPS 2 vCPU / 4 Go RAM.
* **Vitrine (`babifix-vitrine`)** : `Gunicorn --workers 2 --threads 4 --worker-class gthread`, plan Render `starter` minimum + `GZipMiddleware` (ou Cloudflare devant pour absorber 90% du trafic statique).
* **Base PostgreSQL** : plan manage `basic-1gb` minimum avec `DJANGO_CONN_MAX_AGE=60` (ou PgBouncer en transaction pooling si > 10 workers).
* **Redis** : indispensable en multi-worker pour partager le cache catalogue, les rate-limits (`throttle.py`) et les salons WebSocket Channels (en production, `LocMemCache` isole chaque worker et casse le throttling distribue).
* **Medias (`CLOUDINARY_URL`)** : obligatoire sur Render (disque ephemere) pour que photos portraits, portfolio et CNI ne saturent ni le disque ni la RAM Django.

### Variables d environnement critiques a verifier avant mise en ligne
1. `DJANGO_ENV=production`, `DJANGO_DEBUG=False`
2. `DJANGO_SECRET_KEY` (cle forte >= 50 caracteres), `JWT_SECRET_KEY`
3. `DATABASE_URL` (PostgreSQL SSL), `REDIS_URL`
4. `VITRINE_TELEMETRY_SECRET` (chaine aleatoire 32+ chars identique entre Admin et Vitrine)
5. `CLOUDINARY_URL`, `GENIUSPAY_PUBLIC_KEY` / `GENIUSPAY_SECRET_KEY` / `GENIUSPAY_SIMULATE=false`
6. `BABIFIX_SLOW_REQUEST_MS=800`
