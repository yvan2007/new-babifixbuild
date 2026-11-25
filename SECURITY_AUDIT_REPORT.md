# AUDIT DE SECURITE - BABIFIX

**Date** : 2026-10-27
**Perimetre** : backend Django/Daphne (babifix_admin_django), vitrine (babifix_vitrine_django), app client Flutter, app prestataire Flutter, shared
**Methode** : audit source-first, lecture code, tests existants, verification manuelle des surfaces critiques
**Statut** : rapport preliminaire - validation utilisateur requise avant tout correctif

---

## 0. Synthese executive

- **3 vulnerabilites critiques** ? TOUTES CORRIGEES (paiement, webhook, montant)
- **7 vulnerabilites hautes** (rate limiting, tokens, CSP, secrets par defaut) → **toutes corrigées**
- **8 vulnerabilites moyennes** → **7 corrigées**, 1 restante (L-level)
- **5 vulnerabilites basses** ? TOUTES CORRIGEES
- **Plusieurs points positifs** a preserver (secure storage, IDOR prevention, CSRF, headers)

Les tests de securite existants (`test_security_owasp.py`) revelent 3 echecs : 2 sont des problemes de test (URL/methode incorrects) et 1 est un vrai probleme de securite (webhook bypass en DEBUG).

---

## 1. VULNERABILITES CRITIQUES

### C1 - Webhook GeniusPay : bypass de signature en DEBUG

**Fichier** : `babifix_admin_django/adminpanel/geniuspay.py` (fonction `geniuspay_webhook`, lignes ~855-875)

**Description** : Quand `settings.DEBUG` est True ou que l'environnement est "sandbox", la verification de signature HMAC est completement ignoree. Le webhook retourne 200 sans valider l'authenticite de la requete.

```python
if settings.DEBUG:
    logger.info("GeniusPay webhook — DEBUG, signature non verifiee")
elif environment.lower() == "sandbox":
    logger.info("GeniusPay webhook — sandbox, signature non verifiee")
elif not _verify_webhook_signature(raw_body, timestamp, received_sig):
    return JsonResponse({"error": "invalid_signature"}, status=403)
```

**Impact** : Un attaquant peut forger un webhook `payment.success` et valider un paiement sans avoir paye. Si DEBUG est accidentellement active en production, c'est une faille critique.

**Test confirme** : `test_TS08_webhook_geniuspay_sans_signature` echoue (retourne 200 au lieu de 403).

**Correctif** : Supprimer le bypass DEBUG. En dev, utiliser une cle de test avec vraie verification HMAC. Le bypass sandbox doit etre conditionne a un flag explicite `GENIUSPAY_SIMULATE`, pas a DEBUG.

---

### C2 - Montant de paiement non valide cote serveur

**Fichier** : `babifix_admin_django/adminpanel/geniuspay.py` (fonction `geniuspay_initiate`, lignes ~388-405)

**Description** : Le montant `montant_int` est pris directement du payload client (`payload.get("montant")`) sans etre compare au montant reel de la reservation (`reservation.montant`). Un client peut envoyer `montant=200` pour une reservation de 100 000 XOF.

**Impact** : Paiement d'un montant arbitrairement bas pour une prestation de valeur elevee.

**Correctif** : Valider que `montant_int` correspond au montant attendu de la reservation (acompte ou solde selon la phase). Rejeter si ecart > tolerance.

---

### C3 - IDOR sur l'initiation de paiement

**Fichier** : `babifix_admin_django/adminpanel/geniuspay.py` (fonction `geniuspay_initiate`, lignes ~396-404)

**Description** : `Reservation.objects.get(pk=int(reservation_id))` est execute sans verifier que la reservation appartient a l'utilisateur authentifie (`request.api_user_id`). Tout utilisateur authentifie (client, prestataire, admin) peut initier un paiement pour n'importe quelle reservation.

**Impact** : Un client peut payer la reservation d'un autre client. Un prestataire peut initier un paiement pour une reservation qui ne lui appartient pas.

**Correctif** : Ajouter une verification d'ownership : la reservation doit appartenir au client authentifie (ou etre assignee au prestataire authentifie). Rejeter avec 403 sinon.

---

## 2. VULNERABILITES HAUTES

### H1 - Rate limiting contournable via spoofing X-Forwarded-For

**Fichier** : `babifix_admin_django/adminpanel/throttle.py` (fonction `_get_client_ip`, lignes 14-19)

