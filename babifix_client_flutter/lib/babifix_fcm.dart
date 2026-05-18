import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'babifix_api_config.dart';
import 'firebase_options.dart';
import 'services/fcm_router.dart';
import 'services/notification_sound_service.dart';

@pragma('vm:entry-point')
Future<void> babifixFcmBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await BabifixNotificationSoundService.ensureInitialized();
  final data = message.data;
  await BabifixNotificationSoundService.showNotification(
    id: DateTime.now().millisecondsSinceEpoch % 100000,
    title: message.notification?.title ?? data['title'] ?? 'BABIFIX',
    body: message.notification?.body ?? data['body'] ?? '',
    payload: data['route'] ?? data['type'] ?? '',
  );
}

/// Enregistrement FCM → API Django `POST /api/auth/fcm-token`.
class BabifixFcm {
  BabifixFcm._();

  static bool _initTried = false;
  static bool _refreshListening = false;

  static Future<void> ensureInitialized() async {
    if (_initTried) return;
    _initTried = true;
    if (kIsWeb) return;
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      if (kDebugMode) {
        try {
          // Sur Android émulateur, l'hôte est 10.0.2.2, pas localhost.
          final host = (!kIsWeb && Platform.isAndroid) ? '10.0.2.2' : 'localhost';
          await fb.FirebaseAuth.instance.useAuthEmulator(host, 9099);
        } catch (_) {}
      }
      FirebaseMessaging.onBackgroundMessage(babifixFcmBackgroundHandler);
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await BabifixNotificationSoundService.ensureInitialized();

      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    } catch (e) {
      debugPrint('BABIFIX FCM: init ignorée ($e) — exécutez `flutterfire configure` et ajoutez google-services.json.');
    }
  }

  static Future<void> _onForegroundMessage(RemoteMessage message) async {
    final data = message.data;
    final type = (data['type'] ?? '').toString();
    // Phase D — Ne PAS afficher de notification système pour un appel
    // entrant : on prend le contrôle via IncomingCallScreen fullscreen.
    if (type != 'call.incoming') {
      await BabifixNotificationSoundService.showNotification(
        id: DateTime.now().millisecondsSinceEpoch % 100000,
        title: message.notification?.title ?? data['title'] ?? 'BABIFIX',
        body: message.notification?.body ?? data['body'] ?? '',
        payload: data['route'] ?? data['type'] ?? '',
      );
    }
    // Dispatch typé (ouvre l'écran d'appel entrant ou snack contextuel).
    try {
      await BabifixFcmRouter.route(Map<String, dynamic>.from(data));
    } catch (e) {
      debugPrint('BABIFIX FCM router: $e');
    }
  }

  static String _platformLabel() {
    if (kIsWeb) return 'web';
    try {
      return Platform.isIOS ? 'ios' : 'android';
    } catch (_) {
      return 'android';
    }
  }

  /// À appeler après un login API réussi (JWT).
  static Future<void> registerTokenWithBackend(String apiBearerToken) async {
    if (apiBearerToken.isEmpty || kIsWeb) return;
    try {
      await ensureInitialized();
      final tok = await FirebaseMessaging.instance.getToken();
      if (tok == null || tok.isEmpty) return;

      Future<void> send(String t) async {
        final uri = Uri.parse('${babifixApiBaseUrl()}/api/auth/fcm-token');
        await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiBearerToken',
          },
          body: jsonEncode({'token': t, 'platform': _platformLabel()}),
        );
      }

      await send(tok);
      debugPrint('BABIFIX FCM: token enregistré côté serveur');

      if (!_refreshListening) {
        _refreshListening = true;
        FirebaseMessaging.instance.onTokenRefresh.listen((newTok) {
          send(newTok);
        });
      }
    } catch (e) {
      debugPrint('BABIFIX FCM register: $e');
    }
  }
}
