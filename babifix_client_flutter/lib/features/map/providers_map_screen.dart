import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

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
import '../providers/provider_profile_premium_screen.dart';

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
  double _zoom = 12; // zoom courant (pour le clustering)
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

  /// Regroupe (clustering) les prestataires proches selon le zoom courant :
  /// 1 presta → pin goutte avec photo ; plusieurs → badge avec le compte
  /// (tap = zoom sur le groupe). Évite que les pins se chevauchent.
  List<Marker> _buildClusteredMarkers() {
    if (_providers.isEmpty) return const [];
    // Taille de cellule (degrés) selon le zoom : plus on zoome, plus c'est fin.
    final cell = (90.0 / math.pow(2, _zoom)).clamp(0.0004, 6.0);
    final buckets = <String, List<_Provider>>{};
    for (final p in _providers) {
      final key = '${(p.lat / cell).floor()}_${(p.lon / cell).floor()}';
      (buckets[key] ??= <_Provider>[]).add(p);
    }
    final markers = <Marker>[];
    buckets.forEach((_, group) {
      if (group.length == 1) {
        markers.add(_providerPin(group.first));
      } else {
        final lat = group.map((e) => e.lat).reduce((a, b) => a + b) / group.length;
        final lon = group.map((e) => e.lon).reduce((a, b) => a + b) / group.length;
        markers.add(_clusterBadge(LatLng(lat, lon), group.length));
      }
    });
    return markers;
  }

  Marker _providerPin(_Provider p) {
    final sel = _selected?.id == p.id;
    final color = sel ? BabifixDesign.ciOrange : _distanceColor(p.distanceKm);
    return Marker(
      point: LatLng(p.lat, p.lon),
      width: 54,
      height: 66,
      alignment: Alignment.bottomCenter, // la pointe (bas) touche la position
      child: GestureDetector(
        onTap: () => setState(() => _selected = p),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          scale: sel ? 1.15 : 1.0,
          child: _TeardropPin(color: color, photoUrl: p.photoUrl),
        ),
      ),
    );
  }

  Marker _clusterBadge(LatLng center, int count) {
    return Marker(
      point: center,
      width: 52,
      height: 52,
      child: GestureDetector(
        onTap: () => _mapCtrl.move(center, (_zoom + 2).clamp(3.0, 18.0)),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [BabifixDesign.cyan, BabifixDesign.ciBlue],
            ),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                blurRadius: 12,
                spreadRadius: 1,
                color: BabifixDesign.cyan.withValues(alpha: 0.5),
                offset: const Offset(0, 3),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            count > 99 ? '99+' : '$count',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
          ),
        ),
      ),
    );
  }

  Future<void> _locate({bool forceFresh = false}) async {
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

      // forceFresh = appui sur « recentrer » : on IGNORE le cache pour capter
      // la position ACTUELLE (sinon, après un déplacement, la carte resterait
      // bloquée sur l'ancien point en cache — ex. Cocody alors qu'on est à Bassam).
      Position? pos;
      if (!forceFresh) {
        // Démarrage : position cache (instantané) pour un affichage immédiat.
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) {
        // Position fraîche (GPS réel) avec timeout généreux.
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
        ).timeout(
          const Duration(seconds: 12),
          onTimeout: () => throw Exception('GPS timeout'),
        );
      }
      // Position GPS réelle si en Côte d'Ivoire. Hors CI (émulateur), on
      // préfère l'adresse RÉELLE enregistrée au profil plutôt qu'un point
      // fictif (Abidjan), pour des distances exactes.
      if (isInCotedIvoire(pos.latitude, pos.longitude)) {
        _myPosition = LatLng(pos.latitude, pos.longitude);
      } else {
        final saved = await BabifixUserStore.loadAddressCoords();
        _myPosition = saved != null
            ? LatLng(saved.lat, saved.lng)
            : const LatLng(kAbidjanLat, kAbidjanLon);
      }
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
        ? '$base/api/client/prestataires?lat=${_myPosition!.latitude}'
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
        list = (data['items'] ?? data['providers'] ?? data['results'] ?? <dynamic>[]) as List<dynamic>;
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
        // Garde-fou : on n'affiche QUE les prestataires dont les coordonnées
        // sont en Côte d'Ivoire. Une mauvaise capture GPS à l'inscription
        // (ex. position par défaut d'un émulateur → Shanghai) ne place plus un
        // pin à l'autre bout du monde et ne fausse plus la carte.
        if (!isInCotedIvoire(lat, lon)) continue;
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
        title: const Text(
          'Prestataires près de moi',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: BabifixDesign.darkNavy,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location_rounded),
            onPressed: () => _locate(forceFresh: true),
            tooltip: 'Recentrer sur ma position actuelle',
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
              // Suivi du zoom → recalcul du clustering (regroupement des pins
              // proches). On ne rebuild que si le zoom change notablement.
              onPositionChanged: (camera, hasGesture) {
                if ((camera.zoom - _zoom).abs() > 0.3) {
                  setState(() => _zoom = camera.zoom);
                }
              },
            ),
            children: [
              TileLayer(
                // CartoDB Voyager : libre, CDN multi-sous-domaines, beaucoup
                // plus fiable que tile.openstreetmap.org direct (qui rate-limite).
                // {r} = tuiles HD/Retina (@2x) → rendu NET sur les écrans haute
                // densité (la plupart des téléphones) = beaucoup plus pro, gratuit.
                // Mode sombre auto : Dark Matter si le téléphone est en thème
                // sombre, sinon Voyager clair.
                urlTemplate: MediaQuery.platformBrightnessOf(context) ==
                        Brightness.dark
                    ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                    : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                retinaMode: RetinaMode.isHighDensity(context),
                tileProvider: NetworkTileProvider(),
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
              // Prestataires (sous le marqueur de position)
              MarkerLayer(
                markers: _buildClusteredMarkers(),
              ),
              // Ma position — halo "radar" pulsant, TOUJOURS au-dessus des pins
              // pour rester visible même quand des prestataires sont au même endroit.
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
                              width: 30,
                              height: 30,
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
                              child: const Icon(Icons.person_pin_circle,
                                  color: Colors.white, size: 18),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ]),
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
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: BabifixDesign.navy)),
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
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => ProviderProfilePremiumScreen(
                              providerId: _selected!.id,
                            ),
                          ),
                        ),
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
                      FilledButton(onPressed: () => _locate(forceFresh: true), child: const Text('Réessayer')),
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

/// Pin « goutte » : avatar rond (photo du prestataire) + pointe vers le bas.
class _TeardropPin extends StatelessWidget {
  const _TeardropPin({required this.color, required this.photoUrl});
  final Color color;
  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                blurRadius: 8,
                color: color.withValues(alpha: 0.45),
                offset: const Offset(0, 3),
              ),
              const BoxShadow(blurRadius: 5, color: Colors.black26),
            ],
          ),
          child: CircleAvatar(
            radius: 16,
            backgroundColor: Colors.white,
            backgroundImage:
                photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
            child: photoUrl.isEmpty
                ? Icon(Icons.handyman_rounded, color: color, size: 17)
                : null,
          ),
        ),
        // Pointe (triangle) qui désigne l'emplacement exact.
        Transform.translate(
          offset: const Offset(0, -2),
          child: CustomPaint(size: const Size(14, 9), painter: _PinTip(color)),
        ),
      ],
    );
  }
}

class _PinTip extends CustomPainter {
  _PinTip(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    // Bordure blanche pour rester net sur la carte.
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PinTip old) => old.color != color;
}