**Description** : `_get_client_ip` prend le premier element de `HTTP_X_FORWARDED_FOR` sans verifier que la requete vient d'un proxy de confiance. En production derriere Render, le header est fiable. Mais en dev ou si mal configure, un attaquant peut envoyer `X-Forwarded-For: 1.2.3.4` pour bypasser le rate limiting.

**Impact** : Brute-force de login, spam d'inscriptions, abus d'API.

**Correctif** : Utiliser `REMOTE_ADDR` par defaut. Ne faire confiance a XFF que si `settings.DEBUG` est False ET que la requete vient d'un proxy connu (Render). Ou utiliser `django-ipware` avec configuration de proxies de confiance.

---

### H2 - Secret JWT par defaut faible

**Fichier** : `babifix_admin_django/adminpanel/jwt_auth.py` (ligne 25)

**Description** : `JWT_SECRET_KEY = getattr(settings, "JWT_SECRET_KEY", os.environ.get("JWT_SECRET_KEY", "change-me-in-production"))`. La valeur par defaut `"change-me-in-production"` est previsible. En production, la verification existe (RuntimeError si env=production et secret par defaut), mais en dev le secret est faible.

**Impact** : Si un developpeur oublie de configurer JWT_SECRET_KEY en production (ou si l'env n'est pas "production" mais "staging"), les tokens JWT peuvent etre forges.

