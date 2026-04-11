import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'babifix_api_config.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> babifixFcmBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
      FirebaseMessaging.onBackgroundMessage(babifixFcmBackgroundHandler);
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      debugPrint('BABIFIX FCM: init ignorée ($e) — exécutez `flutterfire configure` et ajoutez google-services.json.');
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
