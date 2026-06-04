import 'package:flutter/material.dart';

/// Bannière d'échec de paiement — entrée animée (fade + glissement) avec une
/// icône qui pulse en boucle. Conserve le bouton de fermeture pour permettre
/// au client de réessayer (cas typique : solde Mobile Money insuffisant).
///
/// Pensée pour rester visuellement cohérente avec l'animation de succès
/// (cercle vert élastique) : même langage premium, ton rouge pour l'erreur.
class BabifixPaymentErrorBanner extends StatefulWidget {
  const BabifixPaymentErrorBanner({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  State<BabifixPaymentErrorBanner> createState() =>
      _BabifixPaymentErrorBannerState();
}

class _BabifixPaymentErrorBannerState extends State<BabifixPaymentErrorBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFDC2626);
    // Entrée animée : fade + léger glissement vers le bas.
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * -10), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFCA5A5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icône qui pulse doucement pour attirer l'attention sans agresser.
            ScaleTransition(
              scale: Tween(begin: 0.85, end: 1.1).animate(
                CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
              ),
              child: const Icon(Icons.error_outline_rounded, color: red, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.message,
                style: const TextStyle(color: red, fontSize: 13, height: 1.4),
              ),
            ),
            GestureDetector(
              onTap: widget.onDismiss,
              child: const Icon(Icons.close_rounded, size: 18, color: red),
            ),
          ],
        ),
      ),
    );
  }
}
