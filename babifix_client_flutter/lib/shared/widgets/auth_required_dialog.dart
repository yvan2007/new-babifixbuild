import 'package:flutter/material.dart';

import '../../babifix_design_system.dart';

/// Demande à l'utilisateur s'il veut se connecter pour effectuer une action
/// nécessitant un compte, sinon il peut continuer à visiter en mode invité.
///
/// Retourne :
/// - `true`  → l'utilisateur veut se connecter (à toi d'ouvrir l'écran d'auth)
/// - `false` → l'utilisateur préfère continuer en mode visiteur
///
/// Usage :
/// ```dart
/// final wantLogin = await promptLoginRequired(
///   context,
///   action: 'réserver ce prestataire',
/// );
/// if (wantLogin) {
///   await _openAuth();
/// }
/// ```
Future<bool> promptLoginRequired(
  BuildContext context, {
  String action = 'continuer',
  String? customMessage,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true, // tap dehors = annule
    builder: (ctx) {
      final isLight = Theme.of(ctx).brightness == Brightness.light;
      final bg = isLight ? Colors.white : const Color(0xFF152A45);
      final textPrimary =
          isLight ? const Color(0xFF0F172A) : Colors.white;
      final textSecondary =
          isLight ? const Color(0xFF475569) : const Color(0xFFB4C2D9);

      return Dialog(
        backgroundColor: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icône cadenas dans cercle cyan
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4CC9F0), Color(0xFF22A6D6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: BabifixDesign.cyan.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Connectez-vous',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                customMessage ??
                    'Pour $action, vous devez avoir un compte BABIFIX. C\'est rapide et gratuit !',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 22),

              // CTA principal — Se connecter
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: const Text(
                    'Se connecter / S\'inscrire',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: BabifixDesign.cyan,
                    foregroundColor: const Color(0xFF0B1B34),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Bouton secondaire — Continuer à visiter
              SizedBox(
                width: double.infinity,
                height: 46,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    size: 17,
                    color: textSecondary,
                  ),
                  label: Text(
                    'Continuer à visiter',
                    style: TextStyle(
                      color: textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                  style: TextButton.styleFrom(
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
    },
  );
  return result == true;
}
