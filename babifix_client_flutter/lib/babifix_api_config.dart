import 'package:flutter/foundation.dart';

// ── Dart-define environment variables ────────────────────────────────────────
// Usage :
//   flutter run  --dart-define=BABIFIX_API_BASE=https://api.babifix.app
//                --dart-define=BABIFIX_ENV=production
//                --dart-define=BABIFIX_SENTRY_DSN=https://xxx@sentry.io/yyy
//
// In CI/CD add to `flutter build apk --dart-define=...`

/// Environnement courant : development | staging | production
const kBabifixEnv = String.fromEnvironment(
  'BABIFIX_ENV',
  defaultValue: 'development',
);

/// DSN Sentry (vide en dev)
const kBabifixSentryDsn = String.fromEnvironment(
  'BABIFIX_SENTRY_DSN',
  defaultValue: '',
);

/// Port du `python manage.py runserver` (aligné doc BABIFIX).
const int kBabifixApiPort = 8003;

/// IP locale de ton电脑 (remplace par ton IP réelle)
const String kBabifixApiIp =
    '10.0.2.2'; // <-- IP émulateur Android vers localhost
const String kBabifixApiIpDesktop =
    '127.0.0.1'; // <-- IP pour Windows/Mac/Linux/Web

/// Base URL du backend.
///
/// Override via `--dart-define=BABIFIX_API_BASE=https://api.babifix.app`
String babifixApiBaseUrl() {
  const fromEnv = String.fromEnvironment('BABIFIX_API_BASE', defaultValue: '');
  if (fromEnv.isNotEmpty) {
    return fromEnv.replaceAll(RegExp(r'/$'), '');
  }
  if (kIsWeb) {
    return 'http://$kBabifixApiIpDesktop:$kBabifixApiPort';
  }
  if (defaultTargetPlatform == TargetPlatform.android) {
    return 'http://$kBabifixApiIp:$kBabifixApiPort';
  }
  return 'http://$kBabifixApiIpDesktop:$kBabifixApiPort';
}

/// WebSocket Django Channels.
String babifixWsBaseUrl() {
  final u = babifixApiBaseUrl();
  if (u.startsWith('https://')) return u.replaceFirst('https://', 'wss://');
  return u.replaceFirst('http://', 'ws://');
}

bool get kIsProd => kBabifixEnv == 'production';
bool get kIsStaging => kBabifixEnv == 'staging';
