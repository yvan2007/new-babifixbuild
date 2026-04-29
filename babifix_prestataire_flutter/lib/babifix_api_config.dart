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
    // En prod iOS, utiliser l'IP du réseau local
    return 'http://192.168.1.100:$kBabifixApiPort';
  }

  // Android emulator (AVD) → 10.0.2.2 host loopback
  if (defaultTargetPlatform == TargetPlatform.android) {
    // Détection émulateur vs device réel
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      // Flutter desktop ciblant Android (rare)
      return 'http://10.0.2.2:$kBabifixApiPort';
    }
    // Device Android émulateur
    return 'http://10.0.2.2:$kBabifixApiPort';
  }

  // Desktop Windows/Mac/Linux
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    return 'http://127.0.0.1:$kBabifixApiPort';
  }

  // Fallback par défaut
  return 'http://127.0.0.1:$kBabifixApiPort';
}

/// WebSocket Django Channels.
String babifixWsBaseUrl() {
  final u = babifixApiBaseUrl();
  if (u.startsWith('https://')) return u.replaceFirst('https://', 'wss://');
  return u.replaceFirst('http://', 'ws://');
}

bool get kIsProd => kBabifixEnv == 'production';
bool get kIsStaging => kBabifixEnv == 'staging';
