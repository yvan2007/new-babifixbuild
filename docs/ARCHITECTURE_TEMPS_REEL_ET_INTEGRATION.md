# BABIFIX — Intégration réelle & temps réel (hors démo)

Ce document relie les **4 interfaces** (`BABIFIX_BUILD`), le **modèle métier UML** (`BABIFIX/UML_DIAGRAMMES`) et une stratégie technique pour que **toute action soit propagée** aux bons écrans, sans s’appuyer sur des données factices.

---

## 1. Les quatre interfaces (rôles)

| Interface | Canal | Rôle |
|-----------|--------|------|
| **App mobile client** | Flutter | Réserver, payer (Mobile Money / espèces), suivre statuts, litiges côté client, **chat** avec le prestataire. |
| **App mobile prestataire** | Flutter | Profil, pièces / identité → **validation admin**, accepter/refuser réservations, confirmer paiement espèces, gains, **chat**. |
| **Vitrine web** | Django (babifix_vitrine) | Marketing, liens stores, contenu public ; consomme l’**API publique** (catégories, vitrine). |
| **Panel administrateur** | Django (dashboard + auth) | **Ne crée pas** les fiches client/prestataire à la main : il **observe** et **pilote** (catégories, paramètres, validation dossiers, paiements espèces, litiges, stats). **Ne voit pas** le contenu des conversations client ↔ prestataire (conforme cahier des charges). |

**Source de vérité unique :** la même base de données et les mêmes API Django (`babifix_admin_django`), appelées par les apps Flutter et la vitrine.

Synthèse métier détaillée (flux client / prestataire / admin, FCFA, opérateurs Mobile Money en Côte d’Ivoire) : **`QUATRE_INTERFACES_ROLE_ADMIN_ET_PAIEMENTS_CI.md`**.

---

## 2. Alignement avec les diagrammes UML

Les séquences et activités dans `UML_DIAGRAMMES/` décrivent déjà les flux à connecter en production :

- `03_sequence_client_reservation.puml` / `07_activite_client_reservation.puml` — création réservation, choix paiement.
- `04_sequence_prestataire_inscription.puml` / `08_activite_prestataire_validation.puml` — dossier → **notification admin** → approuver / refuser.
- `05_sequence_admin_validation.puml` / `09_activite_admin_gestion.puml` — validation, catégories, stats, paiements.
- `06_sequence_paiement_especes.puml` — déclaration client → confirmation prestataire → **validation admin**.
- `10_activite_notation.puml` — note après prestation → recalcul moyenne prestataire (`Rating` / `Provider`).

Le diagramme de classes `02_class_diagramme.puml` correspond aux modèles Django (`Provider`, `Reservation`, `Payment`, `Category`, `Dispute`, `Rating`, messagerie, etc.).

---

## 3. État actuel du code (réel vs démo)

### 3.1 Données factices (désactivées par défaut)

Le backend injectait des prestataires, réservations, paiements et comptes `*_demo` si les tables étaient vides.

- **Comportement actuel :** le seed démo ne s’exécute **que** si la variable d’environnement `BABIFIX_ENABLE_DEMO_SEED=1` est définie.
- **Sans cette variable :** seuls les **réglages système** (`SystemSetting`) et les **clés de contenu vitrine** (`SiteContent`) sont initialisés — le reste vient des **inscriptions et actions réelles** (mobile + panel).

### 3.2 Temps réel — panel web (implémenté)

- **Django Channels + Daphne** : `daphne` en tête de `INSTALLED_APPS` pour que `runserver` serve l’**ASGI** (HTTP + WebSocket).
- **WebSocket** : `ws://…/ws/admin/events/` — réservé aux utilisateurs **authentifiés et staff** (cookie de session, même login que `/admin/`).
- **Signaux Django** (`adminpanel/signals.py`) : après chaque `save` / `delete` sur `Reservation`, `Provider`, `Dispute`, `Payment`, `Category`, `Notification`, `Client`, `SystemSetting`, `SiteContent`, `Rating` → `group_send` vers le groupe `babifix_admin_events`.
- **Dashboard** : toast + rechargement léger (~650 ms) pour refléter les changements venant de l’**API mobile** ou d’un autre onglet admin.
- **Redis** : optionnel. Si `REDIS_URL` est défini → `RedisChannelLayer` (plusieurs workers / prod). Sinon → `InMemoryChannelLayer` (un seul processus, suffisant en dev).

