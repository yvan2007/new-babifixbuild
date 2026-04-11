# BABIFIX — Les 4 interfaces, rôle de l’admin, Côte d’Ivoire (FCFA & Mobile Money)

Document de référence aligné sur la vision produit (pas une démo : données réelles, flux métier).

## 1. Les quatre interfaces

| Interface | Public | Rôle |
|-----------|--------|------|
| **App mobile client** | Personnes qui commandent des prestations | Parcourir les prestations / prestataires disponibles, **réserver**, choisir le mode de paiement, suivre le statut, échanger avec le prestataire (hors visibilité admin pour le contenu des messages), noter après service, gérer le flux **espèces** (déclaration → confirmation prestataire → validation admin si prévu). |
| **App mobile prestataire** | Intervenants | Renseigner son **dossier d’identification** (profil, pièces, etc.) ; le dossier part en **validation admin**. Une fois **approuvé**, accès à l’espace métier (catégorie, missions, etc.). **Recevoir** les réservations, **accepter / refuser**, faire évoluer le statut, **discuter de l’heure** ou du détail avec le client, confirmer les paiements espèces côté terrain, voir ses gains. |
| **Site web vitrine** | Grand public | Présentation, confiance, liens stores, FAQ, contenu éditorial ; **ne remplace pas** les apps pour le cœur métier. |
| **Panel web administrateur** | Équipe BABIFIX (staff) | **Pilotage et conformité** : l’admin **ne saisit pas** les noms ni les fiches clients/prestataires comme un opérateur de saisie ; il **voit** ce qui se passe sur la plateforme (réservations, statuts, litiges, transactions, validations). Il **ajoute / gère les catégories** de prestations, **paramètres**, **paiements** (espèces, mobile money, etc.), **approuve ou refuse** les dossiers prestataires, **valide** ce qui doit l’être (ex. prêts en attente, libérations, règles métier). Il **ne lit pas** le contenu des **conversations privées** client ↔ prestataire ; le reste de l’activité transactionnelle et opérationnelle est de son ressort. |

## 2. Synthèse du flux que tu as décrit

- **Client** : mobile → réservation selon disponibilité et prestation voulue → le **prestataire** concerné reçoit la demande et **valide** (ou non) ; ajustements possibles sur **l’heure** / détails via l’échange dans l’app.
- **Prestataire** : mobile → envoi du dossier → **admin** décide **approuver / refuser** → si approuvé, accès à l’espace avec catégorie principale et informations métier.
- **Admin** : vue transversale (interactions, transactions, validations) **sans** être la source de saisie des identités clients/prestataires, et **sans** accès au fil des **discussions** client–prestataire.

## 3. Côte d’Ivoire : temps et monnaie

- **Montants** : exprimés en **francs CFA** (**FCFA**), fuseau **Afrique/Abidjan** côté serveur quand tu configures la prod.
- **Mobile Money** : opérateurs majeurs en CI — **Orange Money**, **MTN Mobile Money**, **Wave**, **Moov Money**. Dans le code, l’app client peut préciser l’opérateur lorsque le type de paiement est « Mobile Money ».

## 4. Logos et chartes (respect des marques)

Les **logos officiels** (Orange, MTN, Wave, Moov) sont protégés : pour une app en production, utilise les **kits média / guidelines** publiés par chaque marque ou des assets fournis par ton intégrateur agrégateur de paiement.  
Dans ce dépôt, l’UI peut afficher le **nom** de l’opérateur et des **couleurs d’identification** courantes (approximation visuelle) ; tu peux remplacer par des **images officielles** dans `assets/` une fois les droits / fichiers obtenus.

## 5. Cohérence avec `BABIFIX_BUILD`

- Backend : devise **FCFA** sur les montants exposés ; champ optionnel **`mobile_money_operator`** sur les réservations lorsque `payment_type = MOBILE_MONEY`.
- Apps : choix **Orange Money / MTN / Wave / Moov** au moment de la réservation (Mobile Money).
- Temps réel / FCM : le panel admin reste informé des événements métier (hors contenu des messages privés — à respecter aussi côté API et permissions).
