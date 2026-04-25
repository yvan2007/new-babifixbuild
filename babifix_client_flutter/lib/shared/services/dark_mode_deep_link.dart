/// Dark Mode Service — Synchronisation du theme entre apps
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';


class DarkModeService {
  /// Cle pour le storage
  static const _themeKey = 'theme_mode';
  
  /// Recuperer le theme actuel
  static Future<ThemeMode> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_themeKey);
    
    switch (value) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }
  
  /// Definir le theme
  static Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
  }
  
  /// Toggle entre clair et sombre
  static Future<void> toggleTheme() async {
    final current = await getThemeMode();
    final next = current == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await setThemeMode(next);
  }
  
  /// Recuperer la palette selon le theme
  static Map<String, Color> getPaletteSync() {
    // Note: Cette methode necessite un BuildContext pour mediaQuery
    // Utiliser getPaletteWithContext pour une version async
    return {
      'background': const Color(0xFFF5F5F5),
      'surface': Colors.white,
      'primary': const Color(0xFF4CC9F0),
      'secondary': const Color(0xFFF72585),
    };
  }
  
  /// Recuperer la palette avec contexte
  static Future<Map<String, Color>> getPaletteWithContext(BuildContext context) async {
    final mode = await getThemeMode();
    final isDark = mode == ThemeMode.dark || 
                (mode == ThemeMode.system && 
                 MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    
    if (isDark) {
      return {
        'background': const Color(0xFF121212),
        'surface': const Color(0xFF1E1E1E),
        'primary': const Color(0xFF4CC9F0),
        'secondary': const Color(0xFFF72585),
      };
    }
    
    return {
      'background': const Color(0xFFF5F5F5),
      'surface': Colors.white,
      'primary': const Color(0xFF4CC9F0),
      'secondary': const Color(0xFFF72585),
    };
  }
}


/// Deep Linking Service
class DeepLinkService {
  /// Gere le deep linking pour BABIFIX
  /// 
  /// ✅ U15: Deep linking fonctionnel
  /// 
  static const _scheme = 'babifix';
  
  /// Parse une URL en route
  static DeepLinkResult parseUrl(Uri url) {
    // babifix://provider/123
    // babifix://reservation/RES-2026-0001
    
    if (url.scheme != _scheme) {
      return DeepLinkResult.invalid();
    }
    
    final path = url.host + url.path;
    final segments = path.split('/');
    
    if (segments.isEmpty) {
      return DeepLinkResult.home();
    }
    
    switch (segments[0]) {
      case 'provider':
        if (segments.length > 1) {
          final id = int.tryParse(segments[1]);
          if (id != null) {
            return DeepLinkResult.provider(id);
          }
        }
        break;
        
      case 'reservation':
        if (segments.length > 1) {
          return DeepLinkResult.reservation(segments[1]);
        }
        break;
        
      case 'devis':
        if (segments.length > 1) {
          return DeepLinkResult.devis(segments[1]);
        }
        break;
        
      case 'home':
        return DeepLinkResult.home();
    }
    
    return DeepLinkResult.invalid();
  }
  
  /// Genere une URL de deep link
  static String generateProviderLink(int providerId) =>
      '$_scheme://provider/$providerId';
  
  static String generateReservationLink(String reference) =>
      '$_scheme://reservation/$reference';
  
  static String generateDevisLink(String reference) =>
      '$_scheme://devis/$reference';
}


class DeepLinkResult {
  final DeepLinkType type;
  final int? providerId;
  final String? reference;
  
  DeepLinkResult._({
    required this.type,
    this.providerId,
    this.reference,
  });
  
  factory DeepLinkResult.home() => DeepLinkResult._(type: DeepLinkType.home);
  factory DeepLinkResult.invalid() => DeepLinkResult._(type: DeepLinkType.invalid);
  factory DeepLinkResult.provider(int id) => DeepLinkResult._(
    type: DeepLinkType.provider,
    providerId: id,
  );
  factory DeepLinkResult.reservation(String ref) => DeepLinkResult._(
    type: DeepLinkType.reservation,
    reference: ref,
  );
  factory DeepLinkResult.devis(String ref) => DeepLinkResult._(
    type: DeepLinkType.devis,
    reference: ref,
  );
}


enum DeepLinkType {
  home,
  provider,
  reservation,
  devis,
  invalid,
}