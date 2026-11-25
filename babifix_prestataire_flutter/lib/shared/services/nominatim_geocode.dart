import 'dart:convert';
import 'dart:math' as math;

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

/// Référentiel géolocalisé des communes d'Abidjan et grandes villes de Côte d'Ivoire
/// pour garantir une localisation intelligente, rapide et précise même hors-ligne.
const List<NominatimPlace> kCivCommunesReference = [
  NominatimPlace(
    latitude: 5.3600,
    longitude: -3.9870,
    displayName: 'Cocody · Deux Plateaux, Abidjan',
  ),
  NominatimPlace(
    latitude: 5.3735,
    longitude: -3.9580,
    displayName: 'Cocody · Riviera Palmeraie, Abidjan',
  ),
  NominatimPlace(
    latitude: 5.3980,
    longitude: -3.9885,
    displayName: 'Cocody · Angré 8e Tranche, Abidjan',
  ),
  NominatimPlace(
    latitude: 5.3260,
    longitude: -4.0205,
    displayName: 'Plateau · Centre des Affaires, Abidjan',
  ),
  NominatimPlace(
    latitude: 5.3035,
    longitude: -3.9825,
    displayName: 'Marcory · Zone 4 / Résidentiel, Abidjan',
  ),
  NominatimPlace(
    latitude: 5.3010,
    longitude: -4.0080,
    displayName: 'Treichville · Avenue 16, Abidjan',
  ),
  NominatimPlace(
    latitude: 5.2970,
    longitude: -3.9550,
    displayName: 'Koumassi · Remblais / Grand Carrefour, Abidjan',
  ),
  NominatimPlace(
    latitude: 5.2580,
    longitude: -3.9350,
    displayName: 'Port-Bouët · Vridi / Gonzagueville, Abidjan',
  ),
  NominatimPlace(
    latitude: 5.3480,
    longitude: -4.0790,
    displayName: 'Yopougon · Maroc / Niangon, Abidjan',
  ),
  NominatimPlace(
    latitude: 5.4190,
    longitude: -4.0190,
    displayName: 'Abobo · Centre / Dokui, Abidjan',
  ),
  NominatimPlace(
    latitude: 5.3580,
    longitude: -4.0230,
    displayName: 'Adjamé · Liberté / 220 Logements, Abidjan',
  ),
  NominatimPlace(
    latitude: 5.3370,
    longitude: -4.0410,
    displayName: 'Attécoubé · Sebroko, Abidjan',
  ),
  NominatimPlace(
    latitude: 5.3560,
    longitude: -3.8880,
    displayName: 'Bingerville · Faya / Cité, Grand Abidjan',
  ),
  NominatimPlace(
    latitude: 5.4940,
    longitude: -4.0510,
    displayName: 'Anyama · Résidentiel, Grand Abidjan',
  ),
  NominatimPlace(
    latitude: 5.2110,
    longitude: -3.7380,
    displayName: 'Grand-Bassam · Quartier France / Mockeyville',
  ),
  NominatimPlace(
    latitude: 7.6900,
    longitude: -5.0300,
    displayName: 'Bouaké · Air France / Commerce',
  ),
  NominatimPlace(
    latitude: 6.8276,
    longitude: -5.2893,
    displayName: 'Yamoussoukro · Habitat / 220 Logements',
  ),
  NominatimPlace(
    latitude: 4.7485,
    longitude: -6.6363,
    displayName: 'San-Pédro · Cité / Bardot',
  ),
  NominatimPlace(
    latitude: 6.8774,
    longitude: -6.4502,
    displayName: 'Daloa · Lobia / Commerce',
  ),
  NominatimPlace(
    latitude: 9.4580,
    longitude: -5.6296,
    displayName: 'Korhogo · Koko / Petit Paris',
  ),
  NominatimPlace(
    latitude: 7.4125,
    longitude: -7.5538,
    displayName: 'Man · Commerce / Libreville',
  ),
  NominatimPlace(
    latitude: 6.1319,
    longitude: -5.9506,
    displayName: 'Gagnoa · Garahio / Dioulabougou',
  ),
  NominatimPlace(
    latitude: 6.7297,
    longitude: -3.4964,
    displayName: 'Abengourou · Cafetou / Indénié',
  ),
  NominatimPlace(
    latitude: 5.8374,
    longitude: -5.3572,
    displayName: 'Divo · Dialogue / Libanais',
  ),
  NominatimPlace(
    latitude: 5.7856,
    longitude: -6.6083,
    displayName: 'Soubré · Camp Manois',
  ),
  NominatimPlace(
    latitude: 5.9275,
    longitude: -4.2133,
    displayName: 'Agboville · Château / Artisanal',
  ),
  NominatimPlace(
    latitude: 8.0402,
    longitude: -2.8000,
    displayName: 'Bondoukou · Zanzan',
  ),
  NominatimPlace(
    latitude: 9.5051,
    longitude: -7.5643,
    displayName: 'Odienné · Kabala / Denguélé',
  ),
  NominatimPlace(
    latitude: 7.9611,
    longitude: -6.6731,
    displayName: 'Séguéla · Worodougou',
  ),
  NominatimPlace(
    latitude: 6.5580,
    longitude: -5.0177,
    displayName: 'Toumodi · Centre',
  ),
  NominatimPlace(
    latitude: 5.8984,
    longitude: -4.8229,
    displayName: 'Tiassalé · Centre',
  ),
  NominatimPlace(
    latitude: 6.1069,
    longitude: -3.8619,
    displayName: 'Adzopé · Mé',
  ),
  NominatimPlace(
    latitude: 5.3255,
    longitude: -4.3769,
    displayName: 'Dabou · Grands-Ponts',
  ),
  NominatimPlace(
    latitude: 5.4678,
    longitude: -3.2071,
    displayName: 'Aboisso · Sud-Comoé',
  ),
];

