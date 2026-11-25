import 'package:flutter/material.dart';

/// Tokens visuels BABIFIX unifies (Navy, Cyan, Orange action, Or & Argent).
/// **UI uniquement** : source canonique pour surfaces, bordures, ombres, typo
/// tabulaire et courbes de mouvement (aligne sur DESIGN_BABIFIX.md).
abstract final class BabifixDesign {
  BabifixDesign._();

  // Couleurs principales, Emerald Money & Metaux Direction 3
  static const Color navy = Color(0xFF0B1B34);
  static const Color obsidian = Color(0xFF080E1C);
  static const Color navySurface = Color(0xFF13223B);
  static const Color navyElevated = Color(0xFF1B2D4B);

  static const Color emeraldForest = Color(0xFF0E3B2E);
  static const Color emeraldTint = Color(0xFF0E6B4E);
  static const Color titaniumCard = Color(0xFF22303D);
  static const Color obsidianGold = Color(0xFF121512);

  static const Color cyan = Color(0xFF4CC9F0);
  static const Color cyanDeep = Color(0xFF0369A1);
  static const Color ciOrange = Color(0xFFC2410C);
  static const Color ciOrangeBright = Color(0xFFE87722);
  static const Color ciOrangePressed = Color(0xFF9A3412);

  static const Color goldBrass = Color(0xFFE7C463);
  static const Color silverMetal = Color(0xFFC8D1DE);

  // Neutres & Surfaces (WCAG AA >= 4.5:1)
  static const Color bgWhite = Color(0xFFFFFFFF);
  static const Color bgLight = Color(0xFFF7F8FA);
  static const Color bgWarmIvory = Color(0xFFFAF5E4);
  static const Color bgSoft = Color(0xFFF8FAFC);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color borderDark = Color(0x24FFFFFF);
  static const Color textStrongLight = Color(0xFF0F172A);
  static const Color textMutedLight = Color(0xFF475569);
  static const Color textStrongDark = Color(0xFFF8FAFC);
  static const Color textMutedDark = Color(0xFFCBD5E1);

  // ─── Icones neutres ──────────────────────────────────────────────────────
  static const Color iconOnLight = Color(0xFF334155);
  static const Color iconOnDark = Color(0xFFE2E8F0);

  static Color iconColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? iconOnDark : iconOnLight;

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static bool isWhiteMode(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light &&
      Theme.of(context).scaffoldBackgroundColor == bgWhite;

  static Color surfaceOf(BuildContext context) =>
      isDark(context) ? navySurface : bgWhite;

  static Color elevatedSurfaceOf(BuildContext context) =>
      isDark(context) ? navyElevated : bgSoft;

  static Color borderOf(BuildContext context) =>
      isDark(context) ? borderDark : borderLight;

  static Color textPrimaryOf(BuildContext context) =>
      isDark(context) ? textStrongDark : textStrongLight;

  static Color textMutedOf(BuildContext context) =>
      isDark(context) ? textMutedDark : textMutedLight;

  // ─── Semantiques (statuts uniquement) ────────────────────────────────────
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color premium = Color(0xFF7C3AED);

  // ─── Alias historiques (compatibilite) ───────────────────────────────────
  /// @deprecated Utiliser [cyan]
  static const Color ciBlue = cyan;
  /// @deprecated Utiliser [success]
  static const Color ciGreen = success;
  /// @deprecated Utiliser [navy]
  static const Color darkNavy = navy;
  /// @deprecated Utiliser [cyan]
  static const Color info = cyan;

  // ─── Espacements (grille 4pt / 8pt stricte) ───────────────────────────────
  static const double spaceXS = 4.0;
  static const double spaceSM = 8.0;
  static const double spaceMD = 12.0;
  static const double spaceLG = 16.0;
  static const double spaceXL = 20.0;
  static const double space2XL = 24.0;
  static const double space3XL = 32.0;
  static const double space4XL = 48.0;

  // ─── Rayons ──────────────────────────────────────────────────────────────
  static const double radiusXS = 6.0;
  static const double radiusSM = 10.0;
  static const double radiusMD = 14.0;
  static const double radiusLG = 18.0;
  static const double radiusXL = 24.0;
  static const double radius2XL = 30.0;
  static const double radiusPill = 99.0;

  // ─── Courbes & Durees de mouvement ───────────────────────────────────────
  static const Duration durationTap = Duration(milliseconds: 110);
  static const Duration durationFast = Duration(milliseconds: 180);
  static const Duration durationStandard = Duration(milliseconds: 260);
  static const Duration durationSheet = Duration(milliseconds: 340);

  static const Curve curveOut = Cubic(0.23, 1.0, 0.32, 1.0);
  static const Curve curveSwitch = Cubic(0.32, 0.72, 0.0, 1.0);

  // ─── Fonds plats / architecturalement sobres ─────────────────────────────
  static const LinearGradient pageGradientWhite = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgWhite, bgWhite],
  );

  static const LinearGradient pageGradientLight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgLight, bgSoft],
  );

  static const LinearGradient pageGradientDark = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [navy, obsidian],
  );

  static const LinearGradient landingGradientLight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [bgWhite, bgLight],
  );

  static const LinearGradient refusedBackground = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFF5F5), bgSoft],
  );

  /// Accent sobre (evite les lueurs neon) : conservé pour compatibilite.
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [ciOrange, Color(0xFFD66517)],
    stops: [0.0, 1.0],
  );

  // ─── Ombres neutres & subtiles ───────────────────────────────────────────
  static List<BoxShadow> cardShadow(bool light) => [
    BoxShadow(
      color: light ? const Color(0x0F0F172A) : const Color(0x45000000),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ];

  static List<BoxShadow> elevationShadowSM(bool light) => [
    BoxShadow(
      color: light ? const Color(0x0B0F172A) : const Color(0x30000000),
      blurRadius: 10,
      offset: const Offset(0, 3),
    ),
  ];

  static List<BoxShadow> cyanGlowShadow({double opacity = 0.14}) => [
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: opacity),
      blurRadius: 14,
      offset: const Offset(0, 6),
    ),
  ];

  static List<BoxShadow> modalShadow(bool light) => [
    BoxShadow(
      color: light ? const Color(0x180F172A) : const Color(0x70000000),
      blurRadius: 32,
      offset: const Offset(0, -6),
    ),
  ];

  // ─── Helpers Typographie & Chiffres Tabulaires ───────────────────────────
  static const List<FontFeature> tabularFigures = [
    FontFeature.tabularFigures(),
  ];

  static TextStyle amountStyle({
    required Color color,
    double fontSize = 20,
    FontWeight fontWeight = FontWeight.w800,
    double letterSpacing = -0.3,
  }) => TextStyle(
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
    fontFeatures: tabularFigures,
  );

  static TextStyle headingH1({required Color color}) => TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w900,
    color: color,
    letterSpacing: -0.7,
    height: 1.12,
  );

  static TextStyle headingH2({required Color color}) => TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    color: color,
    letterSpacing: -0.4,
    height: 1.2,
  );

  static TextStyle headingH3({required Color color}) => TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: color,
    letterSpacing: -0.2,
  );

  static TextStyle bodyMedium({required Color color}) =>
      TextStyle(fontSize: 15, color: color, height: 1.45);

  static TextStyle caption({required Color color}) =>
      TextStyle(fontSize: 13, color: color, height: 1.35);
}
