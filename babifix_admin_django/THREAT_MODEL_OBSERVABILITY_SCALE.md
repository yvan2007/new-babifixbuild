# Modele de Menaces : Observabilite, Journalisation et Passage a l Echelle (5 000+ Utilisateurs)

**Projet** : Plateforme BABIFIX (Admin & API Django `babifix_admin_django`, Site Vitrine `babifix_vitrine_django`, Apps Flutter Client & Prestataire)  
**Date** : 2026-11-20  
**Referentiel** : Loi ivoirienne n° 2013-450 (protection des donnees a caractere personnel), OWASP Top 10 API Security (2023), Directives BABIFIX `security-workflow.md`

---

## 1. Perimetre et Actifs Critiques

| Actif | Sensibilite | Exposition |
|---|---|---|
| `SystemEventLog` (journal erreurs, latences, stacktraces) | Elevee (traces internes, endpoints, IP, IDs utilisateur) | Restreint Staff / Superuser uniquement (`?section=observability` et `/api/admin/observability/*`) |
| Collecteur Mobile `POST /api/app/log-error` | Moyenne (point d entree public pour apps Flutter) | Public avec rate-limiting strict, plafonnement taille et assainissement |
| Collecteur Vitrine `POST /api/telemetry/vitrine/` | Elevee (ingestion serveur a serveur) | Authentifie par signature HMAC-SHA256 + timestamp (ou secret interne), refuse hors signature |
| Endpoints Health (`/api/health/`, `/healthz/`) | Faible (etat DB/Redis/RAM) | Public leger sans secret ni version critique detaillee ; metriques detaillees reservees Admin |
| Cache catalogue (`api_public_providers`, `api_public_categories`, Vitrine `home`) | Moyenne (integrite affichage public) | Lecture publique ; invalidation uniquement via signaux ORM / mutations authentifiees |
| Base de donnees & Pool Connexions (SQLite WAL dev / Postgres + PgBouncer + Redis prod) | Critique | Interne serveur uniquement |

---

## 2. Surfaces d Attaque et Mesures de Mitigation

### M1 : Fuite de donnees personnelles et secrets dans les journaux (`SystemEventLog`)
* **Menace** : Une requete echouee (`4xx`/`5xx`) ou un crash Flutter pourrait enregistrer un mot de passe, code PIN, jeton JWT/Bearer, cle API, photo CNI/selfie base64, ou cookie de session dans `payload_redacted`, `traceback_text` ou `user_agent`. Violation directe de la Loi n° 2013-450 et d OWASP API3/API9.
* **Mitigation** :
  1. Service centralise `adminpanel/services/observability_service.py` appliquant une **redaction systematique (`[MASQUE]`)** sur :
     * Tout en-tete HTTP `Authorization`, `Cookie`, `Set-Cookie`, `X-Api-Key`, `X-Vitrine-Signature`.
     * Toute cle JSON/query correspondant a `password`, `passwd`, `pin`, `secret`, `token`, `access`, `refresh`, `jwt`, `cni`, `recto`, `verso`, `selfie`, `casier`, `certificat`, `signature`, `cvv`, `otp`.
     * Toute chaine ressemblant a un Bearer JWT (`eyJ...`), base64 volumineux (> 120 chars), ou numero de carte/compte.
  2. Masquage partiel des IP/emails si necessaire et tronquage strict des payloads (max 1 500 caracteres apres masquage) et tracebacks (max 4 000 caracteres).
  3. Zero donnee de paiement brut ni piece d identite stockee dans `SystemEventLog`.

### M2 : Saturation DB / Disque par inondation de logs (Log Flooding / DoS)
* **Menace** : Un attaquant envoie des milliers de requetes sur `/api/app/log-error` ou provoque en boucle des `404`/`400` pour remplir PostgreSQL/SQLite ou saturer l I/O.
* **Mitigation** :
  1. `/api/app/log-error` garde `check_rate_limit(request, "log_error", max_requests=20, window=60)` et deduplique les événements identiques (`fingerprint` + fenetre de 60s : incremente `occurrence_count` au lieu d inserer N lignes).
  2. Les requetes `404` repetitives sur scans de bots (`/wp-login.php`, `/.env`, `/.git`) ne doivent pas saturer le journal : deduplication par signature ou exclusion/echantillonnage des scans de fichiers statiques evidents tout en conservant le blocage securite.
  3. Plafond de taille de requete et purge automatique / bouton admin de purge (> 30 jours) + politique de retention cappee (ex: conservation max 30 jours ou 20 000 entrees).

