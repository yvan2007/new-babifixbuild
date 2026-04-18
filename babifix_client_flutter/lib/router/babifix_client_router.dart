import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/forgot_password_screen.dart';
import '../features/booking/devis_detail_screen.dart';
import '../features/map/providers_map_screen.dart';
import '../features/reservations/rate_provider_screen.dart';
import '../features/reservations/reservations_history_screen.dart';
import '../theme/app_theme.dart';

Widget _fadeSlideTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  return FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.05),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

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
  static const reservationsHistory = '/reservations';
  static const rateProvider = '/reservations/:ref/rate';
  static const forgotPassword = '/auth/forgot-password';
  static const providersMap = '/map';
  static const devisDetail = '/devis/:reference';
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
  required Widget Function(BuildContext, String reference) devisDetailBuilder,
}) {
  // Pour simplifier, on commence toujours par /home
  // L'app décidera si afficher onboarding ou non
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refreshListenable,
    routes: [
      GoRoute(path: '/home', builder: (ctx, _) => homeBuilder(ctx)),
      GoRoute(path: '/onboarding', builder: (ctx, _) => onboardingBuilder(ctx)),
      GoRoute(
        path: '/',
        redirect: (_, __) => hasSeenOnboarding ? '/home' : '/onboarding',
      ),
      GoRoute(path: '/home', builder: (ctx, _) => homeBuilder(ctx)),
      GoRoute(path: '/onboarding', builder: (ctx, _) => onboardingBuilder(ctx)),
      GoRoute(
        path: BabifixRoutes.bookingFlow,
        pageBuilder: (ctx, state) => CustomTransitionPage(
          child: bookingBuilder(ctx, state.pathParameters['serviceId'] ?? '0'),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: BabifixRoutes.payment,
        pageBuilder: (ctx, state) => CustomTransitionPage(
          child: paymentBuilder(
            ctx,
            state.pathParameters['reservationId'] ?? '0',
          ),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: BabifixRoutes.providerProfile,
        pageBuilder: (ctx, state) => CustomTransitionPage(
          child: providerProfileBuilder(ctx, state.pathParameters['id'] ?? '0'),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: BabifixRoutes.notifications,
        builder: (ctx, _) => notificationsBuilder(ctx),
      ),
      GoRoute(
        path: BabifixRoutes.payment,
        builder: (ctx, state) =>
            paymentBuilder(ctx, state.pathParameters['reservationId'] ?? '0'),
      ),
      GoRoute(
        path: BabifixRoutes.chat,
        builder: (ctx, _) => messagesBuilder(ctx),
      ),
      GoRoute(
        path: BabifixRoutes.chatRoom,
        builder: (ctx, state) =>
            chatRoomBuilder(ctx, state.pathParameters['prestataireId'] ?? '0'),
      ),
      GoRoute(
        path: BabifixRoutes.editProfile,
        builder: (ctx, _) => editProfileBuilder(ctx),
      ),
      GoRoute(
        path: BabifixRoutes.reservationsHistory,
        builder: (ctx, _) => const ReservationsHistoryScreen(),
      ),
      GoRoute(
        path: BabifixRoutes.rateProvider,
        builder: (ctx, state) {
          final ref = state.pathParameters['ref'] ?? '';
          return RateProviderScreen(bookingId: int.tryParse(ref) ?? 0);
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
      GoRoute(
        path: BabifixRoutes.devisDetail,
        pageBuilder: (ctx, state) => CustomTransitionPage(
          child: devisDetailBuilder(
            ctx,
            state.pathParameters['reference'] ?? '',
          ),
          transitionsBuilder: _fadeSlideTransition,
        ),
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
              child: const Text("Retour à l'accueil"),
            ),
          ],
        ),
      ),
    ),
  );
}
