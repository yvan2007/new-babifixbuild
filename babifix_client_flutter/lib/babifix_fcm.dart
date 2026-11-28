import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'babifix_api_config.dart';
import 'firebase_options.dart';
import 'services/fcm_router.dart';
import 'services/notification_sound_service.dart';
import 'user_store.dart';

@pragma('vm:entry-point')
Future<void> babifixFcmBackgroundHandler(RemoteMessage message) async {
  if (Platform.isIOS && DefaultFirebaseOptions.ios.appId.contains('CONFIGUREZ_IOS')) {
    return;
  }
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    final data = message.data;
    final type = (data['type'] ?? '').toString();
    // Si le payload contient deja un bloc `notification`, Android/iOS l'affiche
    // nativement dans le panneau systeme : ne pas dupliquer en local.
    if (message.notification != null || type == 'call.incoming') {
      return;
    }
    await BabifixNotificationSoundService.ensureInitialized();
    final title = (data['title'] ?? '').toString().trim();
    final body = (data['body'] ?? '').toString().trim();
    if (title.isEmpty && body.isEmpty) return;
    await BabifixNotificationSoundService.showNotification(
      id: DateTime.now().millisecondsSinceEpoch % 100000,
      title: title.isNotEmpty ? title : 'BABIFIX',
      body: body,
      payload: jsonEncode({
        'type': type,
        'reference': data['reference'] ?? '',
      }),
    );
  } catch (_) {}
}

/// Enregistrement FCM → API Django `POST /api/auth/fcm-token`.
class BabifixFcm {
  BabifixFcm._();

  static bool _initOK = false;
  static bool _initAttempted = false;
  static bool _refreshListening = false;

  /// Firebase est-il réellement initialisé ? (false sur iOS sans
  /// GoogleService-Info.plist → ne PAS toucher à FirebaseMessaging.instance).
  static bool get isReady => _initOK;

  static Future<void> ensureInitialized() async {
    if (_initOK) return;
    if (_initAttempted) return;
    _initAttempted = true;
    if (kIsWeb) return;
    // Toujours initialiser les notifications locales (taps, canaux, son) meme
    // si iOS APNs est encore en attente de GoogleService-Info.plist.
    await BabifixNotificationSoundService.ensureInitialized();
    if (Platform.isIOS && DefaultFirebaseOptions.ios.appId.contains('CONFIGUREZ_IOS')) {
      debugPrint('BABIFIX FCM: iOS Firebase non configure (options placeholder), FCM ignore.');
      return;
    }
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      try {
        await FirebaseMessaging.instance.setAutoInitEnabled(true);
        if (Platform.isIOS) {
          await FirebaseMessaging.instance
              .setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          );
        }
      } catch (_) {}
      if (kDebugMode) {
        try {
          // Sur Android émulateur, l'hôte est 10.0.2.2, pas localhost.
          final host = (!kIsWeb && Platform.isAndroid) ? '10.0.2.2' : 'localhost';
          await fb.FirebaseAuth.instance.useAuthEmulator(host, 9099);
        } catch (_) {}
      }
      FirebaseMessaging.onBackgroundMessage(babifixFcmBackgroundHandler);

      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      _initOK = true;
      debugPrint('BABIFIX FCM: initialisé avec succès');
    } catch (e) {
      debugPrint('BABIFIX FCM: init ignorée ($e)');
    }
  }

  static bool _prepromptShowing = false;

  /// Affiche une fiche blanche claire BABIFIX avant le dialogue Android natif,
  /// pour éviter le dialogue système brutal sur fond noir au lancement à froid.
  static Future<void> promptForPermissionIfNeeded(BuildContext context) async {
    if (kIsWeb || !_initOK || _prepromptShowing || !context.mounted) return;
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('babifix_notif_preprompt_v1') == true) return;
      final laterMs = prefs.getInt('babifix_notif_preprompt_later_ms') ?? 0;
      if (laterMs > 0 &&
          DateTime.now().millisecondsSinceEpoch - laterMs < 86400000) {
        return;
      }
      if (!context.mounted) return;

      _prepromptShowing = true;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final bg = isDark ? const Color(0xFF13223B) : Colors.white;
      final fg = isDark ? Colors.white : const Color(0xFF0B1B34);
      final sub = isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569);

      final wantEnable = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => Dialog(
          backgroundColor: bg,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.14)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0369A1).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.notifications_active_rounded,
                    size: 30,
                    color: isDark
                        ? const Color(0xFF4CC9F0)
                        : const Color(0xFF0369A1),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Activer vos alertes BABIFIX',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17.5,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Soyez prévenu dès qu\'un artisan vous envoie un devis, démarre son intervention ou vous écrit.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, height: 1.45, color: sub),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFC2410C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Activer les notifications',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(
                    'Plus tard',
                    style: TextStyle(
                      color: sub,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (wantEnable == true) {
        await prefs.setBool('babifix_notif_preprompt_v1', true);
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        final jwt = await BabifixUserStore.getApiToken();
        if (jwt != null && jwt.isNotEmpty) {
          await registerTokenWithBackend(jwt);
        }
      } else {
        await prefs.setInt(
          'babifix_notif_preprompt_later_ms',
          DateTime.now().millisecondsSinceEpoch,
        );
      }
    } catch (_) {
    } finally {
      _prepromptShowing = false;
    }
  }

  static Future<void> _onForegroundMessage(RemoteMessage message) async {
    debugPrint('BABIFIX FCM: onMessage reçu');
    final data = message.data;
    final type = (data['type'] ?? '').toString();
    // Phase D — Ne PAS afficher de notification système pour un appel
    // entrant : on prend le contrôle via IncomingCallScreen fullscreen.
    if (type != 'call.incoming') {
      final isUrgent =
          (data['is_urgent'] ?? '').toString() == 'true' ||
          type == 'dispute.created';
      await BabifixNotificationSoundService.playForegroundChime(urgent: isUrgent);
      await BabifixNotificationSoundService.showNotification(
        id: DateTime.now().millisecondsSinceEpoch % 100000,
        title: message.notification?.title ?? data['title'] ?? 'BABIFIX',
        body: message.notification?.body ?? data['body'] ?? '',
        payload: jsonEncode({
          'type': data['type'] ?? '',
          'reference': data['reference'] ?? '',
        }),
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
      if (!_initOK) return;
      final tok = await FirebaseMessaging.instance
          .getToken()
          .timeout(const Duration(seconds: 6));
      if (tok == null || tok.isEmpty) return;

      Future<void> send(String t, String jwt) async {
        if (jwt.isEmpty || t.isEmpty) return;
        final uri = Uri.parse('${babifixApiBaseUrl()}/api/auth/fcm-token');
        await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwt',
          },
          body: jsonEncode({'token': t, 'platform': _platformLabel(), 'app': 'client'}),
        );
      }

      await send(tok, apiBearerToken);
      debugPrint('BABIFIX FCM: token enregistré côté serveur');

      if (!_refreshListening) {
        _refreshListening = true;
        FirebaseMessaging.instance.onTokenRefresh.listen((newTok) async {
          final latestJwt = await BabifixUserStore.getApiToken();
          if (latestJwt != null && latestJwt.isNotEmpty) {
            await send(newTok, latestJwt);
          }
        });
      }
    } catch (e) {
      debugPrint('BABIFIX FCM register: $e');
    }
  }
}
