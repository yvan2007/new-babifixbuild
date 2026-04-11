# Configuration Firebase Cloud Messaging (BABIFIX)

## 1. Console Firebase

1. Créez un projet sur [Firebase Console](https://console.firebase.google.com/).
2. Ajoutez une app **Android** (`com.babifix.client` / `com.babifix.prestataire`) et **iOS** si besoin.
3. Téléchargez `google-services.json` (Android) et `GoogleService-Info.plist` (iOS).

## 2. Flutter (client + prestataire)

Pour **Android**, le dépôt peut déjà contenir `android/app/google-services.json` et `lib/firebase_options.dart` (projet `babifix`). Il suffit alors de :

```bash
cd babifix_client_flutter   # puis babifix_prestataire_flutter
flutter pub get
flutter run
```

Pour **iOS** ou tout régénérer :

```bash
dart pub global activate flutterfire_cli
flutterfire configure
flutter pub get
```

## 3. Backend Django (`babifix_admin_django`)

1. Firebase Console → **Paramètres du projet** → **Comptes de service** → **Générer une nouvelle clé privée** (JSON).
2. Stockez le fichier hors dépôt (ex. `secrets/babifix-firebase.json`).
3. Copiez `.env.example` vers **`.env`** à la racine de `babifix_admin_django`, ou créez `.env` avec :

```env
FIREBASE_CREDENTIALS_JSON_PATH=C:/chemin/vers/babifix-firebase-adminsdk-xxxxx.json
```

(`settings.py` charge ce fichier automatiquement ; **`.env` est dans `.gitignore`** — ne commitez pas la clé Admin SDK.)

4. Installez les dépendances : `pip install -r requirements.txt`
5. Migrations : `python manage.py migrate`

## 4. Flux

- Les apps appellent `POST /api/auth/fcm-token` avec le **Bearer JWT** après login.
- Le serveur enregistre les jetons dans `DeviceToken`.
- Lors d’un changement **réservation**, **prestataire**, **paiement lié**, **avis**, le backend envoie une notification FCM aux utilisateurs concernés (si Firebase est initialisé).

Sans fichier JSON côté serveur, les **API et le WebSocket admin** fonctionnent ; seul l’**envoi push** est ignoré.

## 5. Flutter **Windows** — erreurs CMake / ZIP / build

Si `flutter run -d windows` échoue avec :

- **`No space left on device`** ou **`Espace insuffisant sur le disque`**
- **`cmake -E tar: error: ZIP decompression failed (-5)`** (souvent lors de l’extraction du **Firebase C++ SDK**)

**Cause typique** : le disque (souvent `C:`) est **plein**. Les builds Windows + plugins (Firebase, geolocator, etc.) demandent **plusieurs Go** d’espace temporaire.

**Actions** :

1. Libérer de l’espace (viser **15–25 Go+** libres sur le lecteur du projet).
2. Dans chaque app Flutter : `flutter clean`, puis supprimer le dossier `build/` si besoin.
3. Relancer `flutter pub get` puis `flutter run -d windows`.

Si l’erreur ZIP persiste **après** avoir de l’espace : supprimer `build/windows` entièrement et reconstruire (fichiers extraits parfois corrompus quand le disque était plein).

**Erreur lien Visual Studio** : `LNK1106: fichier non valide ou disque plein` sur `firebase_app.lib` — même cause (disque plein ou `.lib` **tronqué** après une extraction ratée). Libérer de l’espace, puis `flutter clean`, supprimer `build\windows` **et** le dossier `build\windows\x64\extracted\firebase_cpp_sdk_windows` s’il existe, puis `flutter pub get` et relancer le build.