double _distKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180.0;
  final dLon = (lon2 - lon1) * math.pi / 180.0;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180.0) *
          math.cos(lat2 * math.pi / 180.0) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return r * c;
}

/// Retourne la commune/ville la plus proche si a moins de 35 km, sinon libelle generique CI.
NominatimPlace resolveNearestCivCommune(double lat, double lon) {
  var best = kCivCommunesReference.first;
  var bestDist = double.infinity;
  for (final item in kCivCommunesReference) {
    final d = _distKm(lat, lon, item.latitude, item.longitude);
    if (d < bestDist) {
      bestDist = d;
      best = item;
    }
  }
  final label = bestDist <= 35.0 ? best.displayName : 'Ma position (Cote d\'Ivoire)';
  return NominatimPlace(
    latitude: lat,
    longitude: lon,
    displayName: label,
  );
}

/// Reverse geocoding : coordonnées GPS -> libellé localité précis (commune + quartier + ville, CI).
Future<NominatimPlace?> nominatimReverse(double lat, double lon) async {
  try {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'lat': '$lat',
      'lon': '$lon',
      'format': 'json',
      'zoom': '16',
      'addressdetails': '1',
    });
    final res = await http
        .get(
          uri,
          headers: {
            'User-Agent':
                'BABIFIX-Mobile/1.0 (contact@babifix.ci)',
            'Accept-Language': 'fr',
          },
        )
        .timeout(const Duration(seconds: 5));
    if (res.statusCode == 200) {
      final j = jsonDecode(res.body);
      if (j is Map<String, dynamic>) {
        String label = '';
        final addr = j['address'];
        if (addr is Map<String, dynamic>) {
          final parts = <String>[];
          for (final k in const [
            'neighbourhood',
            'quarter',
            'suburb',
            'city_district',
            'municipality',
            'town',
            'city',
          ]) {
            final v = addr[k];
            if (v is String && v.trim().isNotEmpty && !parts.contains(v.trim())) {
              parts.add(v.trim());
            }
            if (parts.length >= 3) break;
          }
          label = parts.join(', ');
        }
        if (label.isEmpty && j['display_name'] is String) {
          label = (j['display_name'] as String)
              .split(',')
              .take(3)
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .join(', ');
        }
        // Si Nominatim ne renvoie qu'un "Abidjan" trop vague, on enrichit avec la commune exacte
        if (label.isNotEmpty && label.toLowerCase() != 'abidjan') {
          return NominatimPlace(
            latitude: lat,
            longitude: lon,
            displayName: label,
          );
        }
      }
    }
  } catch (_) {}

  return resolveNearestCivCommune(lat, lon);
}

Future<List<NominatimPlace>> nominatimSearch(String query) async {
  final q = query.trim();
  if (q.length < 2) return [];

  final qLower = q.toLowerCase();
  final localMatches = kCivCommunesReference
      .where((p) => p.displayName.toLowerCase().contains(qLower))
      .toList();

  try {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': q,
      'format': 'json',
      'limit': '8',
      'addressdetails': '1',
      'countrycodes': 'ci',
    });

    final res = await http
        .get(
          uri,
          headers: {
            'User-Agent':
                'BABIFIX-Mobile/1.0 (contact@babifix.ci)',
            'Accept-Language': 'fr',
          },
        )
        .timeout(const Duration(seconds: 5));

    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body);
      if (decoded is List<dynamic>) {
        final out = <NominatimPlace>[...localMatches];
        for (final raw in decoded) {
          if (raw is! Map<String, dynamic>) continue;
          final p = NominatimPlace.fromJson(raw);
          if (p != null &&
              !out.any((e) =>
                  e.displayName.toLowerCase() == p.displayName.toLowerCase())) {
            out.add(p);
          }
        }
        return out;
      }
    }
  } catch (_) {}

  return localMatches;
}
