/// LocationReporter — Push automatique de la position GPS du prestataire.
///
/// Stratégie :
/// - Au démarrage de l'app + à chaque passage en foreground, lit la
///   position GPS si autorisée et l'envoie à `/api/prestataire/location/update`.
/// - Throttle : pas plus d'un push toutes les 5 minutes (sauf forceFlush).
/// - Best-effort silencieux : aucun blocage UI si erreur.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../babifix_api_config.dart';
import '../shared/services/babifix_user_store.dart';

class LocationReporter with WidgetsBindingObserver {
  LocationReporter._();
  static final LocationReporter instance = LocationReporter._();

  DateTime? _lastPushAt;
  bool _initialized = false;

  Future<void> attach() async {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    // Premier push au démarrage (non bloquant)
    unawaited(pushNow());
  }

  void detach() {
    if (!_initialized) return;
    _initialized = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(pushNow());
    }
  }

  /// Force l'envoi immédiat (ignore le throttle).
  Future<void> pushNow({bool forceFlush = false}) async {
    if (!forceFlush && _lastPushAt != null) {
      final since = DateTime.now().difference(_lastPushAt!);
      if (since < const Duration(minutes: 5)) return;
    }
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final svcOn = await Geolocator.isLocationServiceEnabled();
      if (!svcOn) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      ).timeout(const Duration(seconds: 10));

      // GARDE-FOU CÔTE D'IVOIRE : on ne rapporte JAMAIS une position hors CIV
      // (ex. GPS d'émulateur à Shanghai) — sinon la position enregistrée du
      // prestataire serait écrasée au login et il se retrouverait « en Chine ».
      const latMin = 4.0, latMax = 11.0, lonMin = -9.0, lonMax = -2.0;
      if (pos.latitude < latMin ||
          pos.latitude > latMax ||
          pos.longitude < lonMin ||
          pos.longitude > lonMax) {
        return;
      }

      // Reverse geocoding facultatif pour récupérer la ville
      String? ville;
      try {
        final r = await http.get(
          Uri.parse(
            'https://nominatim.openstreetmap.org/reverse'
            '?lat=${pos.latitude}&lon=${pos.longitude}&format=json&accept-language=fr',
          ),
          headers: {'User-Agent': 'BABIFIX/1.0 prestataire'},
        ).timeout(const Duration(seconds: 5));
        if (r.statusCode == 200) {
          final j = jsonDecode(r.body) as Map<String, dynamic>;
          final addr = j['address'] as Map<String, dynamic>?;
          if (addr != null) {
            ville = (addr['city'] ??
                    addr['town'] ??
                    addr['village'] ??
                    addr['municipality'] ??
                    addr['county'])
                ?.toString();
          }
        }
      } catch (_) {}

      final token = await BabifixUserStore.getApiToken();
      if (token == null || token.isEmpty) return;

      final resp = await http
          .post(
            Uri.parse(
              '${babifixApiBaseUrl()}/api/prestataire/location/update',
            ),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'latitude': pos.latitude,
              'longitude': pos.longitude,
              if (ville != null && ville.isNotEmpty) 'ville': ville,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        _lastPushAt = DateTime.now();
        debugPrint(
          '[LocationReporter] pushed lat=${pos.latitude}, lon=${pos.longitude}, ville=$ville',
        );
      } else {
        debugPrint(
          '[LocationReporter] push failed ${resp.statusCode}: ${resp.body}',
        );
      }
    } catch (e) {
      debugPrint('[LocationReporter] silent error: $e');
    }
  }
}