### M3 : Usurpation de telemetrie Vitrine (`POST /api/telemetry/vitrine/`)
* **Menace** : Un tiers tente d injecter de fausses erreurs Vitrine vers Admin pour polluer le cockpit ou declencher de fausses alertes.
* **Mitigation** :
  1. Signature HMAC-SHA256 sur `timestamp + "." + body` avec cle partagee (`VITRINE_TELEMETRY_SECRET` ou derivee de `SECRET_KEY` en environnement local explicitement configure), verification en temps constant (`hmac.compare_digest`), fenetre anti-rejeu de 120 secondes.
  2. Rejet HTTP `403` si signature absente ou invalide.

### M4 : Exposition d informations internes aux clients (OWASP A05 Security Misconfiguration)
* **Menace** : En voulant aider le dirigeant a voir "l erreur exacte", les reponses JSON/HTML publiques exposeraient le `file:line` ou le traceback aux attaquants.
* **Mitigation** :
  1. **Separation stricte interne / externe** : le client externe recoit un message propre et generique avec uniquement un `request_id` de correlation (`X-Request-ID`).
  2. L erreur exacte (`exception_type`, `source_file`, `source_line`, `traceback_text`, `duration_ms`, `memory_mb`) est enregistree exclusivement en base pour le Cockpit Admin authentifie (`is_staff` / `is_superuser`).
  3. L acces a `?section=observability` et `/api/admin/observability/*` exige `@login_required` + `is_staff`/`is_superuser` + protection CSRF sur toute action d ecriture (`resolve`, `purge`).

### M5 : Empoisonnement de cache ou fuite inter-utilisateurs
* **Menace** : Mettre en cache des vues contenant des donnees specifiques a un utilisateur (`api_client_home`, `dashboard`).
* **Mitigation** :
  1. **Regle d or** : seuls les endpoints publics anonymes et identiques pour tous (`api_public_categories`, `api_public_providers` sans parametres prives, Vitrine `home` hors jetons CSRF individuels) utilisent le cache partage.
  2. `vitrine/home` : cacher le **contexte JSON / fragment catalogue** (pas le formulaire avec `{% csrf_token %}` si un token CSRF existe sur la page), afin que chaque utilisateur garde son propre cookie/token CSRF intact.
  3. Invalidation automatique sur signaux Django `post_save`/`post_delete` des modeles `Provider`, `ServiceCategory`, `SiteContent`, `SystemSetting`.

### M6 : Epuisement RAM, SQLite Lock et Connexions DB a 5 000+ utilisateurs
* **Menace** :
  1. Chargement des colonnes base64 CNI/selfie dans les listes `Provider` -> explosion RAM (+111 MB pour 100 requetes).
  2. Requetes N+1 et `_bootstrap_data()` execute sur chaque requete -> contention SQLite (`database is locked`) ou saturation pool Postgres.
  3. Appels synchrones HTTP Nominatim dans la boucle catalogue -> blocage workers.
* **Mitigation** :
  1. `.defer(*PROVIDER_HEAVY_B64_FIELDS)` obligatoire sur toutes les requetes de listing `Provider`.
  2. `_bootstrap_data()` mis en cache par worker (`_BOOTSTRAPPED` + cache) pour ne s executer qu une fois.
  3. SQLite configure avec `PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA busy_timeout=5000;` en dev ; PostgreSQL `CONN_MAX_AGE=60` / PgBouncer + Redis partage en prod.
  4. Requetes agregees SQL (`Sum`, `Count`, `prefetch_related` / bulk `in_bulk`) et suppression des appels Nominatim synchrones dans les endpoints chauds.
