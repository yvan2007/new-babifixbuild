import 'package:flutter/material.dart';

/// Tokens visuels BABIFIX — palette Côte d’Ivoire (orange / vert / bleu premium).
/// **UI uniquement** : aucune logique métier ; à utiliser pour thèmes, dégradés, ombres.
abstract final class BabifixDesign {
  BabifixDesign._();

  static const Color navy = Color(0xFF0B1B34);
  static const Color cyan = Color(0xFF4CC9F0);
  static const Color ciOrange = Color(0xFFE87722);
  static const Color ciGreen = Color(0xFF009A44);
  static const Color ciBlue = Color(0xFF0066B3);
  static const Color success = Color(0xFF22C55E);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);

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
    colors: [cyan, Color(0xFF2563EB), navy],
    stops: [0.0, 0.5, 1.0],
  );

  static List<BoxShadow> cyanGlowShadow({double opacity = 0.35}) => [
    BoxShadow(
      color: cyan.withValues(alpha: opacity),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];
}
