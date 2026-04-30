import 'dart:io';
import 'package:flutter/foundation.dart';

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

/// Port du `python manage.py runserver` (aligné doc BABIFIX).
const int kBabifixApiPort = 8002;

/// Base URL du backend.
///
/// Auto-détection plateforme :
/// - Web (Chrome, Edge) : localhost:8002
/// - Android Device/Emulator : 10.0.2.2 (émulateur) ou IP locale
/// - iOS Simulator/Device : localhost ou IP
/// - Windows/Mac/Linux : localhost
String babifixApiBaseUrl() {
  const fromEnv = String.fromEnvironment('BABIFIX_API_BASE', defaultValue: '');
  if (fromEnv.isNotEmpty) {
    return fromEnv.replaceAll(RegExp(r'/$'), '');
  }

  // Web browser
  if (kIsWeb) {
    return 'http://127.0.0.1:$kBabifixApiPort';
  }

  // iOS Simulator
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    if (kDebugMode) {
      return 'http://localhost:$kBabifixApiPort';
    }
    return 'https://new-babifixbuild.onrender.com';
  }

  // Android
  if (defaultTargetPlatform == TargetPlatform.android) {
    if (kDebugMode) {
      return 'http://10.0.2.2:$kBabifixApiPort';
    }
    return 'https://new-babifixbuild.onrender.com';
  }

  // Desktop Windows/Mac/Linux
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    return 'http://127.0.0.1:$kBabifixApiPort';
  }

  // Fallback production
  return 'https://new-babifixbuild.onrender.com';
}

/// WebSocket Django Channels.
String babifixWsBaseUrl() {
  final u = babifixApiBaseUrl();
  if (u.startsWith('https://')) return u.replaceFirst('https://', 'wss://');
  return u.replaceFirst('http://', 'ws://');
}

bool get kIsProd => kBabifixEnv == 'production';
bool get kIsStaging => kBabifixEnv == 'staging';
