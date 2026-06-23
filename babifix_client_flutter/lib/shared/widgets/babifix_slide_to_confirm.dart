import 'package:flutter/material.dart';

/// Bouton « glisser pour confirmer » premium : un curseur rond qu'on fait
/// glisser de gauche à droite ; un remplissage coloré suit le doigt et l'action
/// se déclenche une fois le bout atteint. Bien plus pro qu'un Dismissible.
class BabifixSlideToConfirm extends StatefulWidget {
  const BabifixSlideToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.color = const Color(0xFF22C55E),
    this.icon = Icons.payments_rounded,
    this.confirmingLabel = 'Confirmation…',
    this.height = 60,
  });

  final String label;
  final String confirmingLabel;
  final Future<void> Function() onConfirmed;
  final Color color;
  final IconData icon;
  final double height;

  @override
  State<BabifixSlideToConfirm> createState() => _BabifixSlideToConfirmState();
}

class _BabifixSlideToConfirmState extends State<BabifixSlideToConfirm>
    with SingleTickerProviderStateMixin {
  double _dx = 0; // position du curseur (0 → max)
  bool _busy = false;
  bool _done = false;

  // Animation d'indice : des chevrons défilent vers la droite pour montrer
  // clairement qu'il faut GLISSER (sinon le bouton n'est pas évident).
  late final AnimationController _hintCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _hintCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final thumb = h - 8;
    return LayoutBuilder(
      builder: (context, c) {
        final maxDx = (c.maxWidth - thumb - 8).clamp(0.0, double.infinity);
        final progress = maxDx > 0 ? (_dx / maxDx).clamp(0.0, 1.0) : 0.0;

        Future<void> finish() async {
          if (_busy || _done) return;
          setState(() => _busy = true);
          try {
            await widget.onConfirmed();
            if (mounted) setState(() => _done = true);
          } finally {
            if (mounted && !_done) {
              setState(() {
                _busy = false;
                _dx = 0;
              });
            }
          }
        }

        return Container(
          height: h,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(h / 2),
            border: Border.all(color: widget.color.withValues(alpha: 0.30)),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Remplissage progressif (suit le curseur).
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: _dx + thumb + 4,
                height: h,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [widget.color, widget.color.withValues(alpha: 0.8)],
                  ),
                  borderRadius: BorderRadius.circular(h / 2),
                ),
              ),
              // Libellé centré.
              Positioned.fill(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.only(left: thumb * 0.5),
                    child: Text(
                      _busy
                          ? widget.confirmingLabel
                          : (_done ? 'Confirmé ✓' : widget.label),
                      style: TextStyle(
                        color: progress > 0.45 ? Colors.white : widget.color,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ),
              ),
              // Chevrons d'indice « ››› » : montrent clairement qu'il faut
              // glisser vers la droite. Ils s'estompent au fur et à mesure.
              if (!_busy && !_done)
                Positioned(
                  right: 18,
                  child: Opacity(
                    opacity: (1 - progress * 2).clamp(0.0, 1.0),
                    child: AnimatedBuilder(
                      animation: _hintCtrl,
                      builder: (_, __) {
                        final t = _hintCtrl.value;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(3, (i) {
                            final phase = ((t - i * 0.18) % 1.0);
                            final op = (phase < 0.5
                                    ? phase * 2
                                    : (1 - phase) * 2)
                                .clamp(0.25, 1.0);
                            return Opacity(
                              opacity: op,
                              child: Icon(
                                Icons.chevron_right_rounded,
                                color: progress > 0.45
                                    ? Colors.white
                                    : widget.color,
                                size: 20,
                              ),
                            );
                          }),
                        );
                      },
                    ),
                  ),
                ),
              // Curseur draggable.
              Positioned(
                left: 4 + _dx,
                child: GestureDetector(
                  onHorizontalDragUpdate: (_busy || _done)
                      ? null
                      : (d) => setState(
                          () => _dx = (_dx + d.delta.dx).clamp(0.0, maxDx)),
                  onHorizontalDragEnd: (_busy || _done)
                      ? null
                      : (_) {
                          if (progress >= 0.9) {
                            setState(() => _dx = maxDx);
                            finish();
                          } else {
                            setState(() => _dx = 0);
                          }
                        },
                  child: Container(
                    width: thumb,
                    height: thumb,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _busy
                        ? Padding(
                            padding: const EdgeInsets.all(14),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(widget.color),
                            ),
                          )
                        : Icon(
                            _done ? Icons.check_rounded : widget.icon,
                            color: widget.color,
                            size: 22,
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
