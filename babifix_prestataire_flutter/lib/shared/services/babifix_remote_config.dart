import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../babifix_api_config.dart';

String formatMaintenanceDateTime(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return '';
  final dt = DateTime.tryParse(s);
  if (dt == null) return s;
  final dd = dt.day.toString().padLeft(2, '0');
  final mm = dt.month.toString().padLeft(2, '0');
  final hh = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  return '$dd/$mm à $hh:$min';
}

class BabifixRemoteConfigData {
  final int commissionBasePct;
  final int commissionFloorPct;
  final int silverPriceFcfa;
  final int goldPriceFcfa;
  final int silverCommissionPct;
  final int goldCommissionPct;
  final int fraisMiseEnRelationFcfa;
  final int minWithdrawalFcfa;
  final int dailyWithdrawalCapFcfa;
  final bool maintenance;
  final String maintenanceScheduledAt;
  final String maintenanceEndAt;
  final String maintenanceMessage;
  final bool maintenanceAllowActive;
  final bool allowCash;
  final bool allowMobileMoney;
  final List<String> operators;
  final String supportPhone;
  final String supportWhatsapp;
  final String supportEmail;
  final bool callsEnabled;
  final bool audioTranscriptionEnabled;

  const BabifixRemoteConfigData({
    this.commissionBasePct = 18,
    this.commissionFloorPct = 5,
    this.silverPriceFcfa = 7500,
    this.goldPriceFcfa = 15000,
    this.silverCommissionPct = 13,
    this.goldCommissionPct = 8,
    this.fraisMiseEnRelationFcfa = 500,
    this.minWithdrawalFcfa = 1000,
    this.dailyWithdrawalCapFcfa = 500000,
    this.maintenance = false,
    this.maintenanceScheduledAt = '',
    this.maintenanceEndAt = '',
    this.maintenanceMessage = '',
    this.maintenanceAllowActive = true,
    this.allowCash = true,
    this.allowMobileMoney = true,
    this.operators = const ['wave', 'orange', 'mtn', 'moov'],
    this.supportPhone = '+225 07 00 00 00 00',
    this.supportWhatsapp = '+225 07 00 00 00 00',
    this.supportEmail = 'contact@babifix.ci',
    this.callsEnabled = false,
    this.audioTranscriptionEnabled = false,
  });

  factory BabifixRemoteConfigData.fromJson(Map<String, dynamic> j) {
    final tiers = (j['tiers'] is Map)
        ? Map<String, dynamic>.from(j['tiers'] as Map)
        : <String, dynamic>{};
    final std = (tiers['standard'] is Map)
        ? Map<String, dynamic>.from(tiers['standard'] as Map)
        : <String, dynamic>{};
    final sil = (tiers['silver'] is Map)
        ? Map<String, dynamic>.from(tiers['silver'] as Map)
        : <String, dynamic>{};
    final gld = (tiers['gold'] is Map)
        ? Map<String, dynamic>.from(tiers['gold'] as Map)
        : <String, dynamic>{};
    final escrow = (j['escrow'] is Map)
        ? Map<String, dynamic>.from(j['escrow'] as Map)
        : <String, dynamic>{};
    final wallet = (j['wallet'] is Map)
        ? Map<String, dynamic>.from(j['wallet'] as Map)
        : <String, dynamic>{};
    final pay = (j['payment_modes'] is Map)
        ? Map<String, dynamic>.from(j['payment_modes'] as Map)
        : <String, dynamic>{};
    final apps = (j['apps'] is Map)
        ? Map<String, dynamic>.from(j['apps'] as Map)
        : <String, dynamic>{};
    final sup = (j['support'] is Map)
        ? Map<String, dynamic>.from(j['support'] as Map)
        : <String, dynamic>{};

    final rawOps = pay['operators'];
    final ops = rawOps is List
        ? rawOps.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : const ['wave', 'orange', 'mtn', 'moov'];

    return BabifixRemoteConfigData(
      commissionBasePct:
          (j['commission_base_pct'] as num?)?.toInt() ??
          (std['commission_pct'] as num?)?.toInt() ??
          18,
      commissionFloorPct: (j['commission_floor_pct'] as num?)?.toInt() ?? 5,
      silverPriceFcfa: (sil['price_fcfa'] as num?)?.toInt() ?? 7500,
      goldPriceFcfa: (gld['price_fcfa'] as num?)?.toInt() ?? 15000,
      silverCommissionPct: (sil['commission_pct'] as num?)?.toInt() ?? 13,
      goldCommissionPct: (gld['commission_pct'] as num?)?.toInt() ?? 8,
      fraisMiseEnRelationFcfa:
          (escrow['frais_mise_en_relation_fcfa'] as num?)?.toInt() ?? 500,
      minWithdrawalFcfa:
          (wallet['min_withdrawal_fcfa'] as num?)?.toInt() ?? 1000,
      dailyWithdrawalCapFcfa:
          (wallet['daily_withdrawal_cap_fcfa'] as num?)?.toInt() ?? 500000,
      maintenance: apps['maintenance'] == true,
      maintenanceScheduledAt:
          formatMaintenanceDateTime((apps['maintenance_scheduled_at'] ?? '').toString()),
      maintenanceEndAt:
          formatMaintenanceDateTime((apps['maintenance_end_at'] ?? '').toString()),
      maintenanceMessage:
          (apps['maintenance_message'] ?? '').toString().trim(),
      maintenanceAllowActive: apps['maintenance_allow_active'] != false,
      allowCash: pay['allow_cash'] != false,
      allowMobileMoney: pay['allow_mobile_money'] != false,
      operators: ops.isEmpty ? const ['wave', 'orange', 'mtn', 'moov'] : ops,
      supportPhone: (sup['phone'] ?? '+225 07 00 00 00 00').toString(),
      supportWhatsapp: (sup['whatsapp'] ?? '+225 07 00 00 00 00').toString(),
      supportEmail: (sup['email'] ?? 'contact@babifix.ci').toString(),
      callsEnabled: apps['calls_enabled'] == true,
      audioTranscriptionEnabled: apps['audio_transcription_enabled'] == true,
    );
  }
}

