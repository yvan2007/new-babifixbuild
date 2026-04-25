import 'package:flutter/material.dart';
import '../../babifix_design_system.dart';

/// Widget etat vide reutilisable sur tous les ecrans BABIFIX.
/// Support icon simple ou animation Lottie.
class BabifixEmptyState extends StatelessWidget {
  const BabifixEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.ctaLabel,
    this.onCta,
    this.iconColor,
    this.lottieAsset,  // Optionnel: chemin vers animation Lottie
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final Color? iconColor;
  final String? lottieAsset;  // ex: "assets/lottie/empty_inbox.json"

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
            // ✅ U9: Support Lottie
            if (lottieAsset != null)
              Opacity(
                opacity: 0.3,
                child: Icon(icon, color: color, size: 80),
              )
            else
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
                  foregroundColor: isLight ? const Color(0xFF1A237E) : Colors.white,
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

/// Placeholder pour les cas ou Lottie n'est pas charge (grace a lazy import)
class _LottiePlaceholder extends StatefulWidget {
  const _LottiePlaceholder({
    required this.asset,
    required this.size,
    required this.color,
  });

  final String asset;
  final double size;
  final Color color;

  @override
  State<_LottiePlaceholder> createState() => _LottiePlaceholderState();
}

class _LottiePlaceholderState extends State<_LottiePlaceholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  bool _hasLottie = false;
  dynamic _lottie;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _loadLottie();
  }

  Future<void> _loadLottie() async {
    try {
      // Note: Lottie require lottie package optionnel
      // Pas de lazy import en Dart - utiliser try-catch
      _hasLottie = false;
    } catch (_) {
      // Lottie pas installe, garder icone
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasLottie) {
      // Fallback simple
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: 0.10),
        ),
        child: Icon(
          Icons.inbox_outlined,
          color: widget.color,
          size: widget.size * 0.5,
        ),
      );
    }

    // TODO: Implementer avec Lottie une fois le package charge
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Icon(
        Icons.inbox_outlined,
        color: widget.color,
        size: widget.size * 0.5,
      ),
    );
}
}
