# Parties B, C, D — Flutter + Django + iOS (BABIFIX)

## État dans ce dépôt (déjà fait pour toi)

- `google-services.json` + `lib/firebase_options.dart` **Android** pour les deux apps (projet Firebase `babifix`).
- Django : chargement de **`.env`** + exemple `FIREBASE_CREDENTIALS_JSON_PATH` (fichier `.env` local, non versionné).

---

## Partie B — Flutter

### B1 — Outils (une fois sur la machine)

```powershell
dart pub global activate flutterfire_cli
```

Assure-toi que `flutter` et `dart` sont dans le PATH.

### B2 — Dépendances (les deux apps)

```powershell
cd C:\Users\YVXN20\Downloads\BABIFIX_BUILD\babifix_client_flutter
flutter pub get

cd C:\Users\YVXN20\Downloads\BABIFIX_BUILD\babifix_prestataire_flutter
flutter pub get
```

### B3 — `flutterfire configure` (optionnel pour Android)

Si **`firebase_options.dart`** est déjà rempli (comme dans ce repo), tu peux **sauter** cette étape pour Android.

Sinon, **depuis chaque dossier d’app** (pas depuis `babifix_admin_django`) :

```powershell
cd C:\Users\YVXN20\Downloads\BABIFIX_BUILD\babifix_client_flutter
flutterfire configure
```

- Choisis le projet **babifix**.
- Coche **Android** (et **iOS** si tu développes sur iPhone).

Puis idem pour le prestataire :

```powershell
cd C:\Users\YVXN20\Downloads\BABIFIX_BUILD\babifix_prestataire_flutter
flutterfire configure
```

### B4 — URL de l’API (`babifix_api_config.dart`)

Par défaut le code utilise le **port 8002** :

| Cible | URL utilisée |
|--------|----------------|
| **Émulateur Android** | `http://10.0.2.2:8002` |
| **Web / simulateur iOS / desktop** | `http://127.0.0.1:8002` |

**Téléphone physique (Wi‑Fi)** : lance l’app avec une base URL complète :

```powershell
flutter run --dart-define=BABIFIX_API_BASE=http://192.168.X.X:8002
```

(Remplace `192.168.X.X` par l’IPv4 de ton PC, même réseau Wi‑Fi ; pare-feu Windows : autoriser le port 8002.)

**USB + adb reverse** (alternative) :

```powershell
adb reverse tcp:8002 tcp:8002
flutter run --dart-define=BABIFIX_API_BASE=http://127.0.0.1:8002
```

### B5 — Lancer les apps

```powershell
cd ...\babifix_client_flutter
flutter run

cd ...\babifix_prestataire_flutter
flutter run
```

Après **login API**, vérifie dans Django admin : **Device tokens**.

---

## Partie C — Backend Django

### C1

```powershell
cd C:\Users\YVXN20\Downloads\BABIFIX_BUILD\babifix_admin_django
pip install -r requirements.txt
```

### C2 — `.env`

Fichier **`babifix_admin_django\.env`** (créé localement, dans `.gitignore`) :

```env
FIREBASE_CREDENTIALS_JSON_PATH=C:/Users/TON_USER/Downloads/babifix-firebase-adminsdk-....json
```

Optionnel : `REDIS_URL`, `DJANGO_SECRET_KEY`, `DJANGO_DEBUG=False`, `DJANGO_ALLOWED_HOSTS=...`

### C3

```powershell
python manage.py migrate
python manage.py runserver 0.0.0.0:8002
```

Le **port 8002** doit correspondre à `babifix_api_config.dart` / `--dart-define`.

### C4 — Test FCM

1. Login dans une app → entrée **DeviceToken**.
2. Action métier (réservation, statut…) → notification si Firebase Admin SDK est valide.

---

## Partie D — iOS (plus tard)

1. Firebase : ajouter app **iOS** + Bundle ID Xcode.
2. Télécharger **`GoogleService-Info.plist`** → `ios/Runner/`.
3. `flutterfire configure` dans chaque projet Flutter (cocher iOS).
4. Xcode : **Push Notifications** ; Firebase : clé **APNs** (Cloud Messaging).

---

## Tableau « tout est bon »

| Vérification | OK si… |
|--------------|--------|
| Firebase | Projet `babifix`, apps Android avec bons packages. |
| Fichiers | `android/app/google-services.json` présents ; `firebase_options.dart` cohérent. |
| Flutter | `flutter pub get` OK ; `flutter run` sans erreur réseau vers l’API. |
| Django | `.env` avec chemin Admin SDK ; `migrate` OK ; `runserver 0.0.0.0:8002`. |
| Réseau | Téléphone : `--dart-define=BABIFIX_API_BASE=...` ou `adb reverse`. |
| FCM | **Device tokens** remplis après login ; push reçus après action métier. |
