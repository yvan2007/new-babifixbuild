import 'package:flutter/material.dart';

import '../../babifix_design_system.dart';

/// Chip distance pro animé avec petit radar pulsant.
///
/// Réutilisable partout où la distance client → prestataire est affichée
/// (cartes accueil, cartes Services/Catégories, profil prestataire).
///
/// Couleur teintée selon la distance pour un retour visuel immédiat :
///  • ≤ 5 km  → vert (très proche)
///  • ≤ 15 km → cyan BABIFIX (proche)
///  • ≤ 30 km → orange (modéré)
///  • > 30 km → rouge (loin)
class BabifixDistanceChip extends StatefulWidget {
  const BabifixDistanceChip({
    super.key,
    required this.distanceKm,
    this.compact = false,
  });

  /// Distance en kilomètres.
  final double distanceKm;

  /// Mode compact : plus petit (pour les cartes denses comme l'accueil).
  final bool compact;

  @override
  State<BabifixDistanceChip> createState() => _BabifixDistanceChipState();
}

class _BabifixDistanceChipState extends State<BabifixDistanceChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Color get _color {
    final d = widget.distanceKm;
    if (d <= 5) return const Color(0xFF22C55E);
    if (d <= 15) return BabifixDesign.cyan;
    if (d <= 30) return const Color(0xFFEA580C);
    return const Color(0xFFDC2626);
  }

  String get _label {
    final d = widget.distanceKm;
    if (d < 1.0) return '${(d * 1000).round()} m';
    return '${d.toStringAsFixed(d < 10 ? 1 : 0)} km';
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    final compact = widget.compact;
    final dotSize = compact ? 12.0 : 16.0;
    final fontSize = compact ? 10.5 : 12.5;
    final padH = compact ? 7.0 : 10.0;
    final padV = compact ? 3.0 : 5.0;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Radar pulsant à gauche
          SizedBox(
            width: dotSize,
            height: dotSize,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) {
                final t = _pulse.value;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: dotSize * (0.5 + 0.5 * t),
                      height: dotSize * (0.5 + 0.5 * t),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.35 * (1 - t)),
                      ),
                    ),
                    Container(
                      width: dotSize * 0.45,
                      height: dotSize * 0.45,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.6),
                            blurRadius: 5,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          SizedBox(width: compact ? 5 : 7),
          Text(
            _label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}
