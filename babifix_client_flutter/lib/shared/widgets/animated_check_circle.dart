/// AnimatedCheckCircle — Cercle vert qui se dessine + check qui se trace.
///
/// Effet "success satisfaisant" : le cercle se ferme en 600 ms, puis le
/// check apparaît avec un bounce. Utilisé dans les dialogs de succès
/// (confirmation travaux, devis envoyé, paiement reçu…).
import 'dart:math';

import 'package:flutter/material.dart';

class AnimatedCheckCircle extends StatefulWidget {
  final double size;
  final Color color;
  final Duration duration;

  const AnimatedCheckCircle({
    super.key,
    this.size = 80,
    this.color = const Color(0xFF22C55E),
    this.duration = const Duration(milliseconds: 900),
  });

  @override
  State<AnimatedCheckCircle> createState() => _AnimatedCheckCircleState();
}

class _AnimatedCheckCircleState extends State<AnimatedCheckCircle>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        size: Size.square(widget.size),
        painter: _CheckPainter(
          progress: _ctrl.value,
          color: widget.color,
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  final double progress;
  final Color color;
  _CheckPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final ringP = (progress / 0.6).clamp(0.0, 1.0); // 0..0.6 = cercle
    final checkP = ((progress - 0.55) / 0.45).clamp(0.0, 1.0); // 0.55..1 = check

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;

    // Anneau de fond léger
    final bg = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bg);

    // Bord qui se ferme
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * ringP,
      false,
      ring,
    );

    // Check qui se trace — proportions d'une vraie coche « ✓ » :
    // petite descente à gauche, puis longue remontée vers la droite.
    if (checkP > 0) {
      final p1 = Offset(size.width * 0.30, size.height * 0.52);
      final p2 = Offset(size.width * 0.44, size.height * 0.66);
      final p3 = Offset(size.width * 0.72, size.height * 0.36);

      // Descente courte = 30 % du tracé, remontée longue = 70 %.
      final seg1 = (checkP / 0.30).clamp(0.0, 1.0);
      final seg2 = checkP <= 0.30 ? 0.0 : ((checkP - 0.30) / 0.70).clamp(0.0, 1.0);

      final pen = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.075
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      // Un seul Path continu (jointure nette au vertex).
      final path = Path()..moveTo(p1.dx, p1.dy);
      final mid1 = Offset.lerp(p1, p2, seg1)!;
      path.lineTo(mid1.dx, mid1.dy);
      if (seg2 > 0) {
        final mid2 = Offset.lerp(p2, p3, seg2)!;
        path.lineTo(mid2.dx, mid2.dy);
      }
      canvas.drawPath(path, pen);
    }
  }

  @override
  bool shouldRepaint(covariant _CheckPainter old) =>
      old.progress != progress || old.color != color;
}
