# 🚀 Commandes BABIFIX — Cheat-sheet

> **Chemin du projet** : `C:\Users\kouay\Documents\BABIFIX_BUILD\`
> ⚠️ Toutes les commandes partent de ce dossier (PAS du `.claude\worktrees\`)

---

## 🟢 1. PREMIÈRE FOIS — Setup initial

À faire UNE SEULE FOIS (ou après avoir cloné le projet ailleurs).

### 1.1 Backend Django

```powershell
cd C:\Users\kouay\Documents\BABIFIX_BUILD\babifix_admin_django

# Active l'env Python (si tu en as un)
# Sinon ignore cette ligne

# Vérifie/applique les migrations
python manage.py migrate

# (Optionnel) crée un compte admin si pas déjà fait
python manage.py createsuperuser
```

### 1.2 App Client Flutter

```powershell
cd C:\Users\kouay\Documents\BABIFIX_BUILD\babifix_client_flutter
flutter clean
flutter pub get
```

### 1.3 App Prestataire Flutter

```powershell
cd C:\Users\kouay\Documents\BABIFIX_BUILD\babifix_prestataire_flutter
flutter clean
flutter pub get
```

### 1.4 Vitrine (site web)

```powershell
cd C:\Users\kouay\Documents\BABIFIX_BUILD\babifix_vitrine_django
python manage.py migrate
```

---

## 🚀 2. LANCEMENT QUOTIDIEN — 4 terminaux

Ouvre **4 terminaux PowerShell** en parallèle.

### Terminal 1 — Backend Django (avec WebSockets via Daphne)

```powershell
cd C:\Users\kouay\Documents\BABIFIX_BUILD\babifix_admin_django
python -m daphne -b 0.0.0.0 -p 8002 config.asgi:application
```

➡️ Backend accessible sur :
- API : http://localhost:8002/api/...
- Admin panel : http://localhost:8002/admin/
- Dashboard custom : http://localhost:8002/

### Terminal 2 — App Client Flutter

```powershell
cd C:\Users\kouay\Documents\BABIFIX_BUILD\babifix_client_flutter
flutter devices                # liste les émulateurs/téléphones
flutter run                    # lance sur le device choisi
```

Quand l'app tourne, dans le terminal :
- `r` = hot reload
- `R` = hot restart
- `q` = quitter

### Terminal 3 — App Prestataire Flutter

```powershell
cd C:\Users\kouay\Documents\BABIFIX_BUILD\babifix_prestataire_flutter
flutter run
```

### Terminal 4 — Vitrine (site web)

```powershell
cd C:\Users\kouay\Documents\BABIFIX_BUILD\babifix_vitrine_django
python manage.py runserver 0.0.0.0:8001
```

➡️ Vitrine accessible sur http://localhost:8001/

---

## 📱 3. ÉMULATEUR ANDROID — préparer pour tests

```powershell
# Si l'émulateur ne démarre pas, le lancer manuellement :
& "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -list-avds
& "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -avd Pixel_10_Pro

# Forcer une position GPS à Abidjan (utile pour le matching) :
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" emu geo fix -3.989 5.345

# Accorder permission location :
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" shell pm grant com.babifix.client android.permission.ACCESS_FINE_LOCATION
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" shell pm grant com.babifix.prestataire android.permission.ACCESS_FINE_LOCATION
```

---

## 🛠️ 4. COMMANDES DE MAINTENANCE

### Quand tu as modifié un modèle Django

```powershell
cd C:\Users\kouay\Documents\BABIFIX_BUILD\babifix_admin_django
python manage.py makemigrations
python manage.py migrate
```

### Quand tu as modifié `pubspec.yaml` Flutter

```powershell
cd C:\Users\kouay\Documents\BABIFIX_BUILD\babifix_client_flutter
flutter pub get
```

### Vider la base de données et tout rebooter

```powershell
# ⚠️ ATTENTION : supprime TOUTES les données

cd C:\Users\kouay\Documents\BABIFIX_BUILD\babifix_admin_django
python manage.py flush --no-input
python manage.py migrate
python manage.py createsuperuser
```

### Compiler un APK Android (release)

```powershell
# Client
cd C:\Users\kouay\Documents\BABIFIX_BUILD\babifix_client_flutter
flutter build apk --release
# → APK ici : build\app\outputs\flutter-apk\app-release.apk

# Prestataire
cd C:\Users\kouay\Documents\BABIFIX_BUILD\babifix_prestataire_flutter
flutter build apk --release
```

### Installer l'APK sur émulateur sans flutter run

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r babifix_client_flutter\build\app\outputs\flutter-apk\app-debug.apk
```

---

## 🩺 5. DIAGNOSTIC — si quelque chose ne marche pas

### Backend ne répond pas

```powershell
# Vérifier qu'il écoute bien sur 8002
netstat -ano | findstr :8002

# Tuer un processus zombi
taskkill /F /PID <PID_TROUVE>

# Tester l'API
curl http://localhost:8002/api/public/categories/
```

### App Flutter ne se connecte pas au backend

L'émulateur Android utilise `10.0.2.2:8002` pour atteindre le PC.
Un vrai téléphone Wi-Fi : utiliser l'IP locale du PC (`ipconfig` pour la trouver).

### Notifications FCM ne fonctionnent pas

```powershell
cd C:\Users\kouay\Documents\BABIFIX_BUILD\babifix_admin_django
python manage.py push_test
```

### Vérifier GeniusPay (sandbox)

```powershell
cd C:\Users\kouay\Documents\BABIFIX_BUILD\babifix_admin_django
python manage.py watch_geniuspay --interval 60
```

---

## 📤 6. PUSH SUR GITHUB

### Voir ce qui a changé

```powershell
cd C:\Users\kouay\Documents\BABIFIX_BUILD
git status
git diff
```

### Commit + push

```powershell
git add .
git commit -m "Description courte de ce que tu as fait"
git push origin master
```

### Récupérer les dernières modifs depuis GitHub

```powershell
git pull origin master
```

---

## 🎯 7. COMMANDES UTILES SUPPLÉMENTAIRES

### Lancer les tests automatiques

```powershell
cd C:\Users\kouay\Documents\BABIFIX_BUILD\babifix_admin_django
python manage.py test adminpanel
```

### Charger des données de démo

```powershell
cd C:\Users\kouay\Documents\BABIFIX_BUILD\babifix_admin_django
python manage.py seed_full_demo
```

### Lancer le diagnostic E2E

```powershell
cd C:\Users\kouay\Documents\BABIFIX_BUILD\babifix_admin_django
python manage.py e2e_debug
```

### Logs Daphne dans un fichier

```powershell
cd C:\Users\kouay\Documents\BABIFIX_BUILD\babifix_admin_django
python -m daphne -b 0.0.0.0 -p 8002 config.asgi:application 2>&1 | Tee-Object -FilePath daphne.log
```

---

## 🔗 URLs UTILES

| Service | URL |
|---------|-----|
| Backend API | http://localhost:8002/api/ |
| Admin Django | http://localhost:8002/admin/ |
| Dashboard custom | http://localhost:8002/ |
| Vitrine | http://localhost:8001/ |
| GitHub | https://github.com/yvan2007/new-babifixbuild |

---

## 📞 CONTACT BACKEND DEPUIS L'APP

| Cas | URL à utiliser |
|-----|----------------|
| **Émulateur Android** | `http://10.0.2.2:8002` |
| **iOS Simulator** | `http://localhost:8002` |
| **Vrai téléphone (Wi-Fi)** | `http://<IP-DU-PC>:8002` |
| **Production** | (à configurer dans `.env`) |
