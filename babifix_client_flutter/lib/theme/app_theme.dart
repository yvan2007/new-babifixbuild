import 'package:flutter/material.dart';
import '../babifix_design_system.dart';

enum AppPaletteMode { blue, light, white }

abstract final class BabifixTheme {
  BabifixTheme._();

  static ThemeData forMode(AppPaletteMode mode) {
    final base = ThemeData(useMaterial3: true);
    final isDark = mode == AppPaletteMode.blue;
    final isWhite = mode == AppPaletteMode.white;
    final isLight = !isDark;
    final bg = isDark
        ? BabifixDesign.navy
        : (isWhite ? BabifixDesign.bgWhite : BabifixDesign.bgLight);
    final onBg = isLight
        ? BabifixDesign.textStrongLight
        : BabifixDesign.textStrongDark;
    final muted = isLight
        ? BabifixDesign.textMutedLight
        : BabifixDesign.textMutedDark;
    final surface = isLight
        ? BabifixDesign.bgWhite
        : BabifixDesign.navySurface;
    final border = isDark ? BabifixDesign.borderDark : BabifixDesign.borderLight;

    final cs = ColorScheme.fromSeed(
      seedColor: BabifixDesign.navy,
      brightness: isLight ? Brightness.light : Brightness.dark,
    ).copyWith(
      primary: isDark ? BabifixDesign.cyan : BabifixDesign.navy,
      onPrimary: isDark ? BabifixDesign.navy : Colors.white,
      surface: surface,
      onSurface: onBg,
      secondary: isDark ? BabifixDesign.ciOrangeBright : BabifixDesign.ciOrange,
      onSecondary: Colors.white,
      tertiary: BabifixDesign.emeraldTint,
      outline: border,
    );

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: cs,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: onBg,
        iconTheme: IconThemeData(color: onBg),
        actionsIconTheme: IconThemeData(color: onBg),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: onBg,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      textTheme: base.textTheme.apply(bodyColor: onBg, displayColor: onBg),
      inputDecorationTheme: InputDecorationTheme(
        alignLabelWithHint: true,
        filled: true,
        fillColor: isDark
            ? BabifixDesign.navyElevated
            : (isWhite ? BabifixDesign.bgWhite : BabifixDesign.bgSoft),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        labelStyle: TextStyle(color: muted, fontWeight: FontWeight.w500),
        hintStyle: TextStyle(color: muted.withValues(alpha: 0.78)),
        prefixIconColor: isDark ? BabifixDesign.cyan : BabifixDesign.navy,
        suffixIconColor: muted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BabifixDesign.radiusMD),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BabifixDesign.radiusMD),
          borderSide: BorderSide(color: border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BabifixDesign.radiusMD),
          borderSide: BorderSide(
            color: isDark ? BabifixDesign.cyan : BabifixDesign.navy,
            width: 1.8,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BabifixDesign.radiusMD),
          borderSide: const BorderSide(color: BabifixDesign.error, width: 1.2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onBg,
          side: BorderSide(color: border, width: 1.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BabifixDesign.radiusMD),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: BabifixDesign.ciOrange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BabifixDesign.radiusMD),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? BabifixDesign.cyan : BabifixDesign.navy,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BabifixDesign.radiusLG),
          side: BorderSide(color: border, width: 1),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark
            ? BabifixDesign.navyElevated
            : (isWhite ? BabifixDesign.bgWhite : BabifixDesign.bgSoft),
        labelStyle: TextStyle(color: onBg, fontSize: 13),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(
        color: border,
        thickness: 1,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: isDark ? BabifixDesign.cyan : BabifixDesign.ciOrange,
        unselectedItemColor: muted,
      ),
    );
  }
}
