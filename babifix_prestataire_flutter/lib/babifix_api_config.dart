import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

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

/// LiveKit Voice/Video Call.
///
/// SÉCURITÉ : la clé API et le secret LiveKit **ne sont plus jamais**
/// embarqués dans l'app mobile. Toute génération de token passe par le
/// backend (`POST /api/livekit/token` ou `POST /api/calls/initiate`),
/// qui détient seul la clé via `LIVEKIT_API_SECRET` (env Django).

/// Port du `python manage.py runserver` (aligné doc BABIFIX).
const int kBabifixApiPort = 8000;

/// URL production (Render).
const String kBabifixProdUrl = 'https://new-babifixbuild.onrender.com';

/// IP locale du PC dev sur le Wi-Fi (pour vrais téléphones).
/// flutter run --dart-define=BABIFIX_LOCAL_IP=192.168.x.x
const String kBabifixLocalIp =
    String.fromEnvironment('BABIFIX_LOCAL_IP', defaultValue: '');

/// Base URL backend — auto-détectée pour que ça marche partout sans config :
///
/// - **Émulateur Android** (debug) → `http://10.0.2.2:8000`
/// - **iOS Simulator / Web** (debug) → `http://localhost:8000`
/// - **Vrai téléphone** sur Wi-Fi : `--dart-define=BABIFIX_LOCAL_IP=192.168.x.x`
/// - **APK release** → Render production
///
/// Ton Django doit écouter sur toutes les interfaces :
///   python manage.py runserver 0.0.0.0:8000
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

  if (kDebugMode) {
    if (kIsWeb) return 'http://127.0.0.1:$kBabifixApiPort';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:$kBabifixApiPort';
    }
    return 'http://localhost:$kBabifixApiPort';
  }

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

/// Auto-détecte en mode debug le port local du backend API Django (8000 ou 8011)
/// pour éviter les erreurs 404 si la Vitrine occupe le port 8000.
Future<void> babifixResolveLocalApiBaseUrl() async {
  if (!kDebugMode) return;
  if (BabifixApiOverride.current != null &&
      BabifixApiOverride.current!.isNotEmpty) {
    return;
  }
  const fromEnv = String.fromEnvironment('BABIFIX_API_BASE', defaultValue: '');
  if (fromEnv.isNotEmpty) return;

  final host = kBabifixLocalIp.isNotEmpty
      ? kBabifixLocalIp
      : (kIsWeb
          ? '127.0.0.1'
          : (defaultTargetPlatform == TargetPlatform.android
              ? '10.0.2.2'
              : 'localhost'));

  final ports = <int>[
    8011,
    if (kBabifixApiPort != 8011) kBabifixApiPort,
    if (kBabifixApiPort != 8000 && 8000 != 8011) 8000,
  ];
  for (final port in ports) {
    final candidate = 'http://$host:$port';
    try {
      final res = await http
          .get(Uri.parse('$candidate/api/health/'))
          .timeout(const Duration(milliseconds: 800));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map && decoded['status'] == 'ok') {
          if (port != kBabifixApiPort) {
            BabifixApiOverride.set(candidate);
          }
          debugPrint('[BabifixApiConfig] Backend API détecté sur $candidate');
          return;
        }
      }
    } catch (_) {}
  }
}

/// WebSocket Django Channels.
String babifixWsBaseUrl() {
  final u = babifixApiBaseUrl();
  if (u.startsWith('https://')) return u.replaceFirst('https://', 'wss://');
  return u.replaceFirst('http://', 'ws://');
}

/// Normalise une URL media/static vers le backend actif (127.0.0.1 / 10.0.2.2 / localhost).
String babifixResolveMediaUrl(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return '';
  if (s.startsWith('assets/') || s.startsWith('data:')) return s;
  final base = babifixApiBaseUrl();
  if (s.startsWith('/')) return '$base$s';
  if (s.startsWith('media/') || s.startsWith('static/')) return '$base/$s';
  final parsed = Uri.tryParse(s);
  if (parsed != null &&
      parsed.hasAuthority &&
      (parsed.host == '127.0.0.1' ||
          parsed.host == 'localhost' ||
          parsed.host == '10.0.2.2' ||
          parsed.host == '0.0.0.0')) {
    return '$base${parsed.path}${parsed.hasQuery ? '?${parsed.query}' : ''}';
  }
  return s;
}

bool get kIsProd => kBabifixEnv == 'production';
bool get kIsStaging => kBabifixEnv == 'staging';