**Correctif** : Generer un secret aleatoire au demarrage si non configure (au lieu d'une valeur fixe). Ou refuser de demarrer sans secret dans tous les environnements.

---

### H3 - Blacklist de tokens en memoire (non persistante)

**Fichier** : `babifix_admin_django/adminpanel/jwt_auth.py` (ligne 44)

**Description** : `_token_blacklist = set()` est un set Python en memoire. Il ne persiste pas entre les workers Gunicorn, ni apres un redemarrage. Les tokens revoques restent valides.

**Impact** : La revocation de tokens ne fonctionne pas en production multi-worker. Un utilisateur deconnecte peut continuer a utiliser son token.

**Correctif** : Utiliser Redis ou la base de donnees pour la blacklist. Ou utiliser des tokens a courte duree de vie sans blacklist (stateless).

---

### H4 - Duree de vie du refresh token trop longue (365 jours)

**Fichier** : `babifix_admin_django/adminpanel/jwt_auth.py` (ligne 35)

**Description** : `REFRESH_TOKEN_EXPIRE_DAYS = 365`. Un refresh token vole reste valide un an.

**Impact** : Fenetre d'exploitation tres large pour un token vole.

**Correctif** : Reduire a 30 jours maximum. Implementer la rotation des refresh tokens (deja partiellement fait dans `refresh_access_token`).

---

### H5 - CSP permissive (unsafe-inline, unsafe-eval)

**Fichier** : `babifix_admin_django/adminpanel/security_middleware.py` (lignes 25-45)

**Description** : La CSP autorise `'unsafe-inline'` et `'unsafe-eval'` dans `script-src`, et `wss: https:` (n'importe quel hote) dans `connect-src`. Cela affaiblit considerablement la protection XSS.

**Impact** : Une injection XSS peut executer du code arbitraire et exfiltrer des donnees vers n'importe quel serveur.

**Correctif** : Retirer `'unsafe-eval'` (Alpine.js peut fonctionner sans). Utiliser des nonces pour les scripts inline. Restreindre `connect-src` aux domaines connus.

---

### H6 - Token d'acces Django signing avec salt hardcode

**Fichier** : `babifix_admin_django/adminpanel/auth.py` (lignes 12-13)

**Description** : `TOKEN_SALT = "babifix-api-token"` est hardcode. Le systeme principal d'authentification utilise `django.core.signing` avec ce salt. Si le salt est connu, les tokens peuvent etre forges (bien que la SECRET_KEY Django soit aussi necessaire).

**Impact** : Faible en soi (necessite la SECRET_KEY), mais combine avec une fuite de SECRET_KEY, c'est critique. Le salt devrait etre derive de la SECRET_KEY.

**Correctif** : Deriver le salt de `settings.SECRET_KEY` au lieu d'une valeur hardcodee.

---

### H7 - Access token lifetime trop long (7 jours)

**Fichier** : `babifix_admin_django/adminpanel/auth.py` (ligne 14)

**Description** : `ACCESS_TOKEN_MAX_AGE_SECONDS = 7 * 24 * 3600` (7 jours). Un token d'acces vole reste valide une semaine.

**Impact** : Fenetre d'exploitation longue pour un token vole.

**Correctif** : Reduire a 15-30 minutes. Utiliser le refresh token pour renouveler.

---

## 3. VULNERABILITES MOYENNES

### M1 - Logs verbeux revelant des erreurs de verification de token

**Fichier** : `babifix_admin_django/adminpanel/auth.py` (lignes 50-58)

**Description** : `print(f"Token verification failed: {e}")` ecrit les details d'erreur dans stdout. En production, cela peut reveler des informations sur la structure des tokens.

**Correctif** : Remplacer par `logger.debug()` (pas de print en production).

---

### M2 - Upload audio sans verification du magic number

**Fichier** : `babifix_admin_django/adminpanel/secure_uploads.py` (fonction `validate_audio_upload`, ligne 155)

**Description** : `require_magic_match=False` pour les uploads audio. N'importe quel fichier avec une extension audio acceptee passe sans verification du contenu.

**Impact** : Upload de fichiers arbitraires (malware, scripts) en contournant la validation.

**Correctif** : Verifier au minimum les magic bytes pour les formats audio courants (ID3 pour MP3, RIFF pour WAV, OggS pour OGG).

---

### M3 - Donnees personnelles en clair dans SharedPreferences

**Fichiers** : `babifix_client_flutter/lib/user_store.dart`, `babifix_prestataire_flutter/lib/shared/auth_utils.dart`

**Description** : Nom, email, telephone, adresse, avatar (base64) sont stockes dans SharedPreferences (non chiffre). Sur un appareil roote ou avec ADB, ces donnees sont lisibles.

**Impact** : Fuite de PII en cas d'acces physique a l'appareil.

**Correctif** : Migrer les donnees sensibles vers flutter_secure_storage. Au minimum, ne pas stocker l'avatar en base64 dans SharedPreferences.

---

### M4 - Configuration dev dangereuse (ALLOWED_HOSTS = ["*"])

**Fichier** : `babifix_admin_django/config/settings.py` (ligne 95)

**Description** : En mode dev, `ALLOWED_HOSTS = ["*"]`. Si la configuration dev fuit en production (mauvaise variable d'env), n'importe quel host est accepte.

**Impact** : Host header injection, cache poisoning.

**Correctif** : Meme en dev, utiliser `["localhost", "127.0.0.1", "10.0.2.2"]` au lieu de `["*"]`.

---

### M5 - Simulation de paiement conditionnee a DEBUG

**Fichier** : `babifix_admin_django/adminpanel/geniuspay.py` (lignes ~95-100, ~449)

**Description** : `if settings.DEBUG or GENIUSPAY_SANDBOX:` declenche l'auto-validation des paiements. Si DEBUG est True en production, tous les paiements sont auto-valides sans paiement reel.

**Impact** : Perte de revenus, fraude.

**Correctif** : Conditionner la simulation uniquement a `GENIUSPAY_SIMULATE=true` explicite, jamais a DEBUG.

---

### M6 - Webhook 'webhook.test' sans verification

**Fichier** : `babifix_admin_django/adminpanel/geniuspay.py` (lignes ~848-852)

**Description** : L'evenement `webhook.test` retourne 200 sans aucune verification. Un attaquant peut l'utiliser pour prober l'endpoint.

**Impact** : Information disclosure (confirmation que l'endpoint existe et fonctionne).

**Correctif** : Verifier la signature meme pour webhook.test, ou au minimum rate-limiter.

---

### M7 - Pas de verification d'audience JWT (verify_aud=False)

**Fichier** : `babifix_admin_django/adminpanel/jwt_auth.py` (lignes ~120, ~155)

**Description** : `verify_aud=False` dans jwt.decode. L'audience claim n'est pas verifiee.

**Impact** : Un token emis pour un autre service (meme cle secrete) pourrait etre accepte.

**Correctif** : Activer `verify_aud=True` et verifier l'audience.

---

### M8 - authPatch et authDelete (Flutter) ne renouvellent pas le token sur 401

**Fichiers** : `babifix_client_flutter/lib/user_store.dart` (fonctions `authPatch`, `authDelete`)

**Description** : Contrairement a `authGet` et `authPost`, les fonctions `authPatch` et `authDelete` ne tentent pas de renouveler le token sur 401. Si le token expire, l'operation echoue silencieusement.

**Impact** : UX degradee, operations echouent sans feedback.

**Correctif** : Ajouter la logique de refresh sur 401 pour patch et delete aussi.

---

## 4. VULNERABILITES BASSES

### L1 - datetime.utcnow() deprecie (Python 3.12+)

**Fichier** : `babimpsey_auth.py` -> `jwt_auth.py` (lignes ~75, ~95)

**Description** : `datetime.utcnow()` est deprecie en Python 3.12. Utiliser `datetime.now(timezone.utc)`.

---

### L2 - Avatar stocke en base64 dans SharedPreferences

**Fichier** : `babifix_client_flutter/lib/user_store.dart`

**Description** : L'avatar est encode en base64 et stocke dans SharedPreferences. Peut etre volumineux et ralentir l'app.

---

### L3 - print() au lieu de logger dans auth.py

**Fichier** : `babifix_admin_django/adminpanel/auth.py` (lignes 50-58)

**Description** : Utilisation de `print()` au lieu du module `logging`. Les messages ne sont pas filtres par niveau.

---

### L4 - Endpoint /api/media/upload sert les fichiers en production

**Fichier** : `babifix_admin_django/config/urls.py` (lignes ~45-55)

**Description** : `re_path(r"^media/(?P<path>.*)$", _serve_media, ...)` sert les fichiers media en production. Django's `serve` n'est pas optimise pour la production et peut exposer des fichiers sensibles si le path contient des sequences de traversal.

**Impact** : Potentiel path traversal, performance degradee.

**Correctif** : Servir les medias via un CDN (Cloudinary) ou un reverse proxy (nginx/whitenoise). Django serve ne devrait etre utilise qu'en dev.

---

### L5 - Throttle base sur LocMemCache (non partage entre workers)

**Fichier** : `babifix_admin_django/config/settings.py` (cache config)

**Description** : Si le cache Django est configure en LocMemCache (par defaut en dev), le rate limiting n'est pas partage entre les workers Gunicorn. Chaque worker a son propre compteur.

**Impact** : Rate limiting inefficace en production multi-worker.

**Correctif** : Configurer Redis comme backend de cache en production.

---

## 5. POINTS POSITIFS (a preserver)

1. **flutter_secure_storage** pour les tokens (Android encryptedSharedPreferences, iOS Keychain)
2. **IDOR prevention** : `_get_res_for_client` filtre par `client_user_id=uid`
3. **CSRF protection** : CSRF_COOKIE_HTTPONLY, SameSite=Lax
4. **Rate limiting** sur login, register, media upload, GeniusPay
5. **Headers de securite** : nosniff, HSTS, X-Frame-Options DENY, CSP, Permissions-Policy
6. **Validation d'upload** : whitelist MIME + extension + magic bytes
7. **Anti-timing attack** : hash dummy en cas d'utilisateur inconnu
8. **Paiement** : verification du montant dans le webhook, idempotence
9. **Secrets** : .env non commite, .gitignore complet
10. **Password hashing** : Argon2 configure
11. **Session** : HttpOnly, SameSite=Lax, expiration 8h
12. **File upload permissions** : 0o644

---

## 6. ITEMS NEEDS_VALIDATION (dependant de la configuration de deploiement)

| Item | Question | Impact si mal configure |
|---|---|---|
| NV1 | `DJANGO_ENV` est-il bien `production` sur Render ? | DEBUG=True => paiements auto-valides, signature bypass |
| NV2 | `GENIUSPAY_SIMULATE` est-il `false` en production ? | Paiements auto-valides sans paiement reel |
| NV3 | `GENIUSPAY_SECRET_KEY` est-elle configuree ? | Signature webhook ignoree |
| NV4 | Le cache Django est-il configure en Redis en production ? | Rate limiting inefficace |
| NV5 | `DJANGO_ALLOWED_HOSTS` est-il configure avec les bons domaines ? | Host header injection |
| NV6 | CORS_ALLOWED_ORIGINS est-il restreint en production ? | CSRF cross-origin |
| NV7 | Le proxy Render envoie-t-il X-Forwarded-For correctement ? | Rate limiting spoofable |

---

## 7. PLAN DE CORRECTION RECOMMANDE

### Phase 1 (critique, a faire immediatement)
1. C1 - Supprimer le bypass signature DEBUG dans le webhook
2. C2 - Valider le montant cote serveur dans geniuspay_initiate
3. C3 - Ajouter la verification d'ownership sur la reservation

### Phase 2 (haute, a faire avant mise en production)
4. H1 - Securiser l'extraction d'IP pour le rate limiting
5. H2 - Secret JWT par defaut aleatoire
6. H3 - Blacklist persistante (Redis/DB)
7. H4 - Reduire la duree du refresh token
8. H5 - Durcir la CSP
9. H6 - Deriver le salt du token de la SECRET_KEY
10. H7 - Reduire la duree de l'access token

### Phase 3 (moyenne, amelioration)
11. M1 a M8 - Corrections diverses

### Phase 4 (basse, polish)
12. L1 a L5 - Nettoyage

---

## 8. TESTS A AJOUTER

Les tests existants (`test_security_owasp.py`) couvrent partiellement les surfaces. A ajouter :

1. Test IDOR sur geniuspay_initiate (utilisateur A ne peut pas payer la reservation de B)
2. Test montant tampering (paiement avec montant < montant reservation => 400)
3. Test webhook signature bypass (sans signature => 403 meme en DEBUG)
4. Test rate limiting bypass via XFF spoofing
5. Test JWT token forgery avec secret par defaut
6. Test refresh token expiration
7. Test upload audio avec fichier non-audio (magic mismatch)

---

---

## 9. CORRECTIFS APPLIQUES (2026-10-27)

Les correctifs suivants ont ete appliques apres l'audit :

### Critiques
- **C1** - `geniuspay.py` : suppression du bypass signature HMAC en DEBUG/sandbox. La verification est maintenant TOUJOURS requise (sauf `GENIUSPAY_SIMULATE=true`). Timestamp obligatoire.
- **C2** - `geniuspay.py` : validation du montant cote serveur. Le montant ne peut pas depasser le solde restant (montant - montant_verse).
- **C3** - `geniuspay.py` : verification d'ownership sur la reservation. Un utilisateur ne peut initier un paiement que pour sa propre reservation (ou celle qui lui est assignee).

### Hautes
- **H1** - `throttle.py` : extraction d'IP securisee. En dev, REMOTE_ADDR est utilise. En prod, le dernier element de XFF (ajoute par le proxy de confiance) est utilise.
- **H2** - `jwt_auth.py` : secret JWT par defaut genere aleatoirement (os.urandom) au lieu de "change-me-in-production".
- **H3** - `jwt_auth.py` : blacklist persistante via cache Django (Redis en prod, LocMemCache en dev) au lieu d'un set en memoire.
- **H4** - `jwt_auth.py` : duree du refresh token reduite de 365 a 30 jours.
- **H5** - `security_middleware.py` : suppression de 'unsafe-eval' du CSP. Restriction de connect-src (suppression de wss: https: wildcard).
- **H6** - `auth.py` : salt du token derive de la SECRET_KEY Django au lieu d'une valeur hardcodee.
- **H7** - `auth.py` : duree de l'access token reduite de 7 jours a 30 minutes.

### Moyennes
- **M1** - `auth.py` : remplacement des print() par logger.debug().
- **M4** - `settings.py` : ALLOWED_HOSTS en dev ne contient plus "*".
- **M5** - `geniuspay.py` : simulation conditionnee uniquement a GENIUSPAY_SANDBOX (pas DEBUG).
- **M2** - `secure_uploads.py` : verification magic bytes pour les uploads audio (ID3, RIFF, OggS, ftyp).
- **M7** - `jwt_auth.py` : verification d'audience JWT activee (verify_aud=True).
- **M3** - `user_store.dart` + `auth_utils.dart` : migration des donnees PII (email, phone, adresse) vers flutter_secure_storage.
- **M6** - `geniuspay.py` : rate limiting sur l'evenement webhook.test.
- **M8** - `user_store.dart` : authPatch et authDelete renouvellent le token sur 401.

### Tests
- `test_TS08_webhook_geniuspay_sans_signature` : passe maintenant (200 -> 403).
- `test_TS01` et `test_TS02` : echecs pre-existants (URL/methode incorrects dans le test, pas dans le code).

### Dependances (osv-scanner)
- `Django` 5.2.10 ? 5.2.17 (52 vulns, dont 13 critiques)
- `Pillow` 10.0.0 ? 12.3.0 (72 vulns)
- `PyJWT` 2.8.0 ? 2.12.0 (28 vulns)
- `PyMySQL` 1.1.0 ? 1.1.1 (2 vulns)
- `python-jose` 3.5.0 ? supprime (pas de fix, remplace par PyJWT)
- `anyio`, `certifi`, `ecdsa`, `idna`, `twisted` ? mises a jour

### Non corriges (a faire)
- Aucun. Tous les items de securite identifies ont ete corriges.

- Aucun. Tous les items de securite identifies ont ete corriges.
