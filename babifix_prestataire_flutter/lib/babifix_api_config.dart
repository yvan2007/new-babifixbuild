import 'package:flutter/foundation.dart';

const int kBabifixApiPort = 8000;

/// Environment injected via --dart-define at build time.
const String kBabifixEnv = String.fromEnvironment(
  'BABIFIX_ENV',
  defaultValue: 'development',
);
const String kBabifixSentryDsn = String.fromEnvironment(
  'BABIFIX_SENTRY_DSN',
  defaultValue: '',
);

bool get kIsProd => kBabifixEnv == 'production';
bool get kIsStaging => kBabifixEnv == 'staging';

/// Voir commentaires dans [babifix_client_flutter/lib/babifix_api_config.dart].
String babifixApiBaseUrl() {
  const fromEnv = String.fromEnvironment('BABIFIX_API_BASE', defaultValue: '');
  if (fromEnv.isNotEmpty) {
    return fromEnv.replaceAll(RegExp(r'/$'), '');
  }
  if (kIsWeb) {
    return 'http://127.0.0.1:$kBabifixApiPort';
  }
  if (defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:$kBabifixApiPort';
  }
  return 'http://127.0.0.1:$kBabifixApiPort';
}

/// WebSocket (Django Channels) — même hôte/port que l’API HTTP.
String babifixWsBaseUrl() {
  final u = babifixApiBaseUrl();
  if (u.startsWith('https://')) {
    return u.replaceFirst('https://', 'wss://');
  }
  return u.replaceFirst('http://', 'ws://');
}