Les **apps Flutter** restent en **REST** + (phase 2) **FCM** ; elles ne consomment pas encore ce WebSocket.

---

## 4. Cible : interaction quasi temps réel (recommandation technique)

Pour que « une modification soit directement transmise au destinataire », combiner **trois briques** (état de l’art pour ce type de plateforme) :

### A. WebSocket (panel admin + optionnellement vitrine connectée)

- **Django Channels** + **Redis** (ou autre broker) : le serveur **publie** un message sur un canal quand un modèle clé change (réservation, statut prestataire, paiement espèces, litige).
- Le **dashboard admin** ouvre une connexion WebSocket et **rafraîchit** les compteurs / listes ou affiche une toast sans recharger la page.
- **Événements à publier** (catalogue minimal, dérivé des UML) :
  - `reservation.created` / `reservation.status_changed`
  - `provider.validation_changed`
  - `payment.cash_client_declared` / `payment.cash_prestataire_confirmed` / `payment.cash_admin_validated`
  - `dispute.updated`
  - `category.updated` (pour invalidation cache vitrine + apps)

### B. Notifications push mobile (Firebase Cloud Messaging)

- Les cas d’usage UML citent **Firebase** comme acteur externe : enregistrer un **device token** par utilisateur (client / prestataire).
- À chaque événement pertinent, l’API envoie une **notification FCM** (nouvelle demande de réservation, décision admin, étape paiement espèces, etc.).
- L’app ouvre l’écran concerné via `data` payload (référence réservation, type d’événement).

### C. Messagerie client ↔ prestataire

- **Hors visibilité admin** : les messages restent sur le canal **Conversation / Message** ; l’admin n’a pas d’endpoint de lecture du contenu.
- Temps réel : **WebSocket dédié** par conversation ou **FCM** + sync REST, selon charge et simplicité.

### D. Vitrine

- Contenu statique / semi-statique : re-fetch API ou **invalidation** quand `category` / `SiteContent` change (événement WebSocket léger ou simple TTL court sur CDN en prod).

---

## 5. Plan de mise en œuvre (phases)

1. **Phase 0 (fait)** : une seule API Django, auth JWT/session, pas de seed démo par défaut, flux REST alignés UML (réservation, espèces, notation, etc.).
2. **Phase 1 (fait)** : **Channels + Daphne**, WebSocket `/ws/admin/events/`, signaux sur les modèles métier listés en §3.2, UI dashboard (pastille + toast + reload).
3. **Phase 2 (fait)** : **FCM** — modèle `DeviceToken`, `POST/DELETE /api/auth/fcm-token` (JWT client/prestataire), `firebase-admin` côté Django (`FIREBASE_CREDENTIALS_JSON_PATH`), envoi depuis `push_dispatch` (réservations, prestataire, paiements liés, avis). Apps Flutter : `firebase_core` / `firebase_messaging`, `babifix_fcm.dart`, Gradle `google-services`. Voir `docs/FCM_SETUP.md`.
4. **Phase 3** : WebSocket ou long-polling pour **liste des messages** / badge non-lu dans les apps (sans exposer le chat à l’admin).

---

## 6. Rapports, mémoire et traçabilité

Pour le document de fin de cycle, vous pouvez appuyer cette architecture sur :

- Les **diagrammes PlantUML** (séquences = preuve des flux à couvrir par les événements temps réel).
- Un **tableau de correspondance** modèle UML ↔ modèle Django ↔ événement WebSocket / push (à compléter au fil de l’implémentation).
- Les choix **Channels + FCM** comme **état de l’art** courant pour marketplaces / services à la demande.

---

## 7. Variables d’environnement utiles

| Variable | Effet |
|----------|--------|
| `BABIFIX_ENABLE_DEMO_SEED=1` | Réactive le jeu de données factice (dev / démo uniquement). |
| `REDIS_URL` | Ex. `redis://127.0.0.1:6379/1` — broker Channels si plusieurs workers ; sinon couche mémoire. |
| `FIREBASE_CREDENTIALS_JSON_PATH` ou `GOOGLE_APPLICATION_CREDENTIALS` | Fichier JSON compte de service Firebase (envoi FCM serveur). |

---

*Document généré pour le dépôt `BABIFIX_BUILD` — cohérent avec `BABIFIX/UML_DIAGRAMMES/README.md`.*
