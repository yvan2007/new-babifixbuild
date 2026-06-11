import 'package:flutter/material.dart';

/// Tokens visuels BABIFIX — palette Côte d’Ivoire (orange / vert / bleu premium).
/// **UI uniquement** : aucune logique métier ; à utiliser pour thèmes, dégradés, ombres.
abstract final class BabifixDesign {
  BabifixDesign._();

  static const Color navy = Color(0xFF0B1B34);
  static const Color cyan = Color(0xFF4CC9F0);
  static const Color ciOrange = Color(0xFFE87722);
  static const Color success = Color(0xFF22C55E);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  // Couleur OFFICIELLE Premium/Pro (exclusivité) — un seul ton, pas d'autre violet.
  static const Color premium = Color(0xFF7C3AED);

  // Couleurs d'icônes "neutres" pour un rendu pro : le cyan reste réservé
  // aux états actifs/sélectionnés et aux boutons d'action.
  // - iconOnLight : icônes sur fond clair (blanc/gris).
  // - iconOnDark  : icônes sur fond sombre (navy).
  static const Color iconOnLight = Color(0xFF334155); // slate 700
  static const Color iconOnDark = Color(0xFFE2E8F0); // slate 200

  /// Renvoie la couleur d'icône neutre adaptée au thème courant.
  static Color iconColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? iconOnDark : iconOnLight;

  /// @deprecated Utiliser [cyan] à la place
  static const Color ciBlue = cyan;
  /// @deprecated Utiliser [success] à la place
  static const Color ciGreen = success;
  /// @deprecated Utiliser [navy] à la place
  static const Color darkNavy = navy;

  static const double radiusMD = 12.0;

  static const LinearGradient pageGradientLight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF8FAFC), Color(0xFFF0FDF4), Color(0xFFEFF6FF)],
  );

  static const LinearGradient pageGradientDark = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0B1B34), Color(0xFF0E2844), Color(0xFF0B1B34)],
  );

  static const LinearGradient landingGradientLight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF8FAFC), Color(0xFFFFFFFF), Color(0xFFEFF6FF)],
  );

  static const LinearGradient refusedBackground = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFF1F0), Color(0xFFFFF7ED), Color(0xFFF8FAFC)],
  );

  static List<BoxShadow> cardShadow(bool light) => [
    BoxShadow(
      color: (light ? const Color(0x220F172A) : const Color(0x66000000)),
      blurRadius: 24,
      offset: const Offset(0, 12),
    ),
  ];

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [cyan, navy],
    stops: [0.0, 1.0],
  );

  static List<BoxShadow> cyanGlowShadow({double opacity = 0.35}) => [
    BoxShadow(
      color: cyan.withValues(alpha: opacity),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];
}
