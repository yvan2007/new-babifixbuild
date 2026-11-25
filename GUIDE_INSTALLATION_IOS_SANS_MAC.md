# Guide Exécutif : Installation des Applications BABIFIX sur iPhone (Sans Mac)

Ce guide décrit la procédure pour compiler les fichiers d installation iOS (`.ipa`) dans le Cloud et les installer directement sur un iPhone depuis un PC Windows.

---

## 1. Principe de Fonctionnement

* **Compilation Cloud (GitHub Actions macOS gratuit)** : GitHub fournit des serveurs macOS virtuels qui compilent le projet Flutter et génèrent les fichiers `.ipa` pour le Client et le Prestataire.
* **Signature & Injection Locale (Sideloadly sous Windows)** : le logiciel gratuit Sideloadly tourne sur votre PC Windows. Il signe l archive `.ipa` avec votre identifiant Apple ID gratuit habituel et l injecte directement sur votre iPhone branché en USB.

---

## 2. Étape 1 : Déclencher le Build iOS dans GitHub

1. Rendez-vous sur votre dépôt GitHub : [https://github.com/yvan2007/new-babifixbuild](https://github.com/yvan2007/new-babifixbuild)
2. Cliquez sur l onglet **Actions**.
3. Dans la liste à gauche, cliquez sur le workflow : **Build iOS IPA (Sans Mac)**.
4. Cliquez sur le bouton **Run workflow** (bouton bleu à droite) puis sélectionnez la branche `master`.
5. La compilation démarre sur les runners macOS d Apple Silicon.
6. Une fois le build terminé (environ 8 à 12 minutes) :
   * Descendez tout en bas de la page du workflow dans la section **Artifacts**.
   * Téléchargez les archives :
     * `BABIFIX-Client-iOS-IPA` (contient `BABIFIX-Client.ipa`)
     * `BABIFIX-Prestataire-iOS-IPA` (contient `BABIFIX-Prestataire.ipa`)

---

## 3. Étape 2 : Préparer votre PC Windows

1. **Installer iTunes pour Windows** (impératif pour que Windows communique avec l iPhone) :
   * Téléchargez la version classique 64-bit d iTunes depuis le site officiel Apple :
     [https://www.apple.com/itunes/download/win64](https://www.apple.com/itunes/download/win64)
   * *(Attention : évitez la version du Microsoft Store qui bloque parfois la communication USB avec les utilitaires tiers).*

2. **Installer Sideloadly pour Windows** :
   * Téléchargez Sideloadly (logiciel gratuit et sécurisé de sideloading) :
     [https://sideloadly.io/](https://sideloadly.io/)
   * Installez-le sur votre PC.

---

## 4. Étape 3 : Installer l IPA sur votre iPhone

1. **Connecter l iPhone au PC** :
   * Branchez votre iPhone au PC via son câble USB.
   * Déverrouillez votre iPhone.
   * Si l iPhone vous demande : « Faire confiance à cet ordinateur ? », appuyez sur **Oui / Se fier** et entrez votre code PIN.
2. **Ouvrir Sideloadly** :
   * Dans le champ **iDevice**, votre iPhone apparaît automatiquement sélectionné.
   * Dans le champ **Apple ID**, renseignez votre adresse email Apple ID (celle que vous utilisez sur votre iPhone).
   * Glissez-déposez le fichier `BABIFIX-Client.ipa` (ou `BABIFIX-Prestataire.ipa`) dans la grande case marquée **IPA** à gauche.
   * Cliquez sur le bouton **Start**.
   * Si demandé la première fois, entrez le mot de passe de votre Apple ID (Sideloadly l utilise uniquement pour demander à Apple un certificat développeur gratuit de 7 jours).
3. Sideloadly affiche `Done.` : l icône BABIFIX apparaît immédiatement sur l écran d accueil de votre iPhone !

---

## 5. Étape 4 : Autoriser le Lancement sur l iPhone (1ère fois seulement)

Par sécurité, iOS bloque le premier lancement des applications installées hors App Store tant que vous n avez pas approuvé le certificat de votre propre compte :

1. Sur votre iPhone, ouvrez :
   * **Réglages** > **Général** > **Gestion des VPN et des appareils**.
2. Dans la section *App de développeur*, touchez votre adresse email Apple ID.
3. Touchez **Faire confiance à [Votre Email]**.
4. Revenez sur l écran d accueil et ouvrez **BABIFIX** : l application se lance à 100 % !

---

## 6. Remarques Importantes

* **Durée du certificat gratuit** : avec un compte Apple ID gratuit, l application reste active 7 jours sur l iPhone. Il suffit de rebrancher le câble et de recliquer sur *Start* dans Sideloadly pour renouveler 7 jours de plus.
* **Si vous achetez plus tard un compte Apple Developer (99 $/an)** : le certificat dure alors 1 an complet et vous pouvez même distribuer l application sans câble via TestFlight.