class BabifixRemoteConfig {
  BabifixRemoteConfig._();
  static final BabifixRemoteConfig instance = BabifixRemoteConfig._();

  static const _cacheKey = 'babifix_remote_platform_config_v1';

  final ValueNotifier<BabifixRemoteConfigData> config =
      ValueNotifier<BabifixRemoteConfigData>(const BabifixRemoteConfigData());

  BabifixRemoteConfigData get current => config.value;

  Future<void> initAndSync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      if (cached != null && cached.isNotEmpty) {
        final map = jsonDecode(cached);
        if (map is Map<String, dynamic>) {
          config.value = BabifixRemoteConfigData.fromJson(map);
        }
      }
    } catch (_) {}
    await refresh();
  }

  Future<void> refresh() async {
    try {
      final base = babifixApiBaseUrl();
      final resp = await http
          .get(Uri.parse('$base/api/public/config/'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map<String, dynamic>) {
          await applyPayload(decoded);
        }
      }
    } catch (_) {}
  }

  Future<void> applyPayload(Map<String, dynamic> payload) async {
    config.value = BabifixRemoteConfigData.fromJson(payload);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(payload));
    } catch (_) {}
  }

  /// Une mission prestataire est consideree active/engagee si elle a deja ete
  /// acceptee ou demarree (hors nouvelles demandes "En attente" et hors statuts terminaux).
  static bool isMissionStatusActive(String rawStatus) {
    final s = rawStatus.trim().toLowerCase();
    if (s.isEmpty) return false;
    const nonActive = <String>{
      'en attente',
      'pending',
      'terminee',
      'terminée',
      'annulee',
      'annulée',
      'refusee',
      'refusée',
      'completed',
      'cancelled',
      'canceled',
      'refused',
    };
    return !nonActive.contains(s);
  }

  /// Interroge l'API prestataire pour detecter automatiquement les interventions en cours.
  Future<List<Map<String, dynamic>>> fetchActiveMissions(String? token) async {
    if (token == null || token.trim().isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    try {
      final base = babifixApiBaseUrl();
      final resp = await http
          .get(
            Uri.parse('$base/api/prestataire/requests'),
            headers: <String, String>{
              'Authorization': 'Bearer ${token.trim()}',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return const <Map<String, dynamic>>[];
      final decoded = jsonDecode(resp.body);
      final rawList = decoded is Map
          ? (decoded['items'] ??
              decoded['requests'] ??
              decoded['reservations'] ??
              decoded['results'] ??
              const [])
          : (decoded is List ? decoded : const []);
      if (rawList is! List) return const <Map<String, dynamic>>[];
      final active = <Map<String, dynamic>>[];
      for (final item in rawList) {
        if (item is Map) {
          final m = Map<String, dynamic>.from(item);
          final statut = (m['statut'] ?? m['status'] ?? '').toString();
          if (isMissionStatusActive(statut)) {
            active.add(m);
          }
        }
      }
      return active;
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }
}
