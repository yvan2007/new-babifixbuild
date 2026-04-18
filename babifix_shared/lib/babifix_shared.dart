import 'package:flutter/material.dart';

class BabifixColors {
  static const primary = Color(0xFF4CC9F0);
  static const secondary = Color(0xFF4895EF);
  static const ciOrange = Color(0xFFE87722);
  static const ciGreen = Color(0xFF009A44);
  static const error = Color(0xFFE63946);
  static const success = Color(0xFF2D6A4F);
  static const warning = Color(0xFFF4A261);
}

class BabifixTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: BabifixColors.primary,
        brightness: Brightness.light,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: BabifixColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: BabifixColors.primary,
        brightness: Brightness.dark,
      ),
      appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: BabifixColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

String formatFcfa(double amount) {
  return '${amount.toStringAsFixed(0)} FCA';
}

String formatDate(DateTime date) {
  return '${date.day}/${date.month}/${date.year}';
}

String formatTime(DateTime time) {
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}
