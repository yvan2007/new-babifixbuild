import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../babifix_api_config.dart';
import '../../babifix_design_system.dart';
import '../../json_utils.dart';
import '../../shared/geo_utils.dart';
import '../../user_store.dart';
import '../../shared/widgets/babifix_ring_loader.dart';

class _Provider {
  _Provider({
    required this.id,
    required this.name,
    required this.city,
    required this.lat,
    required this.lon,
    required this.distanceKm,
    this.rating = 0,
    this.photoUrl = '',
  });
  final int id;
  final String name;
  final String city;
  final double lat;
  final double lon;
  final double distanceKm;
  final double rating;
  final String photoUrl;
}

class ProvidersMapScreen extends StatefulWidget {
  const ProvidersMapScreen({super.key});

  @override
  State<ProvidersMapScreen> createState() => _ProvidersMapScreenState();
}

class _ProvidersMapScreenState extends State<ProvidersMapScreen>
    with SingleTickerProviderStateMixin {
  final _mapCtrl = MapController();
  LatLng? _myPosition;
  List<_Provider> _providers = [];
  bool _loading = true;
  String? _error;
  double _radiusKm = 25;
  _Provider? _selected;

  // Animation "radar" (halo pulsant autour de ma position).
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _locate();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _mapCtrl.dispose();
    super.dispose();
  }

  /// Couleur selon la proximité : vert (proche) → orange (moyen) → rouge (loin).
  Color _distanceColor(double km) {
    if (km <= 5) return const Color(0xFF22C55E);
    if (km <= 15) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  String _distanceLabel(double km) {
    if (km <= 5) return 'Très proche';
    if (km <= 15) return 'À proximité';
    return 'Éloigné';
  }

  Future<void> _locate() async {
    setState(() { _loading = true; _error = null; });
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('GPS désactivé');

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) throw Exception('Permission refusée');
      }
      if (perm == LocationPermission.deniedForever) throw Exception('Permission bloquée définitivement');

      // Essai 1 : position cache (instantané, marche aussi sur émulateur).
      Position? pos = await Geolocator.getLastKnownPosition();
      if (pos == null) {
        // Essai 2 : position fraîche avec timeout généreux.
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw Exception('GPS timeout'),
        );
      }
      // Garde-fou émulateur : si on est clairement hors de Côte d'Ivoire
      // (typiquement Mountain View, lat≈37°), on retombe sur Abidjan
      // pour ne pas casser les calculs de distance & l'expérience carto.
      _myPosition = isInCotedIvoire(pos.latitude, pos.longitude)
          ? LatLng(pos.latitude, pos.longitude)
          : const LatLng(kAbidjanLat, kAbidjanLon);
      _mapCtrl.move(_myPosition!, 12);
      await _loadProviders();
    } catch (e) {
      // Repli : si le GPS est indisponible, on utilise l'adresse enregistrée
      // dans le profil pour quand même respecter le périmètre de proximité.
      final saved = await BabifixUserStore.loadAddressCoords();
      if (saved != null) {
        _myPosition = LatLng(saved.lat, saved.lng);
        _mapCtrl.move(_myPosition!, 12);
        await _loadProviders();
        return;
      }
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadProviders() async {
    if (_myPosition == null) return;
    final token = await BabifixUserStore.getApiToken();
    // Si l'utilisateur est connecté → endpoint authentifié (plus complet).
    // Sinon → endpoint public (la map reste utile aux visiteurs anonymes).
    final useAuth = token != null;
    final base = babifixApiBaseUrl();
    final url = useAuth
        ? '$base/api/prestataires/?lat=${_myPosition!.latitude}'
            '&lon=${_myPosition!.longitude}&radius_km=${_radiusKm.round()}'
        : '$base/api/public/providers/?lat=${_myPosition!.latitude}'
            '&lon=${_myPosition!.longitude}&radius=${_radiusKm.round()}';
    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {if (useAuth) 'Authorization': 'Bearer $token'},
      );
      if (res.statusCode != 200) {
        setState(() { _loading = false; });
        return;
      }
      final data = jsonDecode(res.body);
      // L'endpoint public renvoie `{providers:[...]}`, l'authentifié une liste
      // ou `{results:[...]}`. On gère les deux formats.
      List<dynamic> list;
      if (data is List) {
        list = data;
      } else if (data is Map<String, dynamic>) {
        list = (data['providers'] ?? data['results'] ?? <dynamic>[]) as List<dynamic>;
      } else {
        list = const [];
      }
      final providers = <_Provider>[];
      for (final item in list) {
        final m = item as Map<String, dynamic>;
        // Les endpoints utilisent des noms différents : `latitude`/`longitude`
        // (api_public_providers), `service_latitude`/`service_longitude`
        // (api_client_prestataires) ou simplement `lat`/`lon` parfois.
        final lat = jsonDoubleNullable(
          m['service_latitude'] ?? m['latitude'] ?? m['lat'],
        );
        final lon = jsonDoubleNullable(
          m['service_longitude'] ?? m['longitude'] ?? m['lon'],
        );
        if (lat == null || lon == null) continue;
        providers.add(_Provider(
          id: jsonInt(m['id'] ?? m['user']),
          name: '${m['user_display'] ?? m['nom'] ?? m['username'] ?? 'Prestataire'}',
          city: '${m['service_city'] ?? m['ville'] ?? ''}',
          lat: lat,
          lon: lon,
          distanceKm: jsonDouble(m['distance_km']),
          rating: jsonDouble(m['rating']),
          photoUrl: '${m['photo_portrait_url'] ?? ''}',
        ));
      }
      setState(() {
        _providers = providers;
        _loading = false;
      });
    } catch (_) {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prestataires près de moi'),
        backgroundColor: BabifixDesign.darkNavy,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location_rounded),
            onPressed: _locate,
            tooltip: 'Recentrer',
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Carte OSM ──
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: _myPosition ?? const LatLng(5.345, -4.008), // Abidjan
              initialZoom: 12,
              onTap: (_, __) => setState(() => _selected = null),
            ),
            children: [
              TileLayer(
                // CartoDB Voyager : libre, CDN multi-sous-domaines, beaucoup
                // plus fiable que tile.openstreetmap.org direct (qui rate-limite).
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'app.babifix.client',
              ),
              // Cercle de rayon statique + radar pulsant (3 ondes décalées qui
              // scannent visuellement les prestataires à proximité).
              if (_myPosition != null)
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) {
                    final maxR = _radiusKm * 1000.0;
                    final base = _pulse.value;
                    final waves = List.generate(3, (i) {
                      final t = (base + i / 3) % 1.0;
                      return CircleMarker(
                        point: _myPosition!,
                        radius: maxR * t,
                        useRadiusInMeter: true,
                        color: BabifixDesign.cyan.withValues(alpha: 0.06 * (1 - t)),
                        borderColor:
                            BabifixDesign.cyan.withValues(alpha: 0.55 * (1 - t)),
                        borderStrokeWidth: 1.6,
                      );
                    });
                    return CircleLayer(circles: [
                      // Anneau statique du rayon
                      CircleMarker(
                        point: _myPosition!,
                        radius: maxR,
                        useRadiusInMeter: true,
                        color: BabifixDesign.cyan.withValues(alpha: 0.05),
                        borderColor: BabifixDesign.cyan.withValues(alpha: 0.30),
                        borderStrokeWidth: 2,
                      ),
                      ...waves,
                    ]);
                  },
                ),
              // Ma position — halo "radar" pulsant
              if (_myPosition != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _myPosition!,
                    width: 84,
                    height: 84,
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, __) {
                        final t = _pulse.value;
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 26 + t * 56,
                              height: 26 + t * 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: BabifixDesign.cyan
                                    .withValues(alpha: (1 - t) * 0.35),
                              ),
                            ),
                            Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: BabifixDesign.cyan,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                      color: BabifixDesign.cyan
                                          .withValues(alpha: 0.5),
                                      blurRadius: 12)
                                ],
                              ),
                              child: const Icon(Icons.person,
                                  color: Colors.white, size: 16),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ]),
              // Prestataires
              MarkerLayer(
                markers: _providers.map((p) => Marker(
                  point: LatLng(p.lat, p.lon),
                  width: 44,
                  height: 44,
                  child: GestureDetector(
                    onTap: () => setState(() => _selected = p),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: _selected?.id == p.id
                            ? BabifixDesign.ciOrange
                            : _distanceColor(p.distanceKm),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [const BoxShadow(blurRadius: 8, color: Colors.black26)],
                      ),
                      child: const Icon(Icons.handyman_rounded, color: Colors.white, size: 22),
                    ),
                  ),
                )).toList(),
              ),
            ],
          ),

          // ── Filtre rayon ──
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.radar_rounded, size: 18),
                    const SizedBox(width: 8),
                    Text('${_radiusKm.round()} km',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Expanded(
                      child: Slider(
                        value: _radiusKm,
                        min: 5,
                        max: 100,
                        divisions: 19,
                        activeColor: BabifixDesign.cyan,
                        onChanged: (v) => setState(() => _radiusKm = v),
                        onChangeEnd: (_) => _loadProviders(),
                      ),
                    ),
                    Text('${_providers.length} prestataire(s)',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ),

          // ── Fiche prestataire sélectionné ──
          if (_selected != null)
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundImage: _selected!.photoUrl.isNotEmpty
                            ? NetworkImage(_selected!.photoUrl)
                            : null,
                        backgroundColor: BabifixDesign.darkNavy,
                        child: _selected!.photoUrl.isEmpty
                            ? const Icon(Icons.person, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_selected!.name,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                            Text(_selected!.city,
                                style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.star_rounded,
                                    size: 14, color: BabifixDesign.ciOrange),
                                Text(' ${_selected!.rating.toStringAsFixed(1)}',
                                    style: const TextStyle(fontSize: 12)),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _distanceColor(_selected!.distanceKm)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.location_on_rounded,
                                          size: 13,
                                          color: _distanceColor(
                                              _selected!.distanceKm)),
                                      const SizedBox(width: 3),
                                      Text(
                                        '${_selected!.distanceKm.toStringAsFixed(1)} km · ${_distanceLabel(_selected!.distanceKm)}',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: _distanceColor(
                                              _selected!.distanceKm),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: BabifixDesign.ciOrange),
                        onPressed: () {/* Navigate to booking */},
                        child: const Text('Réserver'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Loading / erreur ──
          if (_loading)
            const Center(child: BabifixRingLoader.cyan(size: 28)),
          if (_error != null && !_loading)
            Center(
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_off_rounded, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _locate, child: const Text('Réessayer')),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
