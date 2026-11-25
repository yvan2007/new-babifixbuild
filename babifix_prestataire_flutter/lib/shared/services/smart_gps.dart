import 'dart:async';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

const double kCivAbidjanLat = 5.3600;
const double kCivAbidjanLon = -3.9870;

bool isInCoteIvoireBounds(double lat, double lon) {
  return lat >= 4.0 && lat <= 11.0 && lon >= -9.0 && lon <= -2.0;
}

/// Resultat propre d'une tentative de geolocalisation (sans exception brute).
class SmartGpsResult {
  const SmartGpsResult({
    this.position,
    this.inCoteIvoire = false,
    this.isFallback = false,
    this.permissionDenied = false,
    this.permissionDeniedForever = false,
    this.serviceDisabled = false,
    this.friendlyMessage,
  });

  final LatLng? position;
  final bool inCoteIvoire;
  final bool isFallback;
  final bool permissionDenied;
  final bool permissionDeniedForever;
  final bool serviceDisabled;
  final String? friendlyMessage;

  bool get ok => position != null;
  bool get hasHardError => permissionDenied || serviceDisabled;
}

/// Acquisition GPS robuste multi-paliers pour Android, iOS et emulateur.
Future<SmartGpsResult> acquireSmartGps({bool forceFresh = false}) async {
  try {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return const SmartGpsResult(
        serviceDisabled: true,
        friendlyMessage: 'Activez la localisation (GPS) sur votre telephone.',
      );
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      return const SmartGpsResult(
        permissionDenied: true,
        permissionDeniedForever: true,
        friendlyMessage: 'Acces position bloque. Activez-le dans les reglages.',
      );
    }
    if (perm == LocationPermission.denied) {
      return const SmartGpsResult(
        permissionDenied: true,
        friendlyMessage: 'Autorisez la localisation pour detecter votre commune.',
      );
    }

    Position? pos;

    // 1. Cache GPS instantane si recent et en Cote d'Ivoire
    if (!forceFresh && !kIsWeb) {
      try {
        final cached = await Geolocator.getLastKnownPosition();
        if (cached != null) {
          final age = DateTime.now().difference(cached.timestamp).abs();
          if (age.inMinutes <= 10 &&
              isInCoteIvoireBounds(cached.latitude, cached.longitude)) {
            pos = cached;
          }
        }
      } catch (_) {}
    }

    // 2. Fix equilibre (rapide et fiable en interieur)
    if (pos == null) {
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 7),
          ),
        ).timeout(const Duration(seconds: 8));
      } catch (_) {}
    }

    // 3. Repli Android LocationManager natif
    if (pos == null &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.low,
            forceLocationManager: true,
            timeLimit: const Duration(seconds: 6),
          ),
        ).timeout(const Duration(seconds: 7));
      } catch (_) {}
    }

    // 4. Dernier repli sur cache GPS
    if (pos == null && !kIsWeb) {
      try {
        pos = await Geolocator.getLastKnownPosition();
      } catch (_) {}
    }

    if (pos == null) {
      return const SmartGpsResult(
        position: LatLng(kCivAbidjanLat, kCivAbidjanLon),
        inCoteIvoire: false,
        isFallback: true,
      );
    }

    final inCi = isInCoteIvoireBounds(pos.latitude, pos.longitude);
    if (!inCi) {
      return const SmartGpsResult(
        position: LatLng(kCivAbidjanLat, kCivAbidjanLon),
        inCoteIvoire: false,
        isFallback: true,
      );
    }

    return SmartGpsResult(
      position: LatLng(pos.latitude, pos.longitude),
      inCoteIvoire: true,
      isFallback: false,
    );
  } catch (_) {
    return const SmartGpsResult(
      position: LatLng(kCivAbidjanLat, kCivAbidjanLon),
      inCoteIvoire: false,
      isFallback: true,
    );
  }
}
