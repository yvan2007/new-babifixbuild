import 'dart:convert';

import 'package:http/http.dart' as http;

class NominatimPlace {
  const NominatimPlace({
    required this.latitude,
    required this.longitude,
    required this.displayName,
  });

  final double latitude;
  final double longitude;
  final String displayName;

  static NominatimPlace? fromJson(Map<String, dynamic> j) {
    final lat = j['lat'];
    final lon = j['lon'];
    final name = j['display_name'];
    if (lat == null || lon == null) return null;
    final la = lat is num ? lat.toDouble() : double.tryParse('$lat');
    final lo = lon is num ? lon.toDouble() : double.tryParse('$lon');
    if (la == null || lo == null) return null;
    return NominatimPlace(
      latitude: la,
      longitude: lo,
      displayName: name is String ? name : '$name',
    );
  }
}

/// Reverse geocoding : coordonnées GPS → libellé localité (commune/ville, CI).
/// Utilisé par le bouton « Me localiser » de l'inscription.
Future<NominatimPlace?> nominatimReverse(double lat, double lon) async {
  try {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'lat': '$lat',
      'lon': '$lon',
      'format': 'json',
      'zoom': '14', // niveau quartier/commune
      'addressdetails': '1',
    });
    final res = await http.get(
      uri,
      headers: {
        'User-Agent': 'BabifixPrestataire/1.0 (inscription; +https://babifix.local)',
        'Accept-Language': 'fr',
      },
    );
    if (res.statusCode != 200) return null;
    final j = jsonDecode(res.body);
    if (j is! Map<String, dynamic>) return null;
    // Construit un libellé court : quartier/commune + ville si dispo.
    String label = '';
    final addr = j['address'];
    if (addr is Map<String, dynamic>) {
      final parts = <String>[];
      for (final k in const [
        'suburb', 'neighbourhood', 'quarter', 'village', 'town', 'city',
        'municipality', 'county', 'state',
      ]) {
        final v = addr[k];
        if (v is String && v.isNotEmpty && !parts.contains(v)) parts.add(v);
        if (parts.length >= 2) break;
      }
      label = parts.join(', ');
    }
    if (label.isEmpty && j['display_name'] is String) {
      label = (j['display_name'] as String).split(',').take(2).join(', ').trim();
    }
    return NominatimPlace(latitude: lat, longitude: lon, displayName: label);
  } catch (_) {
    return null;
  }
}

Future<List<NominatimPlace>> nominatimSearch(String query) async {
  final q = query.trim();
  if (q.length < 3) return [];

  try {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': q,
      'format': 'json',
      'limit': '10',
      'addressdetails': '1',
      'countrycodes': 'ci',
    });

    final res = await http.get(
      uri,
      headers: {
        'User-Agent': 'BabifixPrestataire/1.0 (inscription; +https://babifix.local)',
        'Accept-Language': 'fr',
      },
    );

    if (res.statusCode != 200) return [];

    final decoded = jsonDecode(res.body);
    if (decoded is! List<dynamic>) return [];

    final out = <NominatimPlace>[];
    for (final raw in decoded) {
      if (raw is! Map<String, dynamic>) continue;
      final p = NominatimPlace.fromJson(raw);
      if (p != null) out.add(p);
    }
    return out;
  } catch (_) {
    return [];
  }
}
