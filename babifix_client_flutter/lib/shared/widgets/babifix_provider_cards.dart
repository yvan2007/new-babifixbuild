import 'package:flutter/material.dart';

import '../../babifix_design_system.dart';

/// Style visuel equilibre selon l'abonnement du prestataire :
/// visible pour recompenser les abonnes Pro Silver / Pro Gold tout en
/// conservant une presentation digne et fiable pour les artisans Standard.
class BabifixTierVisual {
  const BabifixTierVisual({
    required this.borderColor,
    required this.borderWidth,
    required this.accentRailColor,
    required this.headerTint,
    required this.tierLabel,
  });

  final Color borderColor;
  final double borderWidth;
  final Color accentRailColor;
  final Color? headerTint;
  final String tierLabel;

  factory BabifixTierVisual.fromTier({
    required String tier,
    required bool isLight,
    bool disponible = true,
  }) {
    final norm = tier.trim().toLowerCase();
    if (!disponible) {
      return BabifixTierVisual(
        borderColor: isLight
            ? const Color(0x30DC2626)
            : const Color(0x30F87171),
        borderWidth: 1.1,
        accentRailColor: const Color(0xFFEF4444),
        headerTint: null,
        tierLabel: 'Indisponible',
      );
    }
    if (norm == 'gold') {
      return BabifixTierVisual(
        borderColor: const Color(0xFFD97706).withValues(alpha: 0.72),
        borderWidth: 1.6,
        accentRailColor: const Color(0xFFD97706),
        headerTint: isLight
            ? const Color(0xFFFFFBEB)
            : const Color(0xFF451A03).withValues(alpha: 0.25),
        tierLabel: 'ELITE OR',
      );
    }
    if (norm == 'silver') {
      return BabifixTierVisual(
        borderColor: const Color(0xFF0284C7).withValues(alpha: 0.60),
        borderWidth: 1.4,
        accentRailColor: const Color(0xFF0284C7),
        headerTint: isLight
            ? const Color(0xFFF0F9FF)
            : const Color(0xFF0C4A6E).withValues(alpha: 0.25),
        tierLabel: 'PRO SILVER',
      );
    }
    return BabifixTierVisual(
      borderColor: isLight
          ? const Color(0x180F172A)
          : const Color(0x18FFFFFF),
      borderWidth: 1.0,
      accentRailColor: BabifixDesign.ciGreen,
      headerTint: null,
      tierLabel: 'VERIFIE',
    );
  }
}

/// Badge compact d'abonnement / statut sans stigmatisation du Standard.
class BabifixTierBadge extends StatelessWidget {
  const BabifixTierBadge({
    super.key,
    required this.tier,
    this.customLabel = '',
    this.isLight = true,
    this.compact = false,
  });

  final String tier;
  final String customLabel;
  final bool isLight;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final norm = tier.trim().toLowerCase();
    final isGold = norm == 'gold';
    final isSilver = norm == 'silver';

    final Color bg;
    final Color fg;
    final IconData icon;
    final String text;

    if (isGold) {
      bg = const Color(0xFFB45309);
      fg = Colors.white;
      icon = Icons.workspace_premium_rounded;
      text = customLabel.isNotEmpty ? customLabel.toUpperCase() : 'ELITE OR';
    } else if (isSilver) {
      bg = const Color(0xFF0369A1);
      fg = Colors.white;
      icon = Icons.verified_rounded;
      text = customLabel.isNotEmpty ? customLabel.toUpperCase() : 'PRO SILVER';
    } else {
      bg = isLight
          ? const Color(0xFFDCFCE7)
          : const Color(0xFF14532D).withValues(alpha: 0.55);
      fg = isLight ? const Color(0xFF166534) : const Color(0xFF86EFAC);
      icon = Icons.check_circle_rounded;
      text = 'Artisan Verifie';
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 2.5 : 3.5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 11 : 12, color: fg),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: compact ? 9.5 : 10.5,
              fontWeight: FontWeight.w800,
              color: fg,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge "Casier verifie" pour les metiers sensibles (nounous, aide domicile, chauffeurs).
class BabifixCasierBadge extends StatelessWidget {
  const BabifixCasierBadge({
    super.key,
    this.isLight = true,
    this.compact = false,
  });

  final bool isLight;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bg = isLight
        ? const Color(0xFFCCFBF1)
        : const Color(0xFF134E4A).withValues(alpha: 0.65);
    final fg = isLight ? const Color(0xFF0F766E) : const Color(0xFF5EEAD4);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 2.5 : 3.5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.policy_rounded, size: compact ? 11 : 12, color: fg),
          const SizedBox(width: 4),
          Text(
            'Casier verifie',
            style: TextStyle(
              fontSize: compact ? 9.5 : 10.5,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
