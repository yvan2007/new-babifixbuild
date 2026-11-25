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

/// LiveKit Voice/Video Call.
///
/// SÉCURITÉ : la clé API et le secret LiveKit **ne sont plus jamais**
/// embarqués dans l'app mobile. Ils étaient hardcodés ici dans une
/// version antérieure — quiconque décompilait l'APK pouvait signer
/// des tokens. Désormais TOUTE génération de token passe par le
/// backend (`POST /api/livekit/token` ou `POST /api/calls/initiate`),
/// qui détient seul la clé via la variable d'environnement Django
/// `LIVEKIT_API_SECRET`.
///
/// L'URL du serveur LiveKit est publique (wss://...livekit.cloud), donc
/// pas sensible — elle est renvoyée par le backend dans la réponse de
/// chaque demande de token. L'app n'a plus aucune config LiveKit à
/// connaître.
///
/// (Les anciennes constantes `kLiveKitApiKey`, `kLiveKitApiSecret`,
/// `kLiveKitUrl` et `isLiveKitConfigured` ont été retirées.)

/// Port du `python manage.py runserver` (aligné doc BABIFIX).
const int kBabifixApiPort = 8000;

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
///   python manage.py runserver 0.0.0.0:8000
const String kBabifixLocalIp =
    String.fromEnvironment('BABIFIX_LOCAL_IP', defaultValue: '');

/// Base URL backend — auto-détectée pour que ça marche partout sans config :
///
/// - **Émulateur Android** (debug) → `http://10.0.2.2:8000`
///   (10.0.2.2 = adresse spéciale qui pointe sur ton PC depuis l'émulateur)
/// - **iOS Simulator / Web** (debug) → `http://localhost:8000`
/// - **Vrai téléphone** sur Wi-Fi du PC : passer
///   `--dart-define=BABIFIX_LOCAL_IP=192.168.x.x` → `http://192.168.x.x:8000`
/// - **APK release** (publication) → Render production
///
/// Overrides explicites (priorité plus haute) :
/// 1. `BabifixApiOverride.set(...)` (runtime, depuis l'app)
/// 2. `--dart-define=BABIFIX_API_BASE=https://xxx` (override total)
/// 3. `--dart-define=BABIFIX_LOCAL_IP=192.168.x.x` (téléphone réel)
///
/// IMPORTANT : ton Django doit ÉCOUTER sur toutes les interfaces pour
/// que l'émulateur ET les vrais téléphones puissent y accéder :
///   python manage.py runserver 0.0.0.0:8000
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

/// Normalise une URL media/static vers le backend actif (utile si cree depuis 127.0.0.1 et lu sur 10.0.2.2 ou inversement).
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
