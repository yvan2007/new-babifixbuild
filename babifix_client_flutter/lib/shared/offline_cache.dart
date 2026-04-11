/// Cache hors-ligne basé sur SharedPreferences.
///
/// Sauvegarde les données JSON de la home et les réservations pour
/// permettre un affichage dégradé sans connexion.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class BabifixOfflineCache {
  BabifixOfflineCache._();

  static const _kHomeData = 'babifix_cache_home_v1';
  static const _kReservations = 'babifix_cache_reservations_v1';
  static const _kTimestamp = 'babifix_cache_ts_v1';
  static const _maxAgeMs = 3600 * 1000; // 1 heure

  // ── Écriture ────────────────────────────────────────────────────────────────

  static Future<void> saveHomeData(Map<String, dynamic> data) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kHomeData, jsonEncode(data));
    await p.setInt(_kTimestamp, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<void> saveReservations(List<dynamic> data) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kReservations, jsonEncode(data));
  }

  // ── Lecture ─────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> loadHomeData() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kHomeData);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<List<dynamic>?> loadReservations() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kReservations);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// True si le cache est vieux de plus d'une heure.
  static Future<bool> isStale() async {
    final p = await SharedPreferences.getInstance();
    final ts = p.getInt(_kTimestamp) ?? 0;
    return DateTime.now().millisecondsSinceEpoch - ts > _maxAgeMs;
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kHomeData);
    await p.remove(_kReservations);
    await p.remove(_kTimestamp);
  }
}
