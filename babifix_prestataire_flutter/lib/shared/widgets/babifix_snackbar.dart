/// Notifications « toast » BABIFIX Prestataire — remplacent les SnackBars
/// Material par défaut (jugées peu pro). Carte navy flottante, coins arrondis,
/// liseré coloré + icône dans une pastille, titre + message. Variantes
/// success / error / info / warning ; l'info reprend l'orange prestataire.
import 'dart:async';

import 'package:flutter/material.dart';

enum BabifixToastType { success, error, info, warning }

class _ToastConfig {
  const _ToastConfig(this.color, this.icon, this.defaultTitle);
  final Color color;
  final IconData icon;
  final String defaultTitle;
}

_ToastConfig _configFor(BabifixToastType type) {
  switch (type) {
    case BabifixToastType.success:
      return const _ToastConfig(
        Color(0xFF22C55E),
        Icons.check_circle_rounded,
        'Succès',
      );
    case BabifixToastType.error:
      return const _ToastConfig(
        Color(0xFFEF4444),
        Icons.error_rounded,
        'Erreur',
      );
    case BabifixToastType.warning:
      return const _ToastConfig(
        Color(0xFFF59E0B),
        Icons.warning_amber_rounded,
        'Attention',
      );
    case BabifixToastType.info:
      return const _ToastConfig(
        Color(0xFFE87722),
        Icons.info_rounded,
        'Information',
      );
  }
}

OverlayEntry? _activeToastEntry;
Timer? _activeToastTimer;

void _dismissTopToast() {
  _activeToastTimer?.cancel();
  _activeToastTimer = null;
  try {
    _activeToastEntry?.remove();
  } catch (_) {}
  _activeToastEntry = null;
}

/// Affiche une capsule discrete en HAUT de l'ecran qui disparait seule.
void showBabifixToast(
  BuildContext context, {
  required String message,
  BabifixToastType type = BabifixToastType.info,
  String? title,
  Duration duration = const Duration(milliseconds: 2600),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final cfg = _configFor(type);
  _dismissTopToast();

  final entry = OverlayEntry(
    builder: (ctx) => _BabifixTopToastWrapper(
      message: message,
      title: title ?? cfg.defaultTitle,
      cfg: cfg,
      onDismiss: _dismissTopToast,
    ),
  );
  _activeToastEntry = entry;
  overlay.insert(entry);
  _activeToastTimer = Timer(duration, _dismissTopToast);
}

class _BabifixTopToastWrapper extends StatefulWidget {
  const _BabifixTopToastWrapper({
    required this.message,
    required this.title,
    required this.cfg,
    required this.onDismiss,
  });

  final String message;
  final String title;
  final _ToastConfig cfg;
  final VoidCallback onDismiss;

  @override
  State<_BabifixTopToastWrapper> createState() => _BabifixTopToastWrapperState();
}

class _BabifixTopToastWrapperState extends State<_BabifixTopToastWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..forward();
    _slide = Tween<Offset>(begin: const Offset(0, -1.0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = Tween<double>(begin: 0, end: 1).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Positioned(
      top: top + 10,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Dismissible(
            key: ValueKey('bx-toast-pro-${widget.title}-${widget.message}'),
            direction: DismissDirection.up,
            onDismissed: (_) => widget.onDismiss(),
            child: Material(
              color: Colors.transparent,
              child: GestureDetector(
                onTap: widget.onDismiss,
                child: _BabifixToastCard(
                  message: widget.message,
                  title: widget.title,
                  cfg: widget.cfg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BabifixToastCard extends StatelessWidget {
  const _BabifixToastCard({
    required this.message,
    required this.title,
    required this.cfg,
  });

  final String message;
  final String title;
  final _ToastConfig cfg;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ColoredBox(
          color: const Color(0xFF0B1B34),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 5, color: cfg.color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: cfg.color.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(cfg.icon, color: cfg.color, size: 21),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                message,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12.5,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
