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
import '../../user_store.dart';

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

class _ProvidersMapScreenState extends State<ProvidersMapScreen> {
  final _mapCtrl = MapController();
  LatLng? _myPosition;
  List<_Provider> _providers = [];
  bool _loading = true;
  String? _error;
  double _radiusKm = 25;
  _Provider? _selected;

  @override
  void initState() {
    super.initState();
    _locate();
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

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      _myPosition = LatLng(pos.latitude, pos.longitude);
      _mapCtrl.move(_myPosition!, 12);
      await _loadProviders();
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadProviders() async {
    if (_myPosition == null) return;
    final token = await BabifixUserStore.getApiToken();
    final uri = Uri.parse(
      '${babifixApiBaseUrl()}/api/prestataires/'
      '?lat=${_myPosition!.latitude}&lon=${_myPosition!.longitude}&radius_km=${_radiusKm.round()}',
    );
    try {
      final res = await http.get(
        uri,
        headers: {if (token != null) 'Authorization': 'Bearer $token'},
      );
      if (res.statusCode != 200) {
        setState(() { _loading = false; });
        return;
      }
      final data = jsonDecode(res.body);
      final list = (data is List ? data : (data['results'] as List? ?? [])) as List<dynamic>;
      final providers = <_Provider>[];
      for (final item in list) {
        final m = item as Map<String, dynamic>;
        final lat = jsonDoubleNullable(m['service_latitude']);
        final lon = jsonDoubleNullable(m['service_longitude']);
        if (lat == null || lon == null) continue;
        providers.add(_Provider(
          id: jsonInt(m['id'] ?? m['user']),
          name: '${m['user_display'] ?? m['username'] ?? 'Prestataire'}',
          city: '${m['service_city'] ?? ''}',
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
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'app.babifix.client',
              ),
              // Cercle de rayon
              if (_myPosition != null)
                CircleLayer(circles: [
                  CircleMarker(
                    point: _myPosition!,
                    radius: _radiusKm * 1000,
                    useRadiusInMeter: true,
                    color: BabifixDesign.cyan.withValues(alpha: 0.08),
                    borderColor: BabifixDesign.cyan.withValues(alpha: 0.4),
                    borderStrokeWidth: 2,
                  ),
                ]),
              // Ma position
              if (_myPosition != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _myPosition!,
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: BabifixDesign.cyan,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [BoxShadow(color: BabifixDesign.cyan.withValues(alpha: 0.5), blurRadius: 12)],
                      ),
                      child: const Icon(Icons.person, color: Colors.white, size: 20),
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
                            : BabifixDesign.darkNavy,
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
                            Row(
                              children: [
                                Icon(Icons.star_rounded, size: 14, color: BabifixDesign.ciOrange),
                                Text(' ${_selected!.rating.toStringAsFixed(1)}',
                                    style: const TextStyle(fontSize: 12)),
                                const SizedBox(width: 8),
                                Icon(Icons.location_on_rounded, size: 14, color: BabifixDesign.cyan),
                                Text(' ${_selected!.distanceKm.toStringAsFixed(1)} km',
                                    style: TextStyle(fontSize: 12, color: BabifixDesign.cyan)),
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
            const Center(child: CircularProgressIndicator()),
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
