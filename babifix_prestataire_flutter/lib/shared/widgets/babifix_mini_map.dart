import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Mini-carte moderne réutilisable (même rendu que l'app client) :
/// fond CartoDB Voyager en HD/Retina + pin « goutte » sur le point.
/// Légèrement interactive (zoom/déplacement) mais compacte.
class BabifixMiniMap extends StatelessWidget {
  const BabifixMiniMap({
    super.key,
    required this.lat,
    required this.lon,
    this.height = 180,
    this.pinColor = const Color(0xFF4CC9F0),
    this.pinIcon = Icons.location_on_rounded,
    this.zoom = 15,
    this.interactive = true,
  });

  final double lat;
  final double lon;
  final double height;
  final Color pinColor;
  final IconData pinIcon;
  final double zoom;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(lat, lon);
    // Mode sombre : si le téléphone est en thème sombre → fond CartoDB Dark
    // Matter ; sinon Voyager clair. {r} = tuiles HD/Retina.
    final dark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final tilesUrl = dark
        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
        : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: point,
            initialZoom: zoom,
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
              subdomains: const ['a', 'b', 'c', 'd'],
              retinaMode: RetinaMode.isHighDensity(context),
              tileProvider: NetworkTileProvider(),
              userAgentPackageName: 'app.babifix.prestataire',
            ),
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
