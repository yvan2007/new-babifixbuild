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

/// Environment courant : development | staging | production
const String kBabifixEnv = String.fromEnvironment(
  'BABIFIX_ENV',
  defaultValue: 'development',
);

/// DSN Sentry (vide en dev)
const String kBabifixSentryDsn = String.fromEnvironment(
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

/// URL production (Render).
const String kBabifixProdUrl = 'https://new-babifixbuild.onrender.com';

/// IP locale du PC dev sur le Wi-Fi (pour vrais téléphones).
/// flutter run --dart-define=BABIFIX_LOCAL_IP=192.168.x.x
const String kBabifixLocalIp =
    String.fromEnvironment('BABIFIX_LOCAL_IP', defaultValue: '');

/// Base URL backend — par défaut : **toujours Render**.
///
/// Comme ça l'app marche peu importe où elle est ouverte (émulateur,
/// vrai téléphone, ordinateur de quelqu'un d'autre) sans avoir besoin
/// qu'un Django local tourne sur le PC du dev.
///
/// Pour basculer en local pendant le dev, utiliser EXPLICITEMENT :
///   flutter run --dart-define=BABIFIX_API_BASE=http://10.0.2.2:8002
///   flutter run --dart-define=BABIFIX_LOCAL_IP=192.168.x.x
///   ou BabifixApiOverride.set('http://10.0.2.2:8002') à l'exécution.
///
/// Priorités :
///  1. Runtime override (`BabifixApiOverride.set(...)`)
///  2. dart-define `BABIFIX_API_BASE`
///  3. dart-define `BABIFIX_LOCAL_IP` → `http://<IP>:8002`
///  4. Défaut universel → Render production
String babifixApiBaseUrl() {
  final ov = BabifixApiOverride.current;
  if (ov != null && ov.isNotEmpty) {
    return ov.replaceAll(RegExp(r'/$'), '');
  }

  const fromEnv = String.fromEnvironment('BABIFIX_API_BASE', defaultValue: '');
  if (fromEnv.isNotEmpty) return fromEnv.replaceAll(RegExp(r'/$'), '');

  if (kBabifixLocalIp.isNotEmpty) {
    return 'http://$kBabifixLocalIp:$kBabifixApiPort';
  }

  // Défaut : production Render — partout, sans config.
  return kBabifixProdUrl;
}

/// Override runtime — pour pouvoir changer l'URL backend sans rebuild.
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
