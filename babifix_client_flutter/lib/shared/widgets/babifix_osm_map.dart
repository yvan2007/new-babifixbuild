import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../babifix_design_system.dart';
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
        _mapController.move(widget.marker, _mapController.camera.zoom);
      });
    }
  }

  Future<void> _useMyPosition() async {
    setState(() => _loadingGps = true);
    try {
      final perm = await Permission.locationWhenInUse.request();
      if (!perm.isGranted && !perm.isLimited) {
        if (mounted) {
          showBabifixToast(
        context,
        type: BabifixToastType.info,
        message: 'Autorisez la localisation pour utiliser votre position.',
      );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final p = LatLng(pos.latitude, pos.longitude);
      widget.onMarkerMoved(p);
      _mapController.move(p, 16);
    } catch (_) {
      if (mounted) {
        showBabifixToast(
        context,
        type: BabifixToastType.error,
        message: 'Impossible de récupérer la position.',
      );
      }
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
                    onTap: (_, point) => widget.onMarkerMoved(point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
                      '© OpenStreetMap',
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
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
