import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../babifix_design_system.dart';
import '../services/smart_gps.dart';
import 'babifix_ring_loader.dart';
import 'babifix_snackbar.dart';

/// Carte OpenStreetMap — point d’intervention (tap pour placer le marqueur).
class BabifixOsmLocationPicker extends StatefulWidget {
  const BabifixOsmLocationPicker({
    super.key,
    required this.marker,
    required this.onMarkerMoved,
    this.height = 200,
  });

  final LatLng marker;
  final ValueChanged<LatLng> onMarkerMoved;
  final double height;

  /// Abidjan par défaut (Côte d’Ivoire)
  static LatLng get defaultCenter => const LatLng(5.36, -4.0083);

  @override
  State<BabifixOsmLocationPicker> createState() => _BabifixOsmLocationPickerState();
}

class _BabifixOsmLocationPickerState extends State<BabifixOsmLocationPicker> {
  final MapController _mapController = MapController();
  bool _loadingGps = false;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant BabifixOsmLocationPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.marker.latitude != widget.marker.latitude ||
        oldWidget.marker.longitude != widget.marker.longitude) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          final z = _mapController.camera.zoom;
          _mapController.move(widget.marker, z > 0 ? z : 15);
        } catch (_) {}
      });
    }
  }

  Future<void> _useMyPosition() async {
    setState(() => _loadingGps = true);
    try {
      final gps = await acquireSmartGps(forceFresh: true);
      if (!mounted) return;
      if (gps.hasHardError) {
        showBabifixToast(
          context,
          type: BabifixToastType.info,
          message: gps.friendlyMessage ??
              'Autorisez la localisation pour utiliser votre position.',
        );
        return;
      }
      if (gps.ok) {
        final p = gps.position!;
        widget.onMarkerMoved(p);
        _mapController.move(p, gps.inCoteIvoire ? 16 : 14);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: widget.height,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: widget.marker,
                    initialZoom: 15,
                    backgroundColor:
                        isLight ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                    onTap: (_, point) => widget.onMarkerMoved(point),
                  ),
                  children: [
                    TileLayer(
                      // CartoDB HD + mode sombre auto (Dark Matter si téléphone
                      // en thème sombre), sinon Voyager clair. {r} = Retina/HD.
                      urlTemplate: MediaQuery.platformBrightnessOf(context) ==
                              Brightness.dark
                          ? 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}'
                          : 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
                                            retinaMode: false,
                      userAgentPackageName: 'com.babifix.client',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: widget.marker,
                          width: 60,
                          height: 60,
                          alignment: Alignment.topCenter,
                          child: _PinWithHalo(),
                        ),
                      ],
                    ),
                  ],
                ),
                // Bouton « Ma position » flottant sur la carte
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Material(
                    color: Colors.white,
                    elevation: 4,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _loadingGps ? null : _useMyPosition,
                      child: Padding(
                        padding: const EdgeInsets.all(11),
                        child: _loadingGps
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: BabifixRingLoader.cyan(size: 30),
                              )
                            : const Icon(
                                Icons.my_location_rounded,
                                size: 22,
                                color: Color(0xFF1D4ED8),
                              ),
                      ),
                    ),
                  ),
                ),
                // Attribution OSM (obligatoire) — discrète
                Positioned(
                  left: 8,
                  bottom: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '© ESRI · ArcGIS',
                      style: TextStyle(fontSize: 9, color: Color(0xFF475569)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.touch_app_rounded,
                size: 15,
                color: isLight
                    ? const Color(0xFF64748B)
                    : const Color(0xFF94A3B8)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Touchez la carte pour placer le point, ou utilisez « Ma position ».',
                style: TextStyle(
                  fontSize: 12,
                  color: isLight
                      ? const Color(0xFF64748B)
                      : const Color(0xFF94A3B8),
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Marqueur stylé : halo + pin orange BABIFIX.
class _PinWithHalo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Positioned(
          top: 8,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: BabifixDesign.ciOrange.withValues(alpha: 0.20),
            ),
          ),
        ),
        const Icon(
          Icons.location_on_rounded,
          size: 44,
          color: BabifixDesign.ciOrange,
          shadows: [
            Shadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
      ],
    );
  }
}

/// Carte OSM en lecture seule (lieu de la prestation dans l’avis, etc.).
class BabifixOsmStaticPreview extends StatelessWidget {
  const BabifixOsmStaticPreview({
    super.key,
    required this.center,
    this.height = 132,
    this.borderRadius = 18,
  });

  final LatLng center;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: 15,
            backgroundColor: const Color(0xFFF1F5F9),
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            TileLayer(
              urlTemplate: MediaQuery.platformBrightnessOf(context) ==
                      Brightness.dark
                  ? 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}'
                  : 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
                            retinaMode: false,
              userAgentPackageName: 'com.babifix.client',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: center,
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.location_on_rounded,
                    size: 40,
                    color: BabifixDesign.ciOrange,
                    shadows: const [
                      Shadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
