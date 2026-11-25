import 'dart:async';
import 'package:flutter/material.dart';

class BabifixNotificationOverlay {
  BabifixNotificationOverlay._();

  static OverlayEntry? _currentEntry;
  static Timer? _timer;

  static void show({
    required OverlayState overlay,
    required String title,
    required String body,
    bool isUrgent = false,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 4),
  }) {
    _dismiss();

    _currentEntry = OverlayEntry(
      builder: (_) => _TopPopupBanner(
        title: title,
        body: body,
        isUrgent: isUrgent,
        duration: duration,
        onTap: () {
          _dismiss();
          onTap?.call();
        },
        onDismiss: _dismiss,
      ),
    );

    overlay.insert(_currentEntry!);
    _timer = Timer(duration, _dismiss);
  }

  static void _dismiss() {
    _timer?.cancel();
    _timer = null;
    try {
      _currentEntry?.remove();
    } catch (_) {}
    _currentEntry = null;
  }
}

class _TopPopupBanner extends StatefulWidget {
  final String title;
  final String body;
  final bool isUrgent;
  final Duration duration;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _TopPopupBanner({
    required this.title,
    required this.body,
    required this.isUrgent,
    required this.duration,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_TopPopupBanner> createState() => _TopPopupBannerState();
}

class _TopPopupBannerState extends State<_TopPopupBanner>
    with TickerProviderStateMixin {
  late final AnimationController _enterCtrl;
  late final AnimationController _progressCtrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutCubic));
    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut),
    );
    _enterCtrl.forward();

    _progressCtrl = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..forward();
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    _progressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent =
        widget.isUrgent ? const Color(0xFFDC2626) : const Color(0xFFE87722);
    final bg = isDark ? const Color(0xFF0F213E) : Colors.white;
    final border = widget.isUrgent
        ? const Color(0xFFFCA5A5)
        : (isDark ? const Color(0xFF1E3A63) : const Color(0xFFE2E8F0));
    final titleColor = isDark ? Colors.white : const Color(0xFF0B1B34);
    final bodyColor =
        isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569);

    return Positioned(
      top: topPadding + 10,
      left: 14,
      right: 14,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Dismissible(
            key: ValueKey('notif-${widget.title}-${widget.body}'),
            direction: DismissDirection.up,
            onDismissed: (_) => widget.onDismiss(),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: border, width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0B1B34).withValues(alpha: 0.14),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 11, 8, 10),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                widget.isUrgent
                                    ? Icons.priority_high_rounded
                                    : Icons.notifications_active_rounded,
                                color: accent,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          widget.title,
                                          style: TextStyle(
                                            color: titleColor,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13.5,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: accent.withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(99),
                                        ),
                                        child: Text(
                                          widget.isUrgent ? 'Urgent' : 'Maintenant',
                                          style: TextStyle(
                                            color: accent,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (widget.body.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.body,
                                      style: TextStyle(
                                        color: bodyColor,
                                        fontSize: 12.2,
                                        height: 1.3,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              onPressed: widget.onDismiss,
                              icon: Icon(
                                Icons.close_rounded,
                                color: bodyColor.withValues(alpha: 0.7),
                                size: 17,
                              ),
                            ),
                          ],
                        ),
                      ),
                      AnimatedBuilder(
                        animation: _progressCtrl,
                        builder: (_, __) => LinearProgressIndicator(
                          value: 1.0 - _progressCtrl.value,
                          minHeight: 2.5,
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            accent.withValues(alpha: 0.65),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
