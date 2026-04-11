import 'package:flutter/material.dart';

/// Tokens visuels BABIFIX — palette Côte d'Ivoire (orange / vert / bleu premium).
/// **UI uniquement** : aucune logique métier ; à utiliser pour thèmes, dégradés, ombres.
abstract final class BabifixDesign {
  BabifixDesign._();

  // ─── Couleurs principales ────────────────────────────────────────────────
  static const Color navy = Color(0xFF0B1B34);
  static const Color darkNavy = Color(0xFF0A0F1A);
  static const Color cyan = Color(0xFF4CC9F0);
  static const Color ciOrange = Color(0xFFE87722);
  static const Color ciGreen = Color(0xFF009A44);
  static const Color ciBlue = Color(0xFF0066B3);

  // ─── Couleurs sémantiques ────────────────────────────────────────────────
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // ─── Spacing constants ──────────────────────────────────────────────────
  /// 4dp — micro espacement (icônes, puces)
  static const double spaceXS = 4.0;

  /// 8dp — espacement serré
  static const double spaceSM = 8.0;

  /// 12dp — espacement standard petits éléments
  static const double spaceMD = 12.0;

  /// 16dp — espacement standard sections
  static const double spaceLG = 16.0;

  /// 20dp — espacement confortable
  static const double spaceXL = 20.0;

  /// 24dp — espacement large entre sections
  static const double space2XL = 24.0;

  /// 32dp — espacement très large
  static const double space3XL = 32.0;

  /// 48dp — espacement page
  static const double space4XL = 48.0;

  // ─── Border radius standards ────────────────────────────────────────────
  /// 6dp — petits badges et puces
  static const double radiusXS = 6.0;

  /// 10dp — boutons compacts, chips
  static const double radiusSM = 10.0;

  /// 14dp — cards compactes
  static const double radiusMD = 14.0;

  /// 20dp — cards standards
  static const double radiusLG = 20.0;

  /// 24dp — grandes cards, modales
  static const double radiusXL = 24.0;

  /// 32dp — cards hero, onboarding
  static const double radius2XL = 32.0;

  /// 99dp — pilules et avatars
  static const double radiusPill = 99.0;

  // ─── Gradients de fond ──────────────────────────────────────────────────

  /// Fond principal app client (clair) — léger vert + bleu (drapeau CI subtil).
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

  /// Landing / onboarding prestataire.
  static const LinearGradient landingGradientLight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF8FAFC), Color(0xFFFFFFFF), Color(0xFFEFF6FF)],
  );

  /// Écran refus dossier — chaleureux, lisible, premium (sans changer le message).
  static const LinearGradient refusedBackground = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFF1F0), Color(0xFFFFF7ED), Color(0xFFF8FAFC)],
  );

  /// Dégradé accent cyan → bleu pour boutons et éléments actifs.
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [cyan, Color(0xFF2563EB), navy],
    stops: [0.0, 0.5, 1.0],
  );

  // ─── Ombres ─────────────────────────────────────────────────────────────

  static List<BoxShadow> cardShadow(bool light) => [
    BoxShadow(
      color: (light ? const Color(0x220F172A) : const Color(0x66000000)),
      blurRadius: 24,
      offset: const Offset(0, 12),
    ),
  ];

  /// Ombre légère pour éléments en surélévation faible (chips, boutons).
  static List<BoxShadow> elevationShadowSM(bool light) => [
    BoxShadow(
      color: (light ? const Color(0x140F172A) : const Color(0x40000000)),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];

  /// Ombre cyan pour les boutons / éléments primaires actifs.
  static List<BoxShadow> cyanGlowShadow({double opacity = 0.35}) => [
    BoxShadow(
      color: cyan.withValues(alpha: opacity),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];

  /// Ombre forte pour modales et bottom sheets.
  static List<BoxShadow> modalShadow(bool light) => [
    BoxShadow(
      color: (light ? const Color(0x1A0F172A) : const Color(0x80000000)),
      blurRadius: 40,
      offset: const Offset(0, -8),
    ),
  ];

  // ─── Helpers typographie ────────────────────────────────────────────────

  /// Style titres H1 : 28px bold — écrans principaux.
  static TextStyle headingH1({required Color color}) => TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w900,
    color: color,
    letterSpacing: -0.8,
    height: 1.1,
  );

  /// Style titres H2 : 22px bold — sections.
  static TextStyle headingH2({required Color color}) => TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    color: color,
    letterSpacing: -0.5,
    height: 1.2,
  );

  /// Style titres H3 : 18px semibold — sous-sections.
  static TextStyle headingH3({required Color color}) => TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: color,
    letterSpacing: -0.3,
  );

  /// Style corps de texte principal : 15px.
  static TextStyle bodyMedium({required Color color}) =>
      TextStyle(fontSize: 15, color: color, height: 1.45);

  /// Style texte secondaire / légende : 13px.
  static TextStyle caption({required Color color}) =>
      TextStyle(fontSize: 13, color: color, height: 1.35);
}
