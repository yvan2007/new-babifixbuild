import 'dart:convert';

import 'package:http/http.dart' as http;

/// Résultat de recherche [Nominatim](https://nominatim.org/release-docs/latest/api/Search/).
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

/// Recherche d’adresses / lieux (priorité Côte d’Ivoire).
///
/// Politique Nominatim : requêtes espacées ; l’app debounce côté UI.
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
        'User-Agent': 'BabifixClient/1.0 (reservation; +https://babifix.local)',
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
