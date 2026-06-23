import 'dart:async';

import 'package:flutter/material.dart';

/// Chronomètre de prestation — preuve horodatée.
///
/// - Pendant l'intervention (`endedAt == null`) : compteur qui défile en
///   temps réel (mise à jour chaque seconde) avec un point « live » pulsant.
/// - Une fois terminé (`endedAt != null`) : durée totale figée + heures de
///   début et de fin. Sert de preuve du temps passé sur la prestation.
class BabifixPrestationTimer extends StatefulWidget {
  const BabifixPrestationTimer({
    super.key,
    required this.startedAt,
    this.endedAt,
    this.compact = false,
    this.encouragement,
  });

  final DateTime? startedAt;
  final DateTime? endedAt;

  /// Version réduite (une seule ligne) pour les cartes denses.
  final bool compact;

  /// Message d'encouragement affiché une fois terminé (ex. « Excellent ! 12 min
  /// de moins que votre dernière prestation »). Optionnel.
  final String? encouragement;

  @override
  State<BabifixPrestationTimer> createState() => _BabifixPrestationTimerState();
}

class _BabifixPrestationTimerState extends State<BabifixPrestationTimer> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _maybeStartTicker();
  }

  @override
  void didUpdateWidget(covariant BabifixPrestationTimer old) {
    super.didUpdateWidget(old);
    if (old.startedAt != widget.startedAt || old.endedAt != widget.endedAt) {
      _maybeStartTicker();
    }
  }

  void _maybeStartTicker() {
    _ticker?.cancel();
    // On ne fait défiler le compteur que pendant l'intervention en cours.
    if (widget.startedAt != null && widget.endedAt == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _fmtDuration(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    String two(int v) => v.toString().padLeft(2, '0');
    if (h > 0) return '$h:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }

  String _fmtDurationLong(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    // On n'affiche QUE heures et minutes (pas de secondes) une fois terminé.
    if (h > 0) return '$h h ${m.toString().padLeft(2, '0')} min';
    if (m > 0) return '$m min';
    return 'moins d\'1 min';
  }

  String _fmtTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final start = widget.startedAt;
    if (start == null) return const SizedBox.shrink();

    final ended = widget.endedAt;
    final running = ended == null;
    final elapsed = (ended ?? DateTime.now()).difference(start);

    final Color accent =
        running ? const Color(0xFF22C55E) : const Color(0xFF4CC9F0);

    if (widget.compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(running ? Icons.timer_outlined : Icons.timer_rounded,
              size: 15, color: accent),
          const SizedBox(width: 5),
          Text(
            running
                ? _fmtDuration(elapsed)
                : 'Durée : ${_fmtDurationLong(elapsed)}',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: accent,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.14),
            accent.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(
              running ? Icons.timer_outlined : Icons.verified_rounded,
              color: accent,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      running ? 'Prestation en cours' : 'Durée de la prestation',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    if (running) ...[
                      const SizedBox(width: 8),
                      _LiveDot(color: accent),
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                // Une fois terminé, la durée apparaît avec une petite animation
                // d'entrée (scale + fade) — sensation de « résultat » satisfaisant.
                running
                    ? Text(
                        _fmtDuration(elapsed),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: accent,
                          letterSpacing: 0.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      )
                    : TweenAnimationBuilder<double>(
                        duration: const Duration(milliseconds: 520),
                        curve: Curves.easeOutBack,
                        tween: Tween(begin: 0, end: 1),
                        builder: (_, v, child) => Opacity(
                          opacity: v.clamp(0.0, 1.0),
                          child: Transform.scale(
                            scale: 0.85 + 0.15 * v.clamp(0.0, 1.0),
                            alignment: Alignment.centerLeft,
                            child: child,
                          ),
                        ),
                        child: Text(
                          _fmtDurationLong(elapsed),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: accent,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                const SizedBox(height: 1),
                Text(
                  ended == null
                      ? 'Démarrée à ${_fmtTime(start)}'
                      : 'De ${_fmtTime(start)} à ${_fmtTime(ended)} · preuve horodatée',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF64748B),
                  ),
                ),
                // Encouragement (comparaison à la dernière prestation).
                if (!running &&
                    widget.encouragement != null &&
                    widget.encouragement!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOut,
                    tween: Tween(begin: 0, end: 1),
                    builder: (_, v, child) => Opacity(
                      opacity: v.clamp(0.0, 1.0),
                      child: child,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFF22C55E)
                                .withValues(alpha: 0.30)),
                      ),
                      child: Row(
                        children: [
                          const Text('🎉', style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              widget.encouragement!,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF16A34A),
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.color});
  final Color color;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1).animate(_c),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text('EN DIRECT',
                style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: widget.color)),
          ],
        ),
      ),
    );
  }
}
