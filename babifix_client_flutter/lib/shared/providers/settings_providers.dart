import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

final localeProvider = StateProvider<Locale>((ref) => const Locale('fr'));

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);

final isDarkModeProvider = Provider<bool>((ref) {
  return ref.watch(themeModeProvider) == ThemeMode.dark;
});
