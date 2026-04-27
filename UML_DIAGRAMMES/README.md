# Diagrammes UML - Projet BABIFIX

## Vue d'ensemble

**Thème visuel :** Bleu clair professionnel (version actuelle des .puml)
- Fond : `#E3F2FD`
- Boites/Cas : `#BBDEFB`
- Bordures : `#1976D2`
- Titres : `#01579B`
- Fleches : `#64B5F6`

Note: Les diagrammes ont ete mis a jour pour correspondre au code reel (Django/PostgreSQL au lieu de Firebase/Firestore)  

---

Ce dossier contient **tous les diagrammes UML** du projet BABIFIX, créés au format **PlantUML** (`.puml`). Ils couvrent les 3 acteurs du système : **Client**, **Prestataire** et **Admin**.

---

## Fichiers et Description

### 1. Diagramme de Cas d'Utilisation
**Fichier :** `01_use_case_diagramme.puml`

**Contenu :**
- **3 acteurs** : Client, Prestataire, Admin
- **3 systèmes** : App Client (BABIFIX), App Prestataire (BABIFIX Pro), Panel Admin
- Relations **<<include>>** et **<<extend>>**
- Acteurs externes : CinetPay, Firebase

**Cas d'utilisation principaux :**
- Client : inscription, réservation, paiement, notation, chat
- Prestataire : inscription CNI, gestion profil, RDV, paiements espèces, gains
- Admin : validation prestataires, statistiques, catégories, notifications

---

### 2. Diagramme de Classes
**Fichier :** `02_class_diagramme.puml`

