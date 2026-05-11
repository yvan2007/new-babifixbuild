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

/// ZEGOCLOUD Voice/Video Call (Appels masqués client-prestataire)
/// Obtenez ces valeurs sur https://console.zegocloud.com/
/// Peut être défini via --dart-define ou fichier .env
int get kZegoAppID => _envInt('ZEGO_APP_ID', const int.fromEnvironment('ZEGO_APP_ID', defaultValue: 0));
String get kZegoAppSign => _envString('ZEGO_APP_SIGN', const String.fromEnvironment('ZEGO_APP_SIGN', defaultValue: ''));

bool get isZegoConfigured => kZegoAppID != 0 && kZegoAppSign.isNotEmpty;

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
  // Priorité 1 : variable dart-define (CI/CD, builds custom)
  const fromEnv = String.fromEnvironment('BABIFIX_API_BASE', defaultValue: '');
  if (fromEnv.isNotEmpty) return fromEnv.replaceAll(RegExp(r'/$'), '');

  // Priorité 2 : debug local → localhost:8002
  if (kDebugMode) {
    if (kIsWeb) return 'http://127.0.0.1:$kBabifixApiPort';
    if (defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:$kBabifixApiPort';
    return 'http://localhost:$kBabifixApiPort';
  }

  // Priorité 3 : release → serveur Render
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
