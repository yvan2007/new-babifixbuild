import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Indicateur de chargement geometrique BABIFIX.
/// Double anneau orbital concentrique avec arcs effiles et rotation fluide
/// (respecte l'accessibilite `disableAnimations` et conserve les constructeurs nommes).
class BabifixRingLoader extends StatefulWidget {
  final double size;
  final Color colorA;
  final Color colorB;
  final Color colorC;
  final Color colorD;
  final Duration duration;

  const BabifixRingLoader({
    super.key,
    this.size = 56,
    this.colorA = const Color(0xFF4CC9F0),
    this.colorB = const Color(0xFFE87722),
    this.colorC = const Color(0xFF0B1B34),
    this.colorD = const Color(0xFF22A6D6),
    this.duration = const Duration(milliseconds: 1150),
  });

  const BabifixRingLoader.cyan({super.key, this.size = 56})
      : colorA = const Color(0xFF4CC9F0),
        colorB = const Color(0xFF0284C7),
        colorC = const Color(0xFF0B1B34),
        colorD = const Color(0xFF4CC9F0),
        duration = const Duration(milliseconds: 1150);

  const BabifixRingLoader.orange({super.key, this.size = 56})
      : colorA = const Color(0xFFE87722),
        colorB = const Color(0xFFF59E0B),
        colorC = const Color(0xFF0B1B34),
        colorD = const Color(0xFFE87722),
        duration = const Duration(milliseconds: 1150);

  const BabifixRingLoader.dark({super.key, this.size = 56})
      : colorA = const Color(0xFF0B1B34),
        colorB = const Color(0xFFE87722),
        colorC = const Color(0xFF64748B),
        colorD = const Color(0xFF0B1B34),
        duration = const Duration(milliseconds: 1150);

  const BabifixRingLoader.mono({
    super.key,
    this.size = 56,
    Color color = const Color(0xFF4CC9F0),
  })  : colorA = color,
        colorB = color,
        colorC = color,
        colorD = color,
        duration = const Duration(milliseconds: 1150);

  const BabifixRingLoader.white({super.key, this.size = 56})
      : colorA = const Color(0xFFFFFFFF),
        colorB = const Color(0xCCFFFFFF),
        colorC = const Color(0x66FFFFFF),
        colorD = const Color(0xFFFFFFFF),
        duration = const Duration(milliseconds: 1150);

  @override
  State<BabifixRingLoader> createState() => _BabifixRingLoaderState();
}

class _BabifixRingLoaderState extends State<BabifixRingLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: reduce
            ? CustomPaint(
                painter: _OrbitalPainter(
                  t: 0.25,
                  primary: widget.colorA,
                  secondary: widget.colorB,
                  track: widget.colorC,
                ),
              )
            : AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) => CustomPaint(
                  painter: _OrbitalPainter(
                    t: _ctrl.value,
                    primary: widget.colorA,
                    secondary: widget.colorB,
                    track: widget.colorC,
                  ),
                ),
              ),
      ),
    );
  }
}

class _OrbitalPainter extends CustomPainter {
  const _OrbitalPainter({
    required this.t,
    required this.primary,
    required this.secondary,
    required this.track,
  });

  final double t;
  final Color primary;
  final Color secondary;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = size.width * 0.41;
    final innerR = size.width * 0.26;
    final strokeOuter = (size.width * 0.09).clamp(1.8, 5.0);
    final strokeInner = (size.width * 0.065).clamp(1.4, 3.6);

    canvas.drawCircle(
      center,
      outerR,
      Paint()
        ..color = track.withValues(alpha: 0.14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeOuter,
    );

    final angle1 = t * math.pi * 2;
    final sweep1 = math.pi * (0.72 + 0.28 * math.sin(t * math.pi * 2));
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outerR),
      angle1,
      sweep1,
      false,
      Paint()
        ..color = primary
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeOuter,
    );

    if (size.width >= 22) {
      final angle2 = -t * math.pi * 2 * 1.35 + math.pi * 0.5;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: innerR),
        angle2,
        math.pi * 0.65,
        false,
        Paint()
          ..color = secondary.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = strokeInner,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitalPainter old) =>
      old.t != t || old.primary != primary || old.secondary != secondary;
}
