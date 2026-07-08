# 🏗️ PLAN D'ÉVOLUTION BABIFIX — Devis fiable, caution & confiance

> Document de conception (pas de code). Récapitule TOUTES les idées validées + les
> étapes d'implémentation, pensées pour **ne rien casser** de ce qui marche déjà.
> À utiliser comme **checklist** au fur et à mesure.

---

## 🔑 Principe directeur — la règle d'or « ne rien casser »
Tout est **additif et rétrocompatible** :
- **Nouveaux champs = optionnels**, avec une **valeur par défaut = comportement actuel**.
- **Nouveaux statuts insérés**, jamais supprimés → l'ancien flux (réservation → devis direct → escrow) **reste le chemin par défaut**.
- **Activation catégorie par catégorie** (feature flag) → déploiement sans impacter les métiers non concernés.
- On **teste chaque phase** avant la suivante. Le flux actuel doit **toujours** fonctionner.

---

## 📦 PARTIE A — Toutes les briques

| # | Fonctionnalité | Rôle |
|---|---|---|
| 1 | **Nature de la demande (type)** | Panne, réaménagement, maintenance… un **type** au lieu de texte libre imprécis |
| 2 | **Description multimodale** (texte + photos + **note vocale** + vidéo option) | Décrire le besoin richement, même sans savoir écrire |
| 3 | **Profil de devis** par catégorie (Surface / Forfait / Diagnostic / Standard) | Décide quel volet s'affiche |
| 4 | **Template d'exigences (JSON)** par catégorie | Questions propres à chaque métier, éditables dans l'admin |
| 5 | **Formulaire de mesures + calcul m²** (les **4 niveaux**) | Chiffrer les travaux au m² |
| 6 | **Devis en 2 temps** (estimation → ferme) | Prix indicatif tout de suite, prix ferme après |
| 7 | **Visite de diagnostic/métré** (nouveau statut) | Quand la présence est nécessaire |
| 8 | **Caution de diagnostic** (déductible) | Protéger le presta + anti-ghosting |
| 9 | **Commission à 2 moments** | Petit % sur la caution + normal sur le job |
| 10 | **Confidentialité progressive** (zone avant / adresse après) | Vie privée + anti-contournement |
| 11 | **Visio-diagnostic** (LiveKit existant) | Diagnostiquer sans se déplacer |
| 12 | **Anti-contournement** (masquage contacts, score fiabilité, détection annulations) | Éviter la désintermédiation |
| 13 | **Règles no-show / annulation** | Cadrer les cas limites |

---

## 🔎 Détail des « intelligences » clés

### ① Nature de la demande (ce n'est PAS toujours une panne)
Un besoin n'est pas forcément un **problème**. Il faut un **type structuré**, plus précis que du texte libre :

- 🔴 **Panne / réparation** (un robinet fuit, une prise ne marche plus)
- 🟠 **Maintenance / entretien** (révision clim, vidange, contrôle périodique)
- 🟢 **Réaménagement / rénovation** (repeindre, refaire un carrelage, réagencer)
- 🔵 **Installation / pose** (poser une clim, installer un chauffe-eau, monter un meuble)
- 🟣 **Devis / conseil** (juste une estimation ou un avis)
- ⚪ **Autre**

**Pourquoi :** le texte libre (« ma douche marche pas ») est **imprécis**. Le type oriente le presta **et** adapte les questions suivantes (une rénovation → mesures ; une panne → symptômes).

