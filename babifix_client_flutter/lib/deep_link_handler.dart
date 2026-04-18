import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class DeepLinkHandler {
  static final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance;
  static VoidCallback? _onNavigate;

  static void registerNavigator(VoidCallback onNavigate) {
    _onNavigate = onNavigate;
  }

  static Future<void> initialize() async {
    final permission = await _firebaseMessaging.requestPermission();
    if (permission.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('FCM permission granted');
    }

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);

    final initialMessage = await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      _navigateFromPayload(initialMessage.data);
    }
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('Foreground message: ${message.notification?.title}');
    _navigateFromPayload(message.data);
  }

  static void _handleBackgroundMessage(RemoteMessage message) {
    debugPrint('Background message: ${message.notification?.title}');
    _navigateFromPayload(message.data);
  }

  static void _navigateFromPayload(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    final ref =
        data['reservation_id'] as String? ?? data['reference'] as String?;
    final prestataireId = data['prestataire_id'] as String?;

    debugPrint('DeepLink: type=$type, ref=$ref, prestataireId=$prestataireId');

    if (_onNavigate != null) {
      _onNavigate!();
    }
  }
}
