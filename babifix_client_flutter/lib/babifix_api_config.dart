import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

int _envInt(String key, int defaultValue) {
  final v = dotenv.env[key];
  if (v == null || v.isEmpty) return defaultValue;
  final parsed = int.tryParse(v);
  return parsed ?? defaultValue;
}

String _envString(String key, String defaultValue) {
  return dotenv.env[key] ?? defaultValue;
}

// ── Dart-define environment variables ────────────────────────────────────────
// Usage :
//   flutter run  --dart-define=BABIFIX_API_BASE=https://api.babifix.app
//                --dart-define=BABIFIX_ENV=production
//                --dart-define=BABIFIX_SENTRY_DSN=https://xxx@sentry.io/yyy
//
// In CI/CD add to `flutter build apk --dart-define=...`

/// Environment courant : development | staging | production
const kBabifixEnv = String.fromEnvironment(
  'BABIFIX_ENV',
  defaultValue: 'development',
);

/// DSN Sentry (vide en dev)
const kBabifixSentryDsn = String.fromEnvironment(
  'BABIFIX_SENTRY_DSN',
  defaultValue: '',
);

/// ZEGOCLOUD Voice/Video Call (deprecated)
/// Obtenez ces valeurs sur https://console.zegocloud.com/
/// Peut être défini via --dart-define ou fichier .env
int get kZegoAppID => _envInt('ZEGO_APP_ID', const int.fromEnvironment('ZEGO_APP_ID', defaultValue: 0));
String get kZegoAppSign => _envString('ZEGO_APP_SIGN', const String.fromEnvironment('ZEGO_APP_SIGN', defaultValue: ''));

bool get isZegoConfigured => kZegoAppID != 0 && kZegoAppSign.isNotEmpty;

/// LiveKit Voice/Video Call (nouveau)
/// Obtenez ces valeurs sur https://cloud.livekit.io
/// Peut être défini via --dart-define ou fichier .env
const _defaultLiveKitUrl = 'wss://babifix-h1giwqew.livekit.cloud';
const _defaultLiveKitApiKey = 'APIHmepmCSoou3K';
const _defaultLiveKitApiSecret = 'Cets7RORRaNS61Ie4dyCY0rE33lyzxTBrG7NYQifs6IA';

String? _envStringSafe(String key) {
  try {
    return dotenv.env[key];
  } catch (_) {
    return null;
  }
}

String _envStringWithFallback(String key, String fallback) {
  final fromEnv = _envStringSafe(key);
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  return fallback;
}

String get kLiveKitUrl => _envStringWithFallback('LIVEKIT_URL', _defaultLiveKitUrl);
String get kLiveKitApiKey => _envStringWithFallback('LIVEKIT_API_KEY', _defaultLiveKitApiKey);
String get kLiveKitApiSecret => _envStringWithFallback('LIVEKIT_API_SECRET', _defaultLiveKitApiSecret);

bool get isLiveKitConfigured => kLiveKitUrl.isNotEmpty && kLiveKitApiKey.isNotEmpty && kLiveKitApiSecret.isNotEmpty;

/// Port du `python manage.py runserver` (aligné doc BABIFIX).
const int kBabifixApiPort = 8002;

/// URL backend production (Render).
const String kBabifixProdUrl = 'https://new-babifixbuild.onrender.com';

/// IP locale du PC dev sur le réseau Wi-Fi (pour les VRAIS téléphones).
///
/// Compile avec :
///   flutter run --dart-define=BABIFIX_LOCAL_IP=192.168.1.42
///
/// Sur ton PC, dans un terminal :
///   ipconfig            (Windows) → adresse IPv4 de la carte Wi-Fi
///   ifconfig | grep inet (Mac/Linux)
///
/// IMPORTANT : ton Django doit ÉCOUTER sur toutes les interfaces :
///   python manage.py runserver 0.0.0.0:8002
const String kBabifixLocalIp =
    String.fromEnvironment('BABIFIX_LOCAL_IP', defaultValue: '');

/// Base URL backend — auto-détectée pour que ça marche partout sans config :
///
/// - **Émulateur Android** (debug) → `http://10.0.2.2:8002`
///   (10.0.2.2 = adresse spéciale qui pointe sur ton PC depuis l'émulateur)
/// - **iOS Simulator / Web** (debug) → `http://localhost:8002`
/// - **Vrai téléphone** sur Wi-Fi du PC : passer
///   `--dart-define=BABIFIX_LOCAL_IP=192.168.x.x` → `http://192.168.x.x:8002`
/// - **APK release** (publication) → Render production
///
/// Overrides explicites (priorité plus haute) :
/// 1. `BabifixApiOverride.set(...)` (runtime, depuis l'app)
/// 2. `--dart-define=BABIFIX_API_BASE=https://xxx` (override total)
/// 3. `--dart-define=BABIFIX_LOCAL_IP=192.168.x.x` (téléphone réel)
///
/// IMPORTANT : ton Django doit ÉCOUTER sur toutes les interfaces pour
/// que l'émulateur ET les vrais téléphones puissent y accéder :
///   python manage.py runserver 0.0.0.0:8002
String babifixApiBaseUrl() {
  // 1. Runtime override
  final ov = BabifixApiOverride.current;
  if (ov != null && ov.isNotEmpty) {
    return ov.replaceAll(RegExp(r'/$'), '');
  }

  // 2. dart-define BABIFIX_API_BASE (override total)
  const fromEnv = String.fromEnvironment('BABIFIX_API_BASE', defaultValue: '');
  if (fromEnv.isNotEmpty) return fromEnv.replaceAll(RegExp(r'/$'), '');

  // 3. dart-define BABIFIX_LOCAL_IP (téléphone réel sur Wi-Fi du dev)
  if (kBabifixLocalIp.isNotEmpty) {
    return 'http://$kBabifixLocalIp:$kBabifixApiPort';
  }

  // 4. Debug : détection auto par plateforme
  if (kDebugMode) {
    if (kIsWeb) return 'http://127.0.0.1:$kBabifixApiPort';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:$kBabifixApiPort';
    }
    return 'http://localhost:$kBabifixApiPort';
  }

  // 5. Release sans override → Render production
  return kBabifixProdUrl;
}

/// Mécanisme d'override runtime pour pouvoir changer l'URL backend
/// depuis l'app (écran caché « Settings backend » utile en démo).
abstract final class BabifixApiOverride {
  static String? _current;
  static String? get current => _current;
  static void set(String? url) {
    if (url == null || url.trim().isEmpty) {
      _current = null;
    } else {
      _current = url.trim();
    }
  }
}

/// WebSocket Django Channels.
String babifixWsBaseUrl() {
  final u = babifixApiBaseUrl();
  if (u.startsWith('https://')) return u.replaceFirst('https://', 'wss://');
  return u.replaceFirst('http://', 'ws://');
}

bool get kIsProd => kBabifixEnv == 'production';
bool get kIsStaging => kBabifixEnv == 'staging';
