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
import '../../shared/services/nominatim_geocode.dart';
import '../../user_store.dart';
import '../../shared/widgets/babifix_button.dart';
import '../../shared/widgets/babifix_page_route.dart';
import '../../shared/widgets/babifix_ring_loader.dart';
import '../../shared/widgets/babifix_sheet.dart';
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
    this.category = '',
    this.premiumTier = 'standard',
    this.premiumBadge = '',
    this.disponible = true,
  });
  final int id;
  final String name;
  final String city;
  final double lat;
  final double lon;
  final double distanceKm;
  final double rating;
  final String photoUrl;
  final String category;
  final String premiumTier;
  final String premiumBadge;
  final bool disponible;
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
  bool _hasExactUserPosition = false;
  String _myCityLabel = '';
  List<_Provider> _providers = [];
  bool _loading = true;
  String? _error;
  double _radiusKm = 25;
  double _zoom = 12; // zoom courant (pour le clustering)
  _Provider? _selected;

  // Filtre catégorie de la carte (null = toutes les catégories).
  String? _selectedCategory;

  /// Prestataires réellement affichés = filtrés par la catégorie sélectionnée.
  List<_Provider> get _visibleProviders => _selectedCategory == null
      ? _providers
      : _providers.where((p) => p.category == _selectedCategory).toList();

  /// Catégories distinctes présentes parmi les prestataires chargés.
  List<String> get _categories {
    final set = <String>{};
    for (final p in _providers) {
      if (p.category.isNotEmpty) set.add(p.category);
    }
    final list = set.toList()..sort();
    return list;
  }

  // Style de carte choisi par l'utilisateur ('' = auto selon le thème actif,
  // sinon 'light' / 'dark' / 'satellite').
  String _mapStyle = '';

  String _effectiveStyle() {
    if (_mapStyle.isNotEmpty) return _mapStyle;
    return Theme.of(context).brightness == Brightness.dark
        ? 'dark'
        : 'light';
  }

  String _tileUrl() {
    switch (_effectiveStyle()) {
      case 'dark':
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}';
      case 'satellite':
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
      default:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}';
    }
  }

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

  /// Couleur Direction 3 Hybride selon palier ou proximite.
  Color _pinRingColor(_Provider p) {
    final tier = p.premiumTier.toLowerCase();
    if (tier == 'gold') return const Color(0xFFB45309); // Or Laiton
    if (tier == 'silver') return const Color(0xFF0E3B2E); // Emeraude Pro
    return _distanceColor(p.distanceKm);
  }

  Color _distanceColor(double km) {
    if (km <= 5) return const Color(0xFF047857);
    if (km <= 15) return const Color(0xFFB45309);
    return const Color(0xFFC2410C);
  }

  String _distanceLabel(double km) {
    if (km <= 5) return 'Très proche';
    if (km <= 15) return 'À proximité';
    return 'Secteur élargi';
  }

  /// Regroupe (clustering) les prestataires proches selon le zoom courant :
  /// 1 presta → pin goutte avec photo ; plusieurs → badge avec le compte
  /// (tap = zoom sur le groupe). Évite que les pins se chevauchent.
  List<Marker> _buildClusteredMarkers() {
    final visible = _visibleProviders;
    if (visible.isEmpty) return const [];
    // Taille de cellule (degrés) selon le zoom : plus on zoome, plus c'est fin.
    final cell = (90.0 / math.pow(2, _zoom)).clamp(0.0004, 6.0);
    final buckets = <String, List<_Provider>>{};
    for (final p in visible) {
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
        markers.add(_clusterBadge(LatLng(lat, lon), List<_Provider>.from(group)));
      }
    });
    return markers;
  }

  Marker _providerPin(_Provider p) {
    final sel = _selected?.id == p.id;
    final color = sel ? const Color(0xFFC2410C) : _pinRingColor(p);
    final isGold = p.premiumTier.toLowerCase() == 'gold';
    return Marker(
      point: LatLng(p.lat, p.lon),
      width: 58,
      height: 70,
      alignment: Alignment.bottomCenter,
      child: GestureDetector(
        onTap: () => setState(() => _selected = p),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          scale: sel ? 1.18 : 1.0,
          child: _TeardropPin(
            color: color,
            photoUrl: p.photoUrl,
            isGold: isGold,
          ),
        ),
      ),
    );
  }

  void _showClusterSheet(List<_Provider> group) {
    final sorted = [...group]
      ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    showBabifixModalSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0B1B34),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(
                children: [
                  const Icon(Icons.groups_rounded,
                      color: Color(0xFFFDE68A), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '${group.length} artisans dans cette zone',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                itemCount: sorted.length,
                separatorBuilder: (_, __) =>
                    const Divider(color: Colors.white12, height: 1),
                itemBuilder: (_, i) {
                  final p = sorted[i];
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 22,
                      backgroundColor: const Color(0xFF1E293B),
                      backgroundImage: p.photoUrl.isNotEmpty
                          ? NetworkImage(p.photoUrl)
                          : null,
                      child: p.photoUrl.isEmpty
                          ? const Icon(Icons.person, color: Colors.white70)
                          : null,
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (p.premiumBadge.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: p.premiumTier == 'gold'
                                  ? const Color(0xFFB45309)
                                  : const Color(0xFF0E3B2E),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              p.premiumBadge,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      '${p.category.isNotEmpty ? '${p.category} · ' : ''}${p.city}${p.distanceKm > 0 ? ' · ${p.distanceKm.toStringAsFixed(1)} km' : ''}',
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 12),
                    ),
                    trailing:
                        const Icon(Icons.chevron_right, color: Colors.white54),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      setState(() => _selected = p);
                      _mapCtrl.move(
                          LatLng(p.lat, p.lon), math.max(_zoom, 15.0));
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Marker _clusterBadge(LatLng center, List<_Provider> group) {
    final count = group.length;
    return Marker(
      point: center,
      width: 50,
      height: 50,
      child: GestureDetector(
        onTap: () => _showClusterSheet(group),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0B1B34),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFDE68A), width: 2.5),
            boxShadow: const [
              BoxShadow(
                blurRadius: 10,
                color: Colors.black38,
                offset: Offset(0, 3),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            count > 99 ? '99+' : '$count',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
          ),
        ),
      ),
    );
  }

  Future<void> _updateCityBadge(LatLng pos) async {
    try {
      final place = await nominatimReverse(pos.latitude, pos.longitude);
      if (!mounted || place == null) return;
      setState(() => _myCityLabel = place.displayName);
    } catch (_) {}
  }

  void _safeMoveMap(LatLng center, double zoom) {
    try {
      _mapCtrl.move(center, zoom);
    } catch (_) {}
  }

  Future<void> _locate({bool forceFresh = false}) async {
    setState(() { _loading = true; _error = null; });
    try {
      // 1) Centrage instantane sur position cachee ou adresse enregistree (sans attendre 12s de GPS)
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      LocationPermission perm = LocationPermission.denied;
      if (serviceEnabled) {
        perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
      }
      final gpsGranted = serviceEnabled &&
          (perm == LocationPermission.always ||
              perm == LocationPermission.whileInUse);

      Position? pos;
      if (gpsGranted && !forceFresh) {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos != null && isInCotedIvoire(pos.latitude, pos.longitude)) {
        _myPosition = LatLng(pos.latitude, pos.longitude);
        _hasExactUserPosition = true;
        _updateCityBadge(_myPosition!);
      } else {
        final saved = await BabifixUserStore.loadAddressCoords();
        if (saved != null) {
          _myPosition = LatLng(saved.lat, saved.lng);
          _hasExactUserPosition = true;
          _updateCityBadge(_myPosition!);
        } else {
          // Vue nationale Cote d'Ivoire (Yamoussoukro) immediate pendant l'acquisition GPS
          _myPosition = const LatLng(6.8276, -5.2893);
          _hasExactUserPosition = false;
          _radiusKm = 100;
          _myCityLabel = 'Côte d\'Ivoire (toutes zones)';
        }
      }
      if (mounted) {
        _safeMoveMap(_myPosition!, _hasExactUserPosition ? 12.5 : 6.8);
      }

      // 2) Charger les prestataires tout de suite, et en parallele affiner le GPS
      final loadFuture = _loadProviders();
      if (gpsGranted && (forceFresh || pos == null)) {
        Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.medium),
        ).timeout(const Duration(seconds: 6)).then((freshPos) {
          if (!mounted ||
              !isInCotedIvoire(freshPos.latitude, freshPos.longitude)) {
            return;
          }
          setState(() {
            _myPosition = LatLng(freshPos.latitude, freshPos.longitude);
            _hasExactUserPosition = true;
            if (_radiusKm >= 100) _radiusKm = 25;
          });
          _updateCityBadge(_myPosition!);
          _safeMoveMap(_myPosition!, 12.5);
          _loadProviders();
        }).catchError((_) {});
      }
      await loadFuture;
    } catch (e) {
      final saved = await BabifixUserStore.loadAddressCoords();
      if (saved != null) {
        _myPosition = LatLng(saved.lat, saved.lng);
        _hasExactUserPosition = true;
        _updateCityBadge(_myPosition!);
        _safeMoveMap(_myPosition!, 12.5);
        await _loadProviders();
        return;
      }
      // Dernier repli : carte nationale Cote d'Ivoire plutot qu'ecran d'erreur bloquant
      _myPosition = const LatLng(6.8276, -5.2893);
      _hasExactUserPosition = false;
      _radiusKm = 100;
      _myCityLabel = 'Côte d\'Ivoire (activez le GPS)';
      _safeMoveMap(_myPosition!, 6.8);
      await _loadProviders();
    } finally {
      if (mounted && _loading) {
        setState(() { _loading = false; });
      }
    }
  }

  Future<void> _loadProviders() async {
    if (_myPosition == null) {
      if (mounted) setState(() { _loading = false; });
      return;
    }
    final token = await BabifixUserStore.getApiToken();
    final useAuth = token != null;
    final base = babifixApiBaseUrl();
    final String url;
    if (_hasExactUserPosition) {
      url = useAuth
          ? '$base/api/client/prestataires?lat=${_myPosition!.latitude}'
              '&lon=${_myPosition!.longitude}&radius_km=${_radiusKm.round()}&page_size=50'
          : '$base/api/public/providers/?lat=${_myPosition!.latitude}'
              '&lon=${_myPosition!.longitude}&radius=${_radiusKm.round()}';
    } else {
      url = useAuth
          ? '$base/api/client/prestataires?page_size=50'
          : '$base/api/public/providers/';
    }
    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {if (useAuth) 'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 12));
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
          rating: jsonDouble(m['average_rating'] ?? m['rating']),
          photoUrl: '${m['photo_portrait_url'] ?? m['image_url'] ?? ''}',
          category: '${m['category_nom'] ?? m['specialite'] ?? ''}'.trim(),
          premiumTier: '${m['premium_tier'] ?? 'standard'}',
          premiumBadge: '${m['premium_badge'] ?? ''}'.trim(),
          disponible: m['disponible'] != false,
        ));
      }
      setState(() {
        _providers = providers;
        // Si la catégorie filtrée n'existe plus dans les résultats, on la retire
        // (évite un dropdown avec une valeur absente + une carte vide).
        if (_selectedCategory != null &&
            !providers.any((p) => p.category == _selectedCategory)) {
          _selectedCategory = null;
        }
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
          // Sélecteur de style de carte (Clair / Sombre / Satellite).
          PopupMenuButton<String>(
            icon: const Icon(Icons.layers_rounded),
            tooltip: 'Style de carte',
            onSelected: (v) => setState(() => _mapStyle = v),
            itemBuilder: (ctx) => [
              CheckedPopupMenuItem(
                value: 'light',
                checked: _mapStyle == 'light',
                child: const Text('Clair'),
              ),
              CheckedPopupMenuItem(
                value: 'dark',
                checked: _mapStyle == 'dark',
                child: const Text('Sombre (nuit)'),
              ),
              CheckedPopupMenuItem(
                value: 'satellite',
                checked: _mapStyle == 'satellite',
                child: const Text('Satellite'),
              ),
              const PopupMenuDivider(),
              CheckedPopupMenuItem(
                value: '',
                checked: _mapStyle == '',
                child: const Text('Auto (système)'),
              ),
            ],
          ),
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
              initialCenter: _myPosition ?? const LatLng(6.8276, -5.2893),
              initialZoom: _hasExactUserPosition ? 12.5 : 6.8,
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF0F172A)
                  : const Color(0xFFF1F5F9),
              onTap: (_, __) => setState(() => _selected = null),
              // Suivi du zoom -> recalcul du clustering (regroupement des pins
              // proches). On ne rebuild que si le zoom change notablement.
              onPositionChanged: (camera, hasGesture) {
                if ((camera.zoom - _zoom).abs() > 0.3) {
                  setState(() => _zoom = camera.zoom);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _tileUrl(),
                retinaMode: false,
                userAgentPackageName: 'com.babifix.client',
              ),
              if (_myPosition != null && _hasExactUserPosition)
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) {
                    final maxR = _radiusKm * 1000.0;
                    final base = _pulse.value;
                    final waves = List.generate(2, (i) {
                      final t = (base + i / 2) % 1.0;
                      return CircleMarker(
                        point: _myPosition!,
                        radius: maxR * t,
                        useRadiusInMeter: true,
                        color: const Color(0xFF0B1B34).withValues(alpha: 0.04 * (1 - t)),
                        borderColor: const Color(0xFFB45309).withValues(alpha: 0.42 * (1 - t)),
                        borderStrokeWidth: 1.5,
                      );
                    });
                    return CircleLayer(circles: [
                      CircleMarker(
                        point: _myPosition!,
                        radius: maxR,
                        useRadiusInMeter: true,
                        color: const Color(0xFF0B1B34).withValues(alpha: 0.04),
                        borderColor: const Color(0xFF0B1B34).withValues(alpha: 0.25),
                        borderStrokeWidth: 1.6,
                      ),
                      ...waves,
                    ]);
                  },
                ),
              // Prestataires (sous le marqueur de position)
              MarkerLayer(
                markers: _buildClusteredMarkers(),
              ),
              // Ma position
              if (_myPosition != null && _hasExactUserPosition)
                MarkerLayer(markers: [
                  Marker(
                    point: _myPosition!,
                    width: 78,
                    height: 78,
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, __) {
                        final t = _pulse.value;
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 26 + t * 50,
                              height: 26 + t * 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFC2410C)
                                    .withValues(alpha: (1 - t) * 0.28),
                              ),
                            ),
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: const Color(0xFF0B1B34),
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 3),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 10)
                                ],
                              ),
                              child: const Icon(Icons.my_location_rounded,
                                  color: Color(0xFFFDE68A), size: 16),
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
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_myCityLabel.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(Icons.near_me_rounded,
                              size: 14, color: Color(0xFFB45309)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _myCityLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0B1B34),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    Row(
                      children: [
                        const Icon(Icons.radar_rounded,
                            size: 18, color: Color(0xFF0B1B34)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: _distanceColor(_radiusKm)
                                .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _hasExactUserPosition ? '${_radiusKm.round()} km' : 'National',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                                color: _distanceColor(_radiusKm)),
                          ),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: const SliderThemeData(
                              trackHeight: 3,
                              overlayShape: RoundSliderOverlayShape(
                                  overlayRadius: 14),
                            ),
                            child: Slider(
                              value: _radiusKm,
                              min: 5,
                              max: 100,
                              divisions: 19,
                              activeColor: const Color(0xFF0B1B34),
                              onChanged: (v) => setState(() => _radiusKm = v),
                              onChangeEnd: (_) => _loadProviders(),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0B1B34),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_visibleProviders.length}',
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    // ── Filtre par catégorie ──
                    if (_categories.isNotEmpty) ...[
                      const Divider(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.category_rounded,
                              size: 17, color: Color(0xFFB45309)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String?>(
                                isExpanded: true,
                                isDense: true,
                                value: _selectedCategory,
                                hint: const Text('Toutes les catégories',
                                    style: TextStyle(fontSize: 13)),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Toutes les catégories',
                                        style: TextStyle(fontSize: 13)),
                                  ),
                                  ..._categories.map(
                                    (c) => DropdownMenuItem<String?>(
                                      value: c,
                                      child: Text(c,
                                          style: const TextStyle(fontSize: 13),
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                  ),
                                ],
                                onChanged: (v) => setState(() {
                                  _selectedCategory = v;
                                  _selected = null;
                                }),
                              ),
                            ),
                          ),
                          if (_selectedCategory != null)
                            InkWell(
                              onTap: () =>
                                  setState(() => _selectedCategory = null),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.close_rounded, size: 16),
                              ),
                            ),
                        ],
                      ),
                    ],
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
                            Row(
                              children: [
                                Flexible(
                                  child: Text(_selected!.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                ),
                                if (_selected!.premiumBadge.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _selected!.premiumTier == 'gold'
                                          ? const Color(0xFFB45309)
                                          : const Color(0xFF0E3B2E),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _selected!.premiumBadge,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              '${_selected!.category.isNotEmpty ? '${_selected!.category} · ' : ''}${_selected!.city}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
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
                      BabifixButton(
                        label: 'Réserver',
                        width: 112,
                        height: 42,
                        onPressed: () => Navigator.of(context).push<void>(
                          babifixRoute(
                            (_) => ProviderProfilePremiumScreen(
                              providerId: _selected!.id,
                            ),
                          ),
                        ),
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

/// Pin goutte Direction 3 : anneau palier / proximite + etoile Gold.
class _TeardropPin extends StatelessWidget {
  const _TeardropPin({
    required this.color,
    required this.photoUrl,
    this.isGold = false,
  });
  final Color color;
  final String photoUrl;
  final bool isGold;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isGold ? const Color(0xFFFDE68A) : Colors.white,
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 8,
                    color: color.withValues(alpha: 0.42),
                    offset: const Offset(0, 3),
                  ),
                  const BoxShadow(blurRadius: 4, color: Colors.black26),
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
            Transform.translate(
              offset: const Offset(0, -2),
              child: CustomPaint(size: const Size(14, 9), painter: _PinTip(color)),
            ),
          ],
        ),
        if (isGold)
          Positioned(
            top: -3,
            right: -3,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: const Color(0xFFB45309),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(Icons.star_rounded, color: Color(0xFFFDE68A), size: 10),
            ),
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
