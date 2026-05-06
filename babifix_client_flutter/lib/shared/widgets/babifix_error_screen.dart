import 'package:flutter/material.dart';
import '../../babifix_design_system.dart';

enum BabifixErrorType {
  network,
  server,
  notFound,
  timeout,
  unauthorized,
  unknown,
}

class BabifixErrorScreen extends StatelessWidget {
  const BabifixErrorScreen({
    super.key,
    required this.type,
    this.title,
    this.message,
    this.onRetry,
    this.onGoHome,
  });

  final BabifixErrorType type;
  final String? title;
  final String? message;
  final VoidCallback? onRetry;
  final VoidCallback? onGoHome;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final config = _typeConfig(type);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    config.color.withValues(alpha: 0.15),
                    config.color.withValues(alpha: 0.05),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                config.icon,
                size: 48,
                color: config.color,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              title ?? config.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message ?? config.message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white54 : Colors.grey.shade500,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            if (onRetry != null) ...[
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: const Text(
                    'Réessayer',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: BabifixDesign.cyan,
                    foregroundColor: BabifixDesign.navy,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (onGoHome != null)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: onGoHome,
                  icon: const Icon(Icons.home_outlined, size: 18),
                  label: const Text(
                    'Accueil',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  _ErrorConfig _typeConfig(BabifixErrorType type) {
    switch (type) {
      case BabifixErrorType.network:
        return const _ErrorConfig(
          icon: Icons.wifi_off_rounded,
          color: Color(0xFF64748B),
          title: 'Pas de connexion',
          message: 'Vérifiez votre réseau et réessayez.',
        );
      case BabifixErrorType.server:
        return const _ErrorConfig(
          icon: Icons.cloud_off_rounded,
          color: Color(0xFFEF4444),
          title: 'Erreur serveur',
          message: 'Nos serveurs rencontrent un problème. Réessayez dans un instant.',
        );
      case BabifixErrorType.notFound:
        return const _ErrorConfig(
          icon: Icons.search_off_rounded,
          color: Color(0xFFF59E0B),
          title: 'Non trouvé',
          message: 'Ce contenu n\'existe pas ou a été supprimé.',
        );
      case BabifixErrorType.timeout:
        return const _ErrorConfig(
          icon: Icons.timer_off_rounded,
          color: Color(0xFF8B5CF6),
          title: 'Délai expiré',
          message: 'La connexion a mis trop de temps à répondre.',
        );
      case BabifixErrorType.unauthorized:
        return const _ErrorConfig(
          icon: Icons.lock_outline_rounded,
          color: Color(0xFFEF4444),
          title: 'Session expirée',
          message: 'Reconnectez-vous pour continuer.',
        );
      case BabifixErrorType.unknown:
        return const _ErrorConfig(
          icon: Icons.error_outline_rounded,
          color: Color(0xFF64748B),
          title: 'Erreur inattendue',
          message: 'Quelque chose s\'est mal passé. Réessayez.',
        );
    }
  }
}

class _ErrorConfig {
  final IconData icon;
  final Color color;
  final String title;
  final String message;

  const _ErrorConfig({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });
}
