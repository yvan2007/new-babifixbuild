import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../babifix_design_system.dart';

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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Autorisez la localisation pour utiliser votre position.')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de récupérer la position.')),
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
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: widget.marker,
                initialZoom: 15,
                onTap: (_, point) => widget.onMarkerMoved(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.babifix.client',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: widget.marker,
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.location_on_rounded,
                        size: 44,
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
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _loadingGps ? null : _useMyPosition,
                icon: _loadingGps
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: BabifixDesign.cyan,
                        ),
                      )
                    : const Icon(Icons.my_location_rounded, size: 20),
                label: Text(_loadingGps ? 'Localisation…' : 'Ma position'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Touchez la carte pour ajuster le pin, ou utilisez la recherche d’adresse au-dessus / « Ma position ».',
          style: TextStyle(
            fontSize: 12,
            color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
            height: 1.3,
          ),
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
