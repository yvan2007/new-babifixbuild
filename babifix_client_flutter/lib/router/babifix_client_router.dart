import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../features/reservations/reservations_history_screen.dart';
import '../features/reservations/rate_provider_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/map/providers_map_screen.dart';

// ── Route names ──────────────────────────────────────────────────────────────
abstract final class BabifixRoutes {
  static const onboarding = '/onboarding';
  static const home = '/home';
  static const auth = '/auth';
  static const serviceDetail = '/service/:id';
  static const bookingFlow = '/booking/:serviceId';
  static const providerProfile = '/provider/:id';
  static const notifications = '/notifications';
  static const payment = '/payment/:reservationId';
  static const chat = '/chat';
  static const chatRoom = '/chat/:prestataireId';
  static const editProfile = '/profile/edit';
  static const actualiteDetail = '/actualite/:id';
  // v2 — Nouvelles routes
  static const reservationsHistory = '/reservations';
  static const rateProvider = '/reservations/:ref/rate';
  static const forgotPassword = '/auth/forgot-password';
  static const providersMap = '/map';
}

GoRouter createBabifixClientRouter({
  required bool hasSeenOnboarding,
  required Listenable refreshListenable,
  required Widget Function(BuildContext) onboardingBuilder,
  required Widget Function(BuildContext) homeBuilder,
  required Widget Function(BuildContext, String serviceId) bookingBuilder,
  required Widget Function(BuildContext, String serviceId) serviceDetailBuilder,
  required Widget Function(BuildContext, String providerId)
  providerProfileBuilder,
  required Widget Function(BuildContext) notificationsBuilder,
  required Widget Function(BuildContext, String reservationId) paymentBuilder,
  required Widget Function(BuildContext) messagesBuilder,
  required Widget Function(BuildContext, String prestataireId) chatRoomBuilder,
  required Widget Function(BuildContext) editProfileBuilder,
}) {
  return GoRouter(
    initialLocation: hasSeenOnboarding
        ? BabifixRoutes.home
        : BabifixRoutes.onboarding,
    refreshListenable: refreshListenable,
    routes: [
      GoRoute(
        path: BabifixRoutes.onboarding,
        builder: (ctx, _) => onboardingBuilder(ctx),
      ),
      GoRoute(path: BabifixRoutes.home, builder: (ctx, _) => homeBuilder(ctx)),
      GoRoute(
        path: BabifixRoutes.serviceDetail,
        builder: (ctx, state) {
          final id = state.pathParameters['id'] ?? '0';
          return serviceDetailBuilder(ctx, id);
        },
      ),
      GoRoute(
        path: BabifixRoutes.bookingFlow,
        builder: (ctx, state) {
          final sid = state.pathParameters['serviceId'] ?? '0';
          return bookingBuilder(ctx, sid);
        },
      ),
      GoRoute(
        path: BabifixRoutes.providerProfile,
        builder: (ctx, state) {
          final id = state.pathParameters['id'] ?? '0';
          return providerProfileBuilder(ctx, id);
        },
      ),
      GoRoute(
        path: BabifixRoutes.notifications,
        builder: (ctx, _) => notificationsBuilder(ctx),
      ),
      GoRoute(
        path: BabifixRoutes.payment,
        builder: (ctx, state) {
          final rid = state.pathParameters['reservationId'] ?? '0';
          return paymentBuilder(ctx, rid);
        },
      ),
      GoRoute(
        path: BabifixRoutes.chat,
        builder: (ctx, _) => messagesBuilder(ctx),
      ),
      GoRoute(
        path: BabifixRoutes.chatRoom,
        builder: (ctx, state) {
          final pid = state.pathParameters['prestataireId'] ?? '0';
          return chatRoomBuilder(ctx, pid);
        },
      ),
      GoRoute(
        path: BabifixRoutes.editProfile,
        builder: (ctx, _) => editProfileBuilder(ctx),
      ),
      // ── v2 — Nouvelles routes ──────────────────────────────────────────────
      GoRoute(
        path: BabifixRoutes.reservationsHistory,
        builder: (ctx, _) => const ReservationsHistoryScreen(),
      ),
      GoRoute(
        path: BabifixRoutes.rateProvider,
        builder: (ctx, state) {
          final idParam = state.pathParameters['ref'] ?? '';
          final id = int.tryParse(idParam) ?? 0;
          return RateProviderScreen(bookingId: id);
        },
      ),
      GoRoute(
        path: BabifixRoutes.forgotPassword,
        builder: (ctx, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: BabifixRoutes.providersMap,
        builder: (ctx, _) => const ProvidersMapScreen(),
      ),
    ],
    errorBuilder: (ctx, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Color(0xFF4CC9F0),
            ),
            const SizedBox(height: 12),
            Text('Page introuvable', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ctx.go(BabifixRoutes.home),
              child: const Text('Retour à l\'accueil'),
            ),
          ],
        ),
      ),
    ),
  );
}
