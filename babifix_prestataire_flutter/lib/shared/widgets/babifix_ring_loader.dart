/// BabifixRingLoader — Loader animé inspiré du composant Uiverse "4 rings".
///
/// 4 anneaux choregraphiés (gros / petit centre / gauche / droite) qui se
/// tracent, voyagent et disparaissent en boucle, avec un décalage de
/// phase pour donner un effet d'orchestration fluide. Port pixel-perfect
/// du keyframes CSS d'origine, mais adapté au système de couleurs BABIFIX.
///
/// Usage :
///   const BabifixRingLoader()                  // 80 px, palette cyan
///   const BabifixRingLoader.cyan(size: 56)
///   const BabifixRingLoader.orange(size: 96)
///   const BabifixRingLoader.mono(color: Colors.white)
///
/// Sur fond sombre : utilise les variantes lumineuses (cyan/orange).
/// Sur fond clair : utilise `BabifixRingLoader.dark()`.
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
    this.size = 80,
    this.colorA = const Color(0xFF4CC9F0),
    this.colorB = const Color(0xFFFFFFFF),
    this.colorC = const Color(0xFF7DD3FC),
    this.colorD = const Color(0xFF4CC9F0),
    this.duration = const Duration(milliseconds: 2000),
  });

  /// Palette cyan/blanc — pour fond navy (app client)
  const BabifixRingLoader.cyan({super.key, this.size = 80})
      : colorA = const Color(0xFF4CC9F0),
        colorB = const Color(0xFFFFFFFF),
        colorC = const Color(0xFF7DD3FC),
        colorD = const Color(0xFF4CC9F0),
        duration = const Duration(milliseconds: 2000);

  /// Palette orange CI — pour fond chaud (app prestataire)
  const BabifixRingLoader.orange({super.key, this.size = 80})
      : colorA = const Color(0xFFE87722),
        colorB = const Color(0xFFFFFFFF),
        colorC = const Color(0xFFFFA94D),
        colorD = const Color(0xFFE87722),
        duration = const Duration(milliseconds: 2000);

  /// Palette navy/cyan — pour fond clair (écrans intérieurs apps)
  const BabifixRingLoader.dark({super.key, this.size = 64})
      : colorA = const Color(0xFF0B1B34),
        colorB = const Color(0xFF4CC9F0),
        colorC = const Color(0xFF1E40AF),
        colorD = const Color(0xFF0B1B34),
        duration = const Duration(milliseconds: 2000);

  /// Loader monochrome (fond contrasté, n'importe quelle couleur)
  const BabifixRingLoader.mono({
    super.key,
    this.size = 64,
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

/// Painter qui rend les 4 anneaux choregraphiés.
///
/// Les keyframes CSS ont été distillées en 3 phases logiques par anneau :
///   - grow      : l'arc apparaît, longueur 0 → max, largeur 20 → 30
///   - travel    : l'arc maintient sa longueur et avance sur le périmètre
///   - shrink    : l'arc disparaît, longueur max → 0
///
/// Chaque anneau effectue 2 passages par cycle, séparés par des pauses.
/// Les phases (offsets) entre A, B, C, D sont différents → effet de
/// vague visuelle.
class _RingsPainter extends CustomPainter {
  final double t; // 0 → 1
  final Color colorA, colorB, colorC, colorD;

  _RingsPainter({
    required this.t,
    required this.colorA,
    required this.colorB,
    required this.colorC,
    required this.colorD,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Coordonnées du viewBox SVG original (240×240).
    // On scale pour que ça remplisse la taille demandée.
    final scale = size.width / 240.0;
    canvas.save();
    canvas.scale(scale, scale);

    // Anneau A : gros cercle extérieur, centré
    _drawRing(
      canvas,
      cx: 120, cy: 120, r: 105,
      phase: 0.0, // commence à 4% du cycle
      color: colorA,
    );

    // Anneau B : petit cercle central, démarre +8%
    _drawRing(
      canvas,
      cx: 120, cy: 120, r: 35,
      phase: 0.08,
      color: colorB,
    );

    // Anneau C : cercle gauche, démarre -4% (en avance)
    _drawRing(
      canvas,
      cx: 85, cy: 120, r: 70,
      phase: -0.04,
      color: colorC,
    );

    // Anneau D : cercle droit, démarre +4%
    _drawRing(
      canvas,
      cx: 155, cy: 120, r: 70,
      phase: 0.04,
      color: colorD,
    );

    canvas.restore();
  }

  void _drawRing(
    Canvas canvas, {
    required double cx,
    required double cy,
    required double r,
    required double phase,
    required Color color,
  }) {
    // Décale le temps de la phase, mod 1
    final tt = ((t - phase) % 1.0 + 1.0) % 1.0;

    // Chaque cycle contient 2 passes :
    //   pass 1 : 0.04 → 0.40 (durée 0.36)
    //   pause  : 0.40 → 0.50 (durée 0.10)
    //   pass 2 : 0.50 → 0.86 (durée 0.36)
    //   pause  : 0.86 → 1.04 (durée 0.14)
    double passT;
    double startBase;

    if (tt >= 0.04 && tt < 0.40) {
      passT = (tt - 0.04) / 0.36;
      startBase = 0.0; // pass 1 démarre à 0 rad
    } else if (tt >= 0.50 && tt < 0.86) {
      passT = (tt - 0.50) / 0.36;
      startBase = math.pi; // pass 2 démarre à l'opposé
    } else {
      return; // pause : rien à dessiner
    }

    // Phase à l'intérieur du pass :
    //   grow   : 0 → 0.22 (longueur d'arc et width grandissent)
    //   travel : 0.22 → 0.78 (longueur max, l'arc avance)
    //   shrink : 0.78 → 1.00 (longueur et width diminuent)
    const maxSweep = math.pi / 2.7; // ~67° — équivalent visuel des "60 units"
    const minWidth = 20.0;
    const maxWidth = 30.0;

    double sweep;
    double width;

    if (passT < 0.22) {
      // grow
      final p = passT / 0.22;
      sweep = maxSweep * p;
      width = minWidth + (maxWidth - minWidth) * p;
    } else if (passT > 0.78) {
      // shrink
      final p = (1.0 - passT) / 0.22;
      sweep = maxSweep * p;
      width = minWidth + (maxWidth - minWidth) * p;
    } else {
      sweep = maxSweep;
      width = maxWidth;
    }

    // Arc start angle : voyage sur 1.5π de rotation au total
    // (équivalent visuel du déplacement de 260 unités sur le périmètre)
    final startAngle = startBase + passT * (math.pi * 1.5) - math.pi / 2;

    if (sweep <= 0) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width;

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
