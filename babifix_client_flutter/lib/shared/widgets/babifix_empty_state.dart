import 'package:flutter/material.dart';
import '../../babifix_design_system.dart';

/// Widget état vide réutilisable sur tous les écrans BABIFIX.
class BabifixEmptyState extends StatelessWidget {
  const BabifixEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.ctaLabel,
    this.onCta,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;
    final color = iconColor ?? BabifixDesign.cyan;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.10),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Icon(icon, color: color, size: 42),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            if (ctaLabel != null && onCta != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onCta,
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: Text(ctaLabel!),
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: isLight ? BabifixDesign.navy : Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
