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

/// Base URL du backend.
///
/// Auto-détection plateforme :
/// - Web (Chrome, Edge) : localhost:8002
/// - Android Device/Emulator : 10.0.2.2 (émulateur) ou IP locale
/// - iOS Simulator/Device : localhost ou IP
/// - Windows/Mac/Linux : localhost
const String kBabifixProdUrl = 'https://new-babifixbuild.onrender.com';

String babifixApiBaseUrl() {
  const fromEnv = String.fromEnvironment('BABIFIX_API_BASE', defaultValue: '');
  if (fromEnv.isNotEmpty) return fromEnv.replaceAll(RegExp(r'/$'), '');

  if (kDebugMode) {
    if (kIsWeb) return 'http://127.0.0.1:$kBabifixApiPort';
    if (defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:$kBabifixApiPort';
    return 'http://localhost:$kBabifixApiPort';
  }

  return kBabifixProdUrl;
}

/// WebSocket Django Channels.
String babifixWsBaseUrl() {
  final u = babifixApiBaseUrl();
  if (u.startsWith('https://')) return u.replaceFirst('https://', 'wss://');
  return u.replaceFirst('http://', 'ws://');
}

bool get kIsProd => kBabifixEnv == 'production';
bool get kIsStaging => kBabifixEnv == 'staging';
