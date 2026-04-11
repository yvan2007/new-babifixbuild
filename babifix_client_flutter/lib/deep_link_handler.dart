import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class DeepLinkHandler {
  static final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance;

  static Future<void> initialize() async {
    // Demander la permission FCM
    final permission = await _firebaseMessaging.requestPermission();
    if (permission.authorizationStatus == AuthorizationStatus.authorized) {
      print('FCM permission granted');
    }

    // Gérer les messages en foreground
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Gérer les messages en background (terminée)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);

    // Gérer le premier message (app fermée)
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
    final reservationId = data['reservation_id'] as String?;
    final conversationId = data['conversation_id'] as String?;

    // Navigation basée sur le type de notification
    switch (type) {
      case 'new_reservation':
        if (reservationId != null) {
          // Aller à la détails de la réservation
          // context.go('/reservations/$reservationId');
        }
        break;
      case 'new_message':
        if (conversationId != null) {
          // Aller au chat
          // context.go('/chat/$conversationId');
        }
        break;
      case 'reservation_completed':
        if (reservationId != null) {
          // Aller à l'écran de notation
          // context.go('/rate/$reservationId');
        }
        break;
      default:
        // Aller à l'écran d'accueil
        break;
    }
  }
}

// Configuration du deep linking pour go_router
final GoRouter appRouter = GoRouter(
  routes: [
    // Routes existantes...
    GoRoute(
      path: '/reservations/:id',
      builder: (context, state) {
        final id = state.pathParameters['id'];
        // return ReservationDetailScreen(id: id);
        return const Scaffold(body: Center(child: Text('Réservation')));
      },
    ),
    GoRoute(
      path: '/chat/:id',
      builder: (context, state) {
        final id = state.pathParameters['id'];
        // return ChatRoomScreen(conversationId: id);
        return const Scaffold(body: Center(child: Text('Chat')));
      },
    ),
    GoRoute(
      path: '/rate/:id',
      builder: (context, state) {
        final id = state.pathParameters['id'];
        // return RateProviderScreen(reservationId: id);
        return const Scaffold(body: Center(child: Text('Noter')));
      },
    ),
  ],
);
