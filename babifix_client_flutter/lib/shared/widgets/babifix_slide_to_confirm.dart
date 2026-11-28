import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../babifix_design_system.dart';
import 'babifix_ring_loader.dart';

/// Bouton glisser pour confirmer BABIFIX.
/// Piste sobre, remplissage fluide, retour haptique et verification de succes.
class BabifixSlideToConfirm extends StatefulWidget {
  const BabifixSlideToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.color = const Color(0xFF16A34A),
    this.icon = Icons.payments_rounded,
    this.confirmingLabel = 'Confirmation...',
    this.height = 58,
  });

  final String label;
  final String confirmingLabel;
  final FutureOr<dynamic> Function() onConfirmed;
  final Color color;
  final IconData icon;
  final double height;

  @override
  State<BabifixSlideToConfirm> createState() => _BabifixSlideToConfirmState();
}

class _BabifixSlideToConfirmState extends State<BabifixSlideToConfirm>
    with SingleTickerProviderStateMixin {
  double _dx = 0;
  bool _busy = false;
  bool _done = false;
  bool _snappedThreshold = false;

  late final AnimationController _hintCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1450),
  )..repeat();

  @override
  void dispose() {
    _hintCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = BabifixDesign.isDark(context);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final h = widget.height;
    final thumb = h - 8;

    return LayoutBuilder(
      builder: (context, c) {
        final maxDx = (c.maxWidth - thumb - 8).clamp(0.0, double.infinity);
        final progress = maxDx > 0 ? (_dx / maxDx).clamp(0.0, 1.0) : 0.0;

        Future<void> finish() async {
          if (_busy || _done) return;
          HapticFeedback.mediumImpact();
          setState(() => _busy = true);
          var confirmed = false;
          try {
            final res = await widget.onConfirmed();
            confirmed = res is bool ? res : true;
            if (confirmed && mounted) {
              HapticFeedback.heavyImpact();
              setState(() {
                _done = true;
                _busy = false;
              });
            }
          } catch (_) {
            confirmed = false;
          } finally {
            if (mounted && !confirmed) {
              setState(() {
                _busy = false;
                _dx = 0;
                _snappedThreshold = false;
              });
            }
          }
        }

        final fillColor = Color.lerp(
          widget.color.withValues(alpha: 0.92),
          widget.color,
          progress,
        )!;

        return Container(
          height: h,
          decoration: BoxDecoration(
            color: isDark
                ? widget.color.withValues(alpha: 0.16)
                : widget.color.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(h / 2),
            border: Border.all(
              color: widget.color.withValues(alpha: progress > 0.1 ? 0.65 : 0.38),
              width: 1.2,
            ),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              AnimatedContainer(
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 90),
                curve: BabifixDesign.curveOut,
                width: _dx + thumb + 4,
                height: h,
                decoration: BoxDecoration(
                  color: fillColor,
                  borderRadius: BorderRadius.circular(h / 2),
                ),
              ),
              Positioned.fill(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.only(left: thumb + 10, right: 34),
                    child: Text(
                      _busy
                          ? widget.confirmingLabel
                          : (_done ? 'Confirme' : widget.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: (_busy || _done || progress > 0.36)
                            ? Colors.white
                            : (isDark ? Colors.white : widget.color),
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ),
              ),
              if (!_busy && !_done && !reduce)
                Positioned(
                  right: 16,
                  child: Opacity(
                    opacity: (1 - progress * 2.2).clamp(0.0, 1.0),
                    child: RepaintBoundary(
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
                                  .clamp(0.22, 0.95);
                              return Opacity(
                                opacity: op,
                                child: Icon(
                                  Icons.chevron_right_rounded,
                                  color: progress > 0.44
                                      ? Colors.white
                                      : widget.color,
                                  size: 19,
                                ),
                              );
                            }),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 4 + _dx,
                child: GestureDetector(
                  onHorizontalDragUpdate: (_busy || _done)
                      ? null
                      : (d) {
                          final next = (_dx + d.delta.dx).clamp(0.0, maxDx);
                          final p = maxDx > 0 ? next / maxDx : 0.0;
                          if (p >= 0.88 && !_snappedThreshold) {
                            _snappedThreshold = true;
                            HapticFeedback.selectionClick();
                          } else if (p < 0.82 && _snappedThreshold) {
                            _snappedThreshold = false;
                          }
                          setState(() => _dx = next);
                        },
                  onHorizontalDragEnd: (_busy || _done)
                      ? null
                      : (_) {
                          final currentProgress =
                              maxDx > 0 ? (_dx / maxDx).clamp(0.0, 1.0) : 0.0;
                          if (currentProgress >= 0.88) {
                            setState(() => _dx = maxDx);
                            finish();
                          } else {
                            setState(() {
                              _dx = 0;
                              _snappedThreshold = false;
                            });
                          }
                        },
                  child: Container(
                    width: thumb,
                    height: thumb,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.06),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _busy
                        ? Center(
                            child: BabifixRingLoader.mono(
                              size: 22,
                              color: widget.color,
                            ),
                          )
                        : Icon(
                            _done ? Icons.check_rounded : widget.icon,
                            color: widget.color,
                            size: 21,
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
