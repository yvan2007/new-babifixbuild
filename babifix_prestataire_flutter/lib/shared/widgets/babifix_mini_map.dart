import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Mini-carte moderne réutilisable :
/// fond OpenStreetMap haute lisibilité + pin « goutte » centré sur la commune.
/// Se recentre automatiquement dès que les coordonnées changent.
class BabifixMiniMap extends StatelessWidget {
  const BabifixMiniMap({
    super.key,
    required this.lat,
    required this.lon,
    this.height = 180,
    this.pinColor = const Color(0xFF0B1B34),
    this.pinIcon = Icons.location_on_rounded,
    this.zoom = 15,
    this.interactive = true,
    this.isApproximate = false,
    this.onTap,
  });

  final double lat;
  final double lon;
  final double height;
  final Color pinColor;
  final IconData pinIcon;
  final double zoom;
  final bool interactive;
  final bool isApproximate;
  final ValueChanged<LatLng>? onTap;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(lat, lon);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tilesUrl = isDark
        ? 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}'
        : 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}';
    final effectiveZoom = isApproximate ? (zoom > 13.5 ? 13.5 : zoom) : zoom;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          key: ValueKey('map_${lat.toStringAsFixed(5)}_${lon.toStringAsFixed(5)}_$isApproximate'),
          options: MapOptions(
            initialCenter: point,
            initialZoom: effectiveZoom,
            onTap: onTap != null ? (_, p) => onTap!(p) : null,
            interactionOptions: InteractionOptions(
              flags: interactive
                  ? (InteractiveFlag.pinchZoom |
                      InteractiveFlag.drag |
                      InteractiveFlag.doubleTapZoom)
                  : InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: tilesUrl,
              tileProvider: NetworkTileProvider(),
              userAgentPackageName: 'ci.babifix.prestataire',
            ),
            if (isApproximate)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: point,
                    radius: 650,
                    useRadiusInMeter: true,
                    color: const Color(0xFFB45309).withValues(alpha: 0.16),
                    borderColor: const Color(0xFFB45309),
                    borderStrokeWidth: 2,
                  ),
                ],
              )
            else
              MarkerLayer(
                markers: [
                  Marker(
                    point: point,
                    width: 46,
                    height: 58,
                    alignment: Alignment.bottomCenter,
                    child: _Teardrop(color: pinColor, icon: pinIcon),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Teardrop extends StatelessWidget {
  const _Teardrop({required this.color, required this.icon});
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
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
          child: Icon(icon, color: Colors.white, size: 20),
        ),
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
