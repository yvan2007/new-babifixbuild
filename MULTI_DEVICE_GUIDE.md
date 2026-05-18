# 📱 Guide multi-device BABIFIX

Comment lancer les apps Flutter sur **émulateur ou téléphone réel**, en
gardant le backend Django joignable dans les deux cas.

## 🟢 Émulateur Android (cas le plus simple)

Le backend tourne sur ton PC à `localhost:8002`. L'émulateur Android voit
l'IP **`10.0.2.2`** pour atteindre l'hôte. C'est déjà câblé par défaut,
rien à configurer.

```bash
# Terminal 1 — Backend
cd babifix_admin_django
source ../venv/Scripts/activate
python manage.py runserver 127.0.0.1:8002

# Terminal 2 — App client
cd babifix_client_flutter
flutter run     # cible l'émulateur Android automatiquement

# Terminal 3 — App prestataire
cd babifix_prestataire_flutter
flutter run
```

## 📲 Téléphone Android réel sur le même Wi-Fi

3 étapes :

### Étape 1 — Trouver ton IP locale (PC)

**Windows** :
```powershell
ipconfig
# Cherche "Adresse IPv4" sur la carte Wi-Fi (ex: 192.168.1.42)
```

**Mac/Linux** :
```bash
ifconfig | grep "inet "
# ou
ip addr show
```

### Étape 2 — Lancer Django sur TOUTES les interfaces

```bash
python manage.py runserver 0.0.0.0:8002
```

⚠️ `0.0.0.0` (pas `127.0.0.1`) sinon le téléphone ne peut pas se connecter.

Puis sur le PC, ajoute l'IP à `DJANGO_ALLOWED_HOSTS` dans le `.env` :
```
DJANGO_ALLOWED_HOSTS=127.0.0.1,localhost,10.0.2.2,192.168.1.42,.ngrok-free.app
```

### Étape 3 — Compiler l'app avec ton IP

```bash
flutter run --dart-define=BABIFIX_LOCAL_IP=192.168.1.42
# Remplace par TON IP de l'étape 1
```

Le téléphone va alors appeler `http://192.168.1.42:8002/api/...` qui est
ton PC sur le Wi-Fi.

✅ Vérifie que le pare-feu Windows ne bloque pas le port 8002 (Defender peut
demander une autorisation au 1er run).

## 🌍 Téléphone hors Wi-Fi (4G / autre réseau)

Utilise **ngrok** pour exposer ton backend local sur le net.

```bash
# Installer une fois : https://ngrok.com/download
ngrok http 8002
# Récupère l'URL publique : https://xxxxx.ngrok-free.app
```

Puis :
```bash
flutter run --dart-define=BABIFIX_API_BASE=https://xxxxx.ngrok-free.app
```

L'URL ngrok est déjà autorisée dans `DJANGO_ALLOWED_HOSTS` (`.ngrok-free.app`).

## 🚀 Test contre la production Render

```bash
flutter run --dart-define=BABIFIX_API_BASE=https://new-babifixbuild.onrender.com
```

ou simplement `flutter build apk --release` qui pointera automatiquement
sur la prod.

## 🎛️ Override runtime (optionnel)

L'app expose `BabifixApiOverride.set(url)` qui prend le dessus sur tout
sans rebuild. Pratique pour un écran caché « Settings backend » :

```dart
// Quelque part dans un écran admin/dev
BabifixApiOverride.set('http://192.168.1.99:8002');
```

Pour revenir à la détection auto :
```dart
BabifixApiOverride.set(null);
```

## 📋 Ordre de priorité

1. **Runtime override** (`BabifixApiOverride.set(...)`)
2. **dart-define `BABIFIX_API_BASE`** (URL complète, override total)
3. **dart-define `BABIFIX_LOCAL_IP`** (juste l'IP, on ajoute http://...:8002)
4. **Debug + Android émulateur** → `http://10.0.2.2:8002`
5. **Debug + Web/iOS Simulator** → `http://localhost:8002`
6. **Release** → Render

## 🔌 WebSocket et FCM

- WebSocket : suit automatiquement la même base URL (`babifixWsBaseUrl()` la dérive).
- FCM (push notifications) : géré par Firebase indépendamment, fonctionne
  même si backend Django est en local (les notifs envoyées par Django via
  Firebase Admin SDK voyagent par Google, pas par le PC dev).

## ⚠️ Pièges courants

| Symptôme | Cause probable | Fix |
|---|---|---|
| Connection refused | Django sur 127.0.0.1 au lieu de 0.0.0.0 | `runserver 0.0.0.0:8002` |
| Bad Request 400 (host) | IP/hostname pas dans ALLOWED_HOSTS | Ajouter au `.env` |
| Téléphone et PC pas dans le même Wi-Fi | Réseau invité, hotspot... | Même Wi-Fi obligatoire |
| Pare-feu Windows bloque | 1er run | Autoriser au popup |
| iOS App Transport Security (ATS) | iOS bloque HTTP non sécurisé | Ajouter `NSAppTransportSecurity` au Info.plist |

## ✅ Test rapide depuis le téléphone

Une fois l'app installée, vérifie dans Chrome du téléphone que tu accèdes à :
```
http://<TON_IP>:8002/api/public/categories/
```
→ Tu dois voir le JSON des catégories. Si oui, l'app Flutter aussi peut s'y
connecter.
