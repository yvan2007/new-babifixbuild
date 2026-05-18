/// GpsLocationCard — Carte UI qui matérialise l'état de la géolocalisation
/// client (loading → détectée → refusée) avec animations + bouton refresh.
///
/// Usage :
///   GpsLocationCard(
///     state: _gpsState,
///     addressText: _addressCtrl.text,
///     onRefresh: _tryAutoLocate,
///     onChangeAddress: () => Navigator.push(...),
///   )
import 'package:flutter/material.dart';

import '../../babifix_design_system.dart';

enum GpsLocationState { idle, resolving, detected, denied }

class GpsLocationCard extends StatefulWidget {
  final GpsLocationState state;
  final String addressText;
  final VoidCallback? onRefresh;
  final VoidCallback? onChangeAddress;

  const GpsLocationCard({
    super.key,
    required this.state,
    required this.addressText,
    this.onRefresh,
    this.onChangeAddress,
  });

  @override
  State<GpsLocationCard> createState() => _GpsLocationCardState();
}

class _GpsLocationCardState extends State<GpsLocationCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  GpsLocationState? _prevState;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _maybeTriggerSuccessAnim();
  }

  void _maybeTriggerSuccessAnim() {
    if (widget.state == GpsLocationState.detected &&
        _prevState != GpsLocationState.detected) {
      _pulse.forward(from: 0);
    }
    _prevState = widget.state;
  }

  @override
  void didUpdateWidget(covariant GpsLocationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeTriggerSuccessAnim();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Color get _color {
    switch (widget.state) {
      case GpsLocationState.detected:
        return BabifixDesign.ciGreen;
      case GpsLocationState.resolving:
        return BabifixDesign.ciBlue;
      case GpsLocationState.denied:
        return Colors.orange.shade700;
      case GpsLocationState.idle:
        return Colors.grey.shade500;
    }
  }

  IconData get _icon {
    switch (widget.state) {
      case GpsLocationState.detected:
        return Icons.gps_fixed;
      case GpsLocationState.resolving:
        return Icons.gps_not_fixed;
      case GpsLocationState.denied:
        return Icons.gps_off;
      case GpsLocationState.idle:
        return Icons.place_outlined;
    }
  }

  String get _title {
    switch (widget.state) {
      case GpsLocationState.detected:
        return 'Position détectée';
      case GpsLocationState.resolving:
        return 'Localisation en cours…';
      case GpsLocationState.denied:
        return 'Position non disponible';
      case GpsLocationState.idle:
        return 'Adresse';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _animatedIcon(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: _color,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        if (widget.state == GpsLocationState.detected) ...[
                          const SizedBox(width: 6),
                          _checkBadge(),
                        ],
                      ],
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, 0.2),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: widget.addressText.trim().isEmpty
                          ? Text(
                              widget.state == GpsLocationState.resolving
                                  ? 'Lecture du GPS…'
                                  : 'Renseignez une adresse',
                              key: const ValueKey('empty'),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600),
                            )
                          : Padding(
                              key: ValueKey(widget.addressText),
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                widget.addressText,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13.5, height: 1.3),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              if (widget.state == GpsLocationState.resolving)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (widget.onRefresh != null)
                Expanded(
                  child: TextButton.icon(
                    onPressed: widget.state == GpsLocationState.resolving
                        ? null
                        : widget.onRefresh,
                    icon: const Icon(Icons.my_location, size: 18),
                    label: const Text('Actualiser GPS'),
                    style: TextButton.styleFrom(
                      foregroundColor: _color,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              if (widget.onChangeAddress != null) ...[
                if (widget.onRefresh != null) const SizedBox(width: 8),
                Expanded(
                  child: TextButton.icon(
                    onPressed: widget.onChangeAddress,
                    icon: const Icon(Icons.edit_location_alt, size: 18),
                    label: const Text('Modifier'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _animatedIcon() {
    if (widget.state == GpsLocationState.resolving) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 900),
        builder: (_, t, __) => Transform.rotate(
          angle: t * 2 * 3.14159,
          child: Icon(_icon, color: _color, size: 22),
        ),
        onEnd: () {
          if (mounted) setState(() {});
        },
      );
    }
    if (widget.state == GpsLocationState.detected) {
      return AnimatedBuilder(
        animation: _pulse,
        builder: (_, child) {
          final v = _pulse.value;
          final scale = 1.0 + (v < 0.5 ? v * 0.4 : (1 - v) * 0.4);
          return Transform.scale(scale: scale, child: child);
        },
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(_icon, color: _color, size: 18),
        ),
      );
    }
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: Icon(_icon, color: _color, size: 18),
    );
  }

  Widget _checkBadge() {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) {
        final t = Curves.easeOutBack.transform(_pulse.value.clamp(0.0, 1.0));
        return Transform.scale(
          scale: t,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: _color,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, size: 10, color: Colors.white),
          ),
        );
      },
    );
  }
}
