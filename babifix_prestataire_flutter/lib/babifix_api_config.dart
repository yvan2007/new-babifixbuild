import 'package:flutter/foundation.dart';

const int kBabifixApiPort = 8003;
const String kBabifixApiIpDesktop = '127.0.0.1';
const String kBabifixApiIpAndroid = '10.0.2.2';

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

String babifixApiBaseUrl() {
  const fromEnv = String.fromEnvironment('BABIFIX_API_BASE', defaultValue: '');
  if (fromEnv.isNotEmpty) {
    return fromEnv.replaceAll(RegExp(r'/$'), '');
  }
  if (kIsWeb) {
    return 'http://$kBabifixApiIpDesktop:$kBabifixApiPort';
  }
  if (defaultTargetPlatform == TargetPlatform.android) {
    return 'http://$kBabifixApiIpAndroid:$kBabifixApiPort';
  }
  return 'http://$kBabifixApiIpDesktop:$kBabifixApiPort';
}

/// WebSocket (Django Channels) — même hôte/port que l’API HTTP.
String babifixWsBaseUrl() {
  final u = babifixApiBaseUrl();
  if (u.startsWith('https://')) {
    return u.replaceFirst('https://', 'wss://');
  }
  return u.replaceFirst('http://', 'ws://');
}
