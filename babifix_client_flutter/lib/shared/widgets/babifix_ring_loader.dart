/// BabifixRingLoader — Port pixel-perfect du loader Uiverse "4 rings".
///
/// Géométrie identique au SVG original (viewBox 240×240) :
///   • Ring A : cx=120, cy=120, r=105 (gros anneau extérieur)
///   • Ring B : cx=120, cy=120, r=35  (petit anneau central)
///   • Ring C : cx=85,  cy=120, r=70  (anneau gauche)
///   • Ring D : cx=155, cy=120, r=70  (anneau droit)
///
/// Les rings C et D **traversent** A par leur côté — c'est le design
/// voulu (effet d'entrelacement orchestré, pas un bug).
///
/// Animations : ringA/B/C/D portées 1-to-1 depuis les keyframes CSS.
/// Chaque anneau effectue 2 passes par cycle (grow → travel → shrink),
/// stroke-width oscille 20 → 30 → 20, le tout déphasé entre A/B/C/D.
///
/// Couleurs : adaptées au cyan BABIFIX (au lieu de rouge/orange/bleu/rose).
///
/// Usage :
///   const BabifixRingLoader()                  // 56 px, palette cyan
///   const BabifixRingLoader.cyan(size: 80)
///   const BabifixRingLoader.dark(size: 64)     // sur fond clair
///   const BabifixRingLoader.mono(color: Colors.white)
import 'dart:math' as math;

import 'package:flutter/material.dart';

class BabifixRingLoader extends StatefulWidget {
  final double size;
  final Color colorA; // gros anneau extérieur
  final Color colorB; // petit anneau central
  final Color colorC; // anneau gauche
  final Color colorD; // anneau droit
  final Duration duration;

  const BabifixRingLoader({
    super.key,
    this.size = 56,
    this.colorA = const Color(0xFF4CC9F0), // cyan signature
    this.colorB = const Color(0xFF7DD3FC), // cyan clair
    this.colorC = const Color(0xFF0B1B34), // navy profond
    this.colorD = const Color(0xFF22A6D6), // cyan foncé
    this.duration = const Duration(milliseconds: 2000),
  });

  /// Palette couleurs principales BABIFIX — cyan + navy uniquement.
  const BabifixRingLoader.cyan({super.key, this.size = 56})
      : colorA = const Color(0xFF4CC9F0),
        colorB = const Color(0xFF7DD3FC),
        colorC = const Color(0xFF0B1B34),
        colorD = const Color(0xFF22A6D6),
        duration = const Duration(milliseconds: 2000);

  /// Palette orange CI — pour fond chaud (app prestataire).
  const BabifixRingLoader.orange({super.key, this.size = 56})
      : colorA = const Color(0xFFE87722),
        colorB = const Color(0xFFFFA94D),
        colorC = const Color(0xFF0B1B34),
        colorD = const Color(0xFFB8551B),
        duration = const Duration(milliseconds: 2000);

  /// Palette navy/cyan — pour fond clair.
  const BabifixRingLoader.dark({super.key, this.size = 56})
      : colorA = const Color(0xFF0B1B34),
        colorB = const Color(0xFF4CC9F0),
        colorC = const Color(0xFF1E40AF),
        colorD = const Color(0xFF22A6D6),
        duration = const Duration(milliseconds: 2000);

  /// Loader monochrome.
  const BabifixRingLoader.mono({
    super.key,
    this.size = 56,
    Color color = const Color(0xFF4CC9F0),
  })  : colorA = color,
        colorB = color,
        colorC = color,
        colorD = color,
        duration = const Duration(milliseconds: 2000);

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
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          painter: _RingsPainter(
            t: _ctrl.value,
            colorA: widget.colorA,
            colorB: widget.colorB,
            colorC: widget.colorC,
            colorD: widget.colorD,
          ),
        ),
      ),
    );
  }
}

/// Un keyframe : à `t`, on a la position `s` (longueur le long du
/// périmètre, en unités du viewBox), `dashLen` (longueur de l'arc
/// visible), `width` (épaisseur du stroke).
class _KF {
  final double t;
  final double s;
  final double dashLen;
  final double width;
  const _KF(this.t, this.s, this.dashLen, this.width);
}

/// Port direct des @keyframes ringA/B/C/D du CSS Uiverse.
class _RingsPainter extends CustomPainter {
  final double t; // 0..1
  final Color colorA, colorB, colorC, colorD;

  _RingsPainter({
    required this.t,
    required this.colorA,
    required this.colorB,
    required this.colorC,
    required this.colorD,
  });

  // ────────── KEYFRAMES (portés directement du CSS) ──────────
  //
  // s = -strokeDashoffset (CSS) → distance positive du début de la
  // dash depuis le point d'attaque (angle 0 = 3 h dans le SVG).