### ② Description multimodale (pas seulement écrit)
Beaucoup d'utilisateurs sont **peu à l'aise avec l'écrit**. La demande doit accepter :
- **Texte** (comme aujourd'hui)
- **Photos** (déjà en place)
- **Note vocale** 🎙️ — le client **enregistre et envoie** un message audio pour expliquer son besoin *(plus naturel, plus riche qu'un texte)*
- **Vidéo courte** (option) — surtout pour montrer un problème en mouvement

> NB : les **notes vocales existent déjà dans le chat** → on **réutilise le même composant** au moment de la **demande/description**, pas juste dans la discussion.

### ③ Les 4 niveaux de mesure (profil Surface)
1. **Presets** (type de logement) → estimation sans mesurer.
2. **Photo avec objet de référence** (porte ≈ 2 m, carreau, feuille A4) → estimation dégrossie.
3. **Visio guidée** (le presta dicte les mesures) → bonne précision.
4. **Visite de métré** (avec caution) → exacte.

### ④ Les 4 profils (chaque catégorie en a un)
- **Surface** (peinture, carrelage) → mesures / m².
- **Forfait** (ménage, jardinage) → quantités (nb pièces, taille jardin).
- **Diagnostic** (plomberie, élec, clim) → symptômes + photos/visio + visite.
- **Standard** (montage, petits travaux) → photos + description.

---

## 🪜 PARTIE B — Les ÉTAPES d'implémentation (ordre qui ne casse rien)

### Phase 0 — Préparation
- [ ] Branche dédiée (jamais direct sur master).
- [ ] Règle : **migrations additives uniquement** (jamais supprimer/renommer un champ utilisé).
- [ ] Chaque nouveau champ a un **défaut = comportement actuel**.
- [ ] Backup base avant chaque migration.
- [ ] Noter le **cycle actuel de référence** (pour vérifier l'absence de régression).

### Phase 1 — Quick wins (n'affectent PAS le flux existant) ✅ TERMINÉE
- [x] **Nature de la demande (type)** : sélecteur ajouté au formulaire de réservation (défaut vide → rien cassé).
- [x] **Note vocale à la demande** : composant audio du chat réutilisé au stade description.
- [x] **Zone + distance avant acceptation** : `distance_km` exposé + badge presta ; adresse exacte toujours masquée.
- [x] **Masquage des contacts dans le chat** : `mask_contacts` (numéros/emails) côté serveur (REST + WebSocket).
- [x] **Bouton « visio-diagnostic »** : appel vidéo presta→client avant acceptation (exception ciblée, LiveKit).
- [ ] → Tester, redéployer admin, réinstaller les APK.

### Phase 2 — Le devis intelligent (cœur métier) ✅ TERMINÉE
- [x] Champ **`profil_devis`** sur la **catégorie** (défaut **Standard** → inchangé). *(migration 0082)*
- [x] Champ **`template_exigences` (JSON)** sur la catégorie (défaut **vide** → formulaire actuel). *(migration 0082 ; éditable dans l'admin catégories)*
- [x] App : **si template vide → formulaire actuel** ; sinon → formulaire **généré dynamiquement**. *(widget `BabifixDynamicRequirements` + endpoint `/api/providers/<id>/requirements/` ; réponses stockées dans `Reservation.reponses_exigences`, migration 0083, affichées côté presta)*
- [x] Le **type de demande** peut filtrer/adapter les questions du template. *(question déclarant `types:[...]` → affichée seulement si le type courant y figure)*
- [x] **Formulaire de mesures** (profil Surface) + **calcul m² auto** + **presets logement**. *(assistant surface : presets studio→villa + calcul L×l (sol) / 2·(L+l)·H (murs) → bouton Reporter)*
- [x] **Toutes les catégories pré-remplies** (profil + template). *(migration 0084, idempotente)*
- [x] **Devis en 2 temps** : `est_estimation` + `prix_min` / `prix_max` (migration 0085). Estimation = fourchette indicative NON payable (demande reste DEVIS_EN_COURS) ; le presta envoie ensuite un devis ferme (qui périme l'estimation) ; l'acceptation refuse les estimations. App presta : bascule « Envoyer une estimation ». App client : fiche + carte chat affichent la fourchette, sans bouton payer.
- [ ] → Activer **une seule catégorie test** (ex. Peinture), vérifier, puis étendre. *(les 10 catégories sont déjà pré-remplies via 0084 ; à valider en réel)*

### Phase 3 — La visite & la caution (+ commission) ✅ TERMINÉE
- [x] Statut **`VISITE_DIAGNOSTIC`** inséré **avant `DEVIS_ENVOYE`** — **optionnel** (devis direct toujours possible). *(migration 0086)*
- [x] Champs **caution** : `caution_montant`, `caution_motif`, `caution_payee`, `caution_deduite` (défauts 0/false).
- [x] **Endpoint paiement caution** : `POST .../pay-caution` (même modèle que l'acompte : Payment + PlatformRevenue). App presta demande la visite (`request-visit`), app client règle la caution (chip « Caution visite »).
- [x] **Déblocage adresse conditionné au paiement de la caution** (`caution_payee` → adresse exacte révélée au presta).
- [x] **Commission caution** (12 % sur la caution) + **déduction** de la caution du montant à l'acceptation du devis (`caution_deduite`).
- [x] **Règles no-show / annulation** (qui garde la caution). *(migration 0087 : `visite_effectuee`/`caution_remboursee`. Visite faite → presta garde la caution ; sinon → remboursée au client + commission plateforme rendue. Presta déclare la visite via `visite-done`.)*
- [ ] → Tester le cycle **avec** ET **sans** visite (les deux doivent marcher).

> 💰 Commission caution fixée à **12 %** (dans `pay_caution`). Le montant de la caution lui-même est libre (FCFA saisi par le presta). Rendre le 12 % configurable en admin = amélioration possible.

> ⚠️ Note technique : l'écran de création de devis réellement utilisé est **`DevisKanbanEditorScreen`** ; `create_devis_screen.dart` est **du code mort**. L'estimation & la visite sont donc exposées via des **dialogues dans la fiche demande** (`request_detail_screen.dart`), pas dans l'ancien écran.

### Phase 4 — Confiance avancée (v2) ✅ TERMINÉE (permissif)
- [x] **Score de fiabilité** (0–100, défaut 100) sur `Provider` ET `UserProfile` (client). Gains à la prestation terminée, pertes au no-show / annulation tardive (`ReliabilityService`, migration 0088). *Conséquences dures (visibilité, quota, prépaiement) volontairement PAS encore appliquées → activables plus tard sur ce signal.*
- [x] **Détection d'annulations suspectes** : client qui annule juste après le déblocage de l'adresse (sans visite/prestation) → `annulation_suspecte` + malus + log si motif répété même client+presta.
- [x] → **Permissif** : deltas petits, aucun blocage, score borné 0–100, hooks best-effort. Badge « Fiabilité X/100 » visible dans l'admin (fiche presta).

---

## ✅ ÉTAT GLOBAL — Phases 1 à 4 livrées
Le socle complet (nature de demande, note vocale, masquage contacts, zone+distance, visio-diagnostic, devis intelligent + templates par catégorie + assistant surface, devis en 2 temps, visite + caution déductible + commission à 2 moments + no-show, score de fiabilité) est **implémenté et poussé**. Restent surtout : **tests bout-en-bout en réel**, et les **améliorations d'activation** (rendre configurables les taux/seuils, activer le gating du score quand le signal est jugé fiable).

---

## ⚠️ PARTIE C — Points de vigilance (ne rien casser)

| Risque | Précaution |
|---|---|
| Une migration casse la base | **Additif uniquement** ; jamais supprimer/renommer un champ en prod |
| L'ancienne app plante sur un nouveau champ | **Rétrocompatibilité** : l'API tolère l'absence des nouveaux champs |
| Un métier non concerné est impacté | **Défaut = Standard** ; activation **catégorie par catégorie** |
| Le flux actuel régresse | **Défaut = comportement actuel** ; tester le cycle complet après CHAQUE phase |
| Déploiement partiel | **Backend d'abord** (migrations + endpoints), **puis** les apps |
| Perte de données | Backup avant migration ; migrations réversibles |

---

## 🚀 PARTIE D — Ordre de déploiement & tests (à chaque phase)
1. **Backend** : migrations additives + endpoints → `python manage.py check` → **redéployer Render**.
2. **Apps** : build + réinstaller les APK.
3. **Test du cycle complet** (client réserve → devis → paiement → escrow → confirmation) → **doit toujours marcher**.
4. **Test de la nouvelle brique** de la phase.
5. Si OK → phase suivante. Si KO → corriger **avant** d'avancer.

---

## 💰 Rappel — La commission (2 moments, jamais en double)
- **Sur la prestation** : commission **normale** (18 %), à la **libération de l'escrow** — inchangée.
- **Sur la caution de visite** : **petite** commission (10–15 %), au **paiement de la caution**.
- **Cas accepté** : la caution est déduite du **prix client** (pas de ta commission) → tu gardes tes 2 revenus.
- **Cas refusé** : tu gardes au moins la **commission de visite** ; le presta garde la caution (dédommagement déplacement).

---

## 🎯 Phrase de synthèse (soutenance)
> « BABIFIX s'adapte à la nature du besoin (panne, maintenance, réaménagement…) et au métier :
> il collecte l'information de la manière la plus riche et la plus légère possible — type de
> demande, **note vocale**, photos, presets, visio guidée — et n'exige une **visite de métré**
> (avec caution déductible) que pour les gros chantiers. Le tout **sans casser** le parcours
> existant, car chaque évolution s'ajoute de façon rétrocompatible. »

---

*Document de conception — BABIFIX. À dérouler phase par phase.*

---

## 🔧 Améliorations post-Phases 1–4 (livrées)
- [x] **Réglages admin** (`PlatformConfig`, migration 0089, éditable via `/admin`) : commission caution (%), activation du gating + seuil, deltas de fiabilité. `pay_caution` et `ReliabilityService` lisent la config.
- [x] **Gating fiabilité** (helpers + surfaces exposées, **OFF par défaut**) : `provider_penalise`, `client_prepaiement_requis` ; champs `fiabilite_score` (profil presta) et `prepaiement_requis` (résa client) exposés.
- [x] **Badge score client** dans l'admin (fiche Clients).
- [x] **Test bout-en-bout** (`adminpanel/tests/test_phase1_4_features.py`, 6 cas, VERT).

## 🐞 Bugs trouvés par le test E2E
- [x] **CORRIGÉ** — les hooks caution/fiabilité d'annulation étaient sur `CancellationService` **sans aucun appelant** (code mort) → déplacés vers `api_client_cancel_reservation` (endpoint réel). Avant ce fix, annuler ne remboursait jamais la caution et ne bougeait pas le score.
- [ ] **À décider** — signal `post_save` réservation appelle `send_babifix_email` **non défini** → les e-mails liés aux réservations échouent silencieusement (warning à chaque save).
- [ ] **À décider** — seed démo `Client.depense = "2 450"` mal formaté → `_bootstrap_data` plante si `BABIFIX_ENABLE_DEMO_SEED=1` sur base neuve.
- [ ] **À décider** — `CancellationService.cancel` référence des colonnes supprimées (`cancelled_at`, `cancellation_by/stage/motif` par 0071) → planterait si un jour appelé (actuellement mort).
