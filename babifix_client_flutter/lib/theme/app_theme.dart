import 'package:flutter/material.dart';
import '../babifix_design_system.dart';

enum AppPaletteMode { blue, light, white }

abstract final class BabifixTheme {
  BabifixTheme._();

  static ThemeData forMode(AppPaletteMode mode) {
    final base = ThemeData(useMaterial3: true);
    final isDark = mode == AppPaletteMode.blue;
    final isWhite = mode == AppPaletteMode.white;
    // "light" et "white" partagent la luminosité claire ; seul le fond change
    // (blanc pur pour "white", très légèrement teinté pour "light").
    final isLight = !isDark;
    final bg = isDark
        ? BabifixDesign.navy
        : (isWhite ? const Color(0xFFFFFFFF) : const Color(0xFFF6F8FC));
    final seed = BabifixDesign.cyan;
    final onBg = isLight ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final muted = isLight ? const Color(0xFF64748B) : const Color(0xFFB4C2D9);
    final surface = isLight ? const Color(0xFFFFFFFF) : const Color(0xFF151D2E);
    final cs = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: isLight ? Brightness.light : Brightness.dark,
    ).copyWith(
      surface: surface,
      secondary: BabifixDesign.ciOrange,
      tertiary: BabifixDesign.success,
    );
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: cs,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: onBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: onBg,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      textTheme: base.textTheme.apply(bodyColor: onBg, displayColor: onBg),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? const Color(0xFFF1F5F9) : const Color(0xFF1A2438),
        labelStyle: TextStyle(color: muted),
        hintStyle: TextStyle(color: muted.withValues(alpha: 0.85)),
        prefixIconColor: BabifixDesign.cyan,
        suffixIconColor: muted,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: BabifixDesign.cyan.withValues(alpha: isLight ? 0.35 : 0.5),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: BabifixDesign.cyan, width: 2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onBg,
          side: BorderSide(color: BabifixDesign.cyan.withValues(alpha: 0.65)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: BabifixDesign.cyan,
          foregroundColor: BabifixDesign.navy,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: BabifixDesign.cyan),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isLight
                ? const Color(0x140F172A)
                : const Color(0x12FFFFFF),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isLight
            ? const Color(0xFFF1F5F9)
            : const Color(0xFF1A2438),
        labelStyle: TextStyle(color: onBg, fontSize: 13),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(
        color: isLight ? const Color(0x140F172A) : const Color(0x22FFFFFF),
        thickness: 1,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: BabifixDesign.cyan,
        unselectedItemColor: muted,
      ),
    );
  }
}