**Contenu :**
- **Classe abstraite** : `Utilisateur` (attributs #private et +public)
- **Sous-classes** : `Client`, `Prestataire`, `Admin`
- **Entités métier** : `Categorie`, `Service`, `Reservation`, `Paiement`, `Rating`, `Message`, `Notification`
- **Énumérations** : `StatutValidation`, `StatutReservation`, `StatutPaiement`, `TypePaiement`
- Attributs avec visibilité : `-` privé, `#` protégé, `+` public
- Relations : héritage, composition, association

---

### 3. Diagrammes de Séquence

#### 3.1 Client - Réservation et Paiement
**Fichier :** `03_sequence_client_reservation.puml`

Flux complet : Connexion → Sélection service/prestataire → Création réservation → Paiement Mobile Money (CinetPay)

#### 3.2 Prestataire - Inscription et Validation
**Fichier :** `04_sequence_prestataire_inscription.puml`

Flux : Formulaire CNI → Upload Storage → Enregistrement pending → Notification Admin → Validation/Refus

#### 3.3 Admin - Gestion Globale
**Fichier :** `05_sequence_admin_validation.puml`

Flux : Connexion → Validation prestataires → Gestion catégories → Statistiques

#### 3.4 Paiement en Espèces
**Fichier :** `06_sequence_paiement_especes.puml`

Flux : Client déclare payé → Prestataire confirme → Admin valide (optionnel)

---

### 4. Diagrammes d'Activité

#### 4.1 Client - Réservation
**Fichier :** `07_activite_client_reservation.puml`

Activités : Connexion, sélection, réservation, choix paiement (Mobile Money / Espèces)

#### 4.2 Prestataire - Inscription et Validation
**Fichier :** `08_activite_prestataire_validation.puml`

Activités : Formulaire, upload CNI, attente, validation Admin (Valider/Refuser)

#### 4.3 Admin - Gestion Complète
**Fichier :** `09_activite_admin_gestion.puml`

Activités parallèles : Validation prestataires, catégories, statistiques, paiements espèces, notifications

#### 4.4 Notation
**Fichier :** `10_activite_notation.puml`

Activités : Client consulte réservations terminées → Note 1-5 → Commentaire → Recalcul moyenne

---

### 5. Diagrammes Avancés (Architecture & Infrastructure)

#### 5.1 Diagramme de Composants
**Fichier :** `11_composants_architecture.puml`

Contenu :
- **Architecture monolithique en couches** (pas microservices)
- **Backend** : Django REST Framework + Django Channels (ASGI)
- **Admin** : Django Templates + HTMX + Alpine.js
- **Composants** : auth.py (JWT custom), views.py, models.py, consumers.py, signals.py
- **Base de donnees** : PostgreSQL, Redis, MEDIA_ROOT (local)
- **Services externes** : Firebase (FCM uniquement), CinetPay, SMTP
- **Services externes** : Firebase, CinetPay, SMTP, Sentry

#### 5.2 Diagramme de Déploiement
**Fichier :** `12_deploiement_infrastructure.puml`

Contenu :
- **Infrastructure production** avec haute disponibilité
- **CDN/Edge** : Cloudflare avec SSL, DDoS protection
- **Load Balancer** : Nginx avec health checks
- **Serveurs applicatifs** : Gunicorn + Uvicorn, Django Channels
- **Cluster DB** : PostgreSQL avec réplication
- **Cache** : Redis cluster, Celery workers

---

### 6. Diagrammes d'État (State Machine)

#### 6.1 State Machine Réservation
**Fichier :** `13_state_machine_reservation.puml`

États :
- DEMANDE_ENVOYEE → DEVIS_EN_COURS → DEVIS_ENVOYE → DEVIS_ACCEPTE → INTERVENTION_EN_COURS → EN_ATTENTE_CLIENT → TERMINEE
- Chemins d'annulation : ANNULEE
- Flux paiement : PENDING → COMPLETE (StatutPaiement)

#### 6.2 State Machine Prestataire
**Fichier :** `16_state_machine_prestataire.puml`

États :
- EN_ATTENTE → VALIDE (prestataire actif) ou REFUSE (dossier refusé)
- VALIDE → SUSPENDU → VALIDE (cycle suspension/réactivation admin)
- Règles métier : visible client uniquement si VALIDE

---

### 7. Diagrammes de Séquence Avancés

#### 7.1 Chat Temps Réel (WebSocket + FCM)
**Fichier :** `14_sequence_chat_websocket.puml`

Flux :
- Connexion WebSocket avec authentification JWT
- Envoi de messages texte et images
- Indicateur de frappe
- Notifications push pour utilisateurs hors-ligne
- Gestion de la déconnexion

#### 7.2 Gestion des Litiges
**Fichier :** `15_sequence_litiges.puml`

Flux :
- Ouverture litige par client avec preuves
- Réponse du prestataire
- Décision admin (remboursement/partage/libération)
- Audit log et notifications
- Délai automatique de 7 jours

#### 7.3 Paiement Mobile Money (CinetPay)
**Fichier :** `17_sequence_paiement_mobile_money.puml`

Flux :
- Initiation avec sélection opérateur
- Vérification signature HMAC du webhook
- Confirmation et mise à jour des statuts
- Notifications push de succès/échec
- Gestion des remboursements

## Comment visualiser les diagrammes

### Option 1 : PlantUML en ligne
1. Copier le contenu d'un fichier `.puml`
2. Coller sur [PlantUML Online](https://www.plantuml.com/plantuml/uml/)
3. Le diagramme s'affiche automatiquement

### Option 2 : Extension VS Code / Cursor
- Installer l'extension **PlantUML**
- Ouvrir un fichier `.puml`
- `Alt+D` ou clic droit → "Preview Current Diagram"

### Option 3 : Ligne de commande
```bash
# Installer PlantUML (nécessite Java)
# Puis :
plantuml 01_use_case_diagramme.puml
# Génère 01_use_case_diagramme.png
```

### Option 4 : Export en PNG/SVG
- PlantUML Online : bouton "Submit" puis "PNG" ou "SVG"
- VS Code : Export via extension PlantUML

---

## Légende des symboles UML

### Diagramme de Classes
- `-` : attribut/méthode **privé**
- `#` : attribut/méthode **protégé**
- `+` : attribut/méthode **public**

### Diagramme de Cas d'Utilisation
- `<<include>>` : cas inclus (obligatoire)
- `<<extend>>` : cas étendu (optionnel)

### Diagramme de Séquence
- `->` : message synchrone
- `-->` : message de retour
- `alt` : alternative
- `opt` : optionnel

---

## Structure des 3 acteurs BABIFIX

| Acteur | Application | Accès |
|--------|-------------|-------|
| **Client** | BABIFIX (mobile) | Réserver, payer, noter |
| **Prestataire** | BABIFIX Pro (mobile) | Profil, RDV, gains |
| **Admin** | Panel Web (Django Templates + HTMX) | Validation, stats, gestion |

---

## Correspondance avec l’implémentation (`BABIFIX_BUILD`)

Le code source de production est dans **`BABIFIX_BUILD`** (Django admin + API, vitrine Django, apps Flutter). Les diagrammes UML ci-dessus servent de référence métier ; l’alignement technique inclut notamment :

| Élément UML | Implémentation |
|-------------|----------------|
| **Prestataire** (validation, tarif, notes, CNI, disponibilité) | Modèle `Provider` : `tarif_horaire`, `average_rating`, `rating_count`, `disponible`, `cni_url`, statuts alignés |
| **Réservation** + statuts | `Reservation` : statuts *En attente*, *Confirmée*, *En cours*, *Terminée*, *Annulée* ; type de paiement ; flux espèces |
| **Paiement espèces** (séquence triple validation) | Champs `cash_*` sur `Reservation` ; API `cash-declare` (client), `cash-confirm` (prestataire), `cash-validate` (admin) |
| **Rating / avis** | Modèle `Rating` (1–5, commentaire) ; recalcul `average_rating` / `rating_count` sur le prestataire ; API `POST .../rating` |
| **Catégorie** | `Category` : `description`, `icone_url`, `ordre_affichage` ; API publique `GET /api/public/categories/` |
| **Paiement** | `Payment` : lien optionnel `reservation`, `type_paiement`, `valide_par_admin`, `reference_externe` |
| **FAQ / contenu** | `SiteContent` clé `faq` (JSON) exposée dans `GET /api/public/vitrine/` |

Les endpoints détaillés sont dans `babifix_admin_django/adminpanel/urls.py`.

### Intégration réelle & temps réel (sans démo)

Pour connecter les **4 interfaces** (2 mobiles, vitrine, panel admin), désactiver les données factices et prévoir **WebSocket + push FCM**, voir :

**`BABIFIX_BUILD/docs/ARCHITECTURE_TEMPS_REEL_ET_INTEGRATION.md`**

---

*Projet BABIFIX - Mémoire Informatique*  
*Diagrammes générés en PlantUML*