  static const List<_KF> _ringA = [
    _KF(0.00, 330, 0, 20),
    _KF(0.04, 330, 0, 20),
    _KF(0.12, 335, 60, 30),
    _KF(0.32, 595, 60, 30),
    _KF(0.40, 660, 0, 20),
    _KF(0.54, 660, 0, 20),
    _KF(0.62, 665, 60, 30),
    _KF(0.82, 925, 60, 30),
    _KF(0.90, 990, 0, 20),
    _KF(1.00, 990, 0, 20),
  ];

  static const List<_KF> _ringB = [
    _KF(0.00, 110, 0, 20),
    _KF(0.12, 110, 0, 20),
    _KF(0.20, 115, 20, 30),
    _KF(0.40, 195, 20, 30),
    _KF(0.48, 220, 0, 20),
    _KF(0.62, 220, 0, 20),
    _KF(0.70, 225, 20, 30),
    _KF(0.90, 305, 20, 30),
    _KF(0.98, 330, 0, 20),
    _KF(1.00, 330, 0, 20),
  ];

  static const List<_KF> _ringC = [
    _KF(0.00, 0, 0, 20),
    _KF(0.08, 5, 40, 30),
    _KF(0.28, 175, 40, 30),
    _KF(0.36, 220, 0, 20),
    _KF(0.58, 220, 0, 20),
    _KF(0.66, 225, 40, 30),
    _KF(0.86, 395, 40, 30),
    _KF(0.94, 440, 0, 20),
    _KF(1.00, 440, 0, 20),
  ];

  static const List<_KF> _ringD = [
    _KF(0.00, 0, 0, 20),
    _KF(0.08, 0, 0, 20),
    _KF(0.16, 5, 40, 30),
    _KF(0.36, 175, 40, 30),
    _KF(0.44, 220, 0, 20),
    _KF(0.50, 220, 0, 20),
    _KF(0.58, 225, 40, 30),
    _KF(0.78, 395, 40, 30),
    _KF(0.86, 440, 0, 20),
    _KF(1.00, 440, 0, 20),
  ];

  /// Interpole linéairement entre les keyframes pour le temps `t`.
  _KF _sample(List<_KF> kf, double t) {
    if (t <= kf.first.t) return kf.first;
    if (t >= kf.last.t) return kf.last;
    for (var i = 0; i < kf.length - 1; i++) {
      final a = kf[i];
      final b = kf[i + 1];
      if (t >= a.t && t <= b.t) {
        final dt = b.t - a.t;
        if (dt <= 0) return a;
        final p = (t - a.t) / dt;
        return _KF(
          t,
          a.s + (b.s - a.s) * p,
          a.dashLen + (b.dashLen - a.dashLen) * p,
          a.width + (b.width - a.width) * p,
        );
      }
    }
    return kf.last;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Le viewBox SVG est 240×240, on scale pour remplir la taille
    // demandée (homothétie centrée).
    final scale = size.width / 240.0;
    canvas.save();
    canvas.scale(scale, scale);

    // Ring A : cx=120, cy=120, r=105
    _drawRing(canvas, cx: 120, cy: 120, r: 105, color: colorA,
        kf: _sample(_ringA, t));

    // Ring B : cx=120, cy=120, r=35
    _drawRing(canvas, cx: 120, cy: 120, r: 35, color: colorB,
        kf: _sample(_ringB, t));

    // Ring C : cx=85, cy=120, r=70
    _drawRing(canvas, cx: 85, cy: 120, r: 70, color: colorC,
        kf: _sample(_ringC, t));

    // Ring D : cx=155, cy=120, r=70
    _drawRing(canvas, cx: 155, cy: 120, r: 70, color: colorD,
        kf: _sample(_ringD, t));

    canvas.restore();
  }

  void _drawRing(
    Canvas canvas, {
    required double cx,
    required double cy,
    required double r,
    required Color color,
    required _KF kf,
  }) {
    if (kf.dashLen <= 0 || r <= 0) return;

    // Périmètre du cercle (unités viewBox).
    final perim = 2 * math.pi * r;

    // s peut dépasser perim (les keyframes vont jusqu'à 990 alors que
    // la perimetre ≈ 659.7) — c'est intentionnel dans le CSS pour
    // simuler le wrap autour du cercle. On prend modulo.
    final sMod = kf.s % perim;
    final startAngle = (sMod / perim) * 2 * math.pi;
    final sweep = (kf.dashLen / perim) * 2 * math.pi;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = kf.width
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      startAngle,
      sweep,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingsPainter old) =>
      old.t != t ||
      old.colorA != colorA ||
      old.colorB != colorB ||
      old.colorC != colorC ||
      old.colorD != colorD;
}
