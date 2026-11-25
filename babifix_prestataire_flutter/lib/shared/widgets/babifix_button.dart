import 'package:flutter/material.dart';
import '../services/haptics_service.dart';
import '../../babifix_design_system.dart';
import 'babifix_ring_loader.dart';

enum BabifixButtonVariant {
  primary,
  navy,
  outlined,
  ghost,
  danger,
}

class BabifixButton extends StatefulWidget {
  const BabifixButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.isOutlined = false,
    this.icon,
    this.width,
    this.variant,
    this.loadingLabel,
    this.height = 52,
    this.borderRadius,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isOutlined;
  final IconData? icon;
  final double? width;
  final BabifixButtonVariant? variant;
  final String? loadingLabel;
  final double height;
  final double? borderRadius;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  State<BabifixButton> createState() => _BabifixButtonState();
}

class _BabifixButtonState extends State<BabifixButton> {
  bool _pressed = false;

  BabifixButtonVariant get _effectiveVariant {
    if (widget.variant != null) return widget.variant!;
    return widget.isOutlined
        ? BabifixButtonVariant.outlined
        : BabifixButtonVariant.primary;
  }

  bool get _enabled => !widget.isLoading && widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final radius = widget.borderRadius ?? BabifixDesign.radiusMD;
    final variant = _effectiveVariant;

    Color bg;
    Color fg;
    BorderSide? side;
    List<BoxShadow>? shadows;

    switch (variant) {
      case BabifixButtonVariant.primary:
        bg = widget.backgroundColor ?? BabifixDesign.ciOrange;
        if (_pressed && _enabled) {
          bg = Color.lerp(bg, Colors.black, 0.14) ?? BabifixDesign.ciOrangePressed;
        }
        fg = widget.foregroundColor ?? Colors.white;
        if (!_enabled) {
          bg = bg.withValues(alpha: 0.48);
          fg = Colors.white.withValues(alpha: 0.85);
        } else {
          shadows = [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.09),
              blurRadius: _pressed ? 4 : 10,
              offset: Offset(0, _pressed ? 1 : 4),
            ),
          ];
        }
      case BabifixButtonVariant.navy:
        bg = widget.backgroundColor ??
            (isDark ? BabifixDesign.bgWhite : BabifixDesign.navy);
        if (_pressed && _enabled) {
          bg = Color.lerp(bg, isDark ? Colors.grey.shade300 : Colors.black, 0.14) ??
              bg;
        }
        fg = widget.foregroundColor ??
            (isDark ? BabifixDesign.navy : Colors.white);
        if (!_enabled) {
          bg = bg.withValues(alpha: 0.45);
        }
      case BabifixButtonVariant.danger:
        bg = widget.backgroundColor ?? BabifixDesign.error;
        if (_pressed && _enabled) {
          bg = Color.lerp(bg, Colors.black, 0.15) ?? bg;
        }
        fg = widget.foregroundColor ?? Colors.white;
        if (!_enabled) bg = bg.withValues(alpha: 0.45);
      case BabifixButtonVariant.outlined:
        bg = widget.backgroundColor ??
            (_pressed && _enabled
                ? (isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : BabifixDesign.navy.withValues(alpha: 0.04))
                : Colors.transparent);
        fg = widget.foregroundColor ??
            (isDark ? BabifixDesign.textStrongDark : BabifixDesign.navy);
        final borderColor = widget.foregroundColor != null
            ? widget.foregroundColor!.withValues(alpha: _enabled ? 0.35 : 0.16)
            : (isDark
                ? Colors.white.withValues(alpha: _enabled ? 0.35 : 0.14)
                : BabifixDesign.navy.withValues(alpha: _enabled ? 0.38 : 0.14));
        side = BorderSide(color: borderColor, width: 1.5);
      case BabifixButtonVariant.ghost:
        bg = _pressed && _enabled
            ? (isDark
                ? Colors.white.withValues(alpha: 0.07)
                : const Color(0x0F0F172A))
            : Colors.transparent;
        fg = widget.foregroundColor ??
            (isDark ? BabifixDesign.cyan : BabifixDesign.navy);
    }

    final child = AnimatedSwitcher(
      duration: BabifixDesign.durationFast,
      switchInCurve: BabifixDesign.curveOut,
      switchOutCurve: Curves.easeIn,
      child: widget.isLoading
          ? Row(
              key: const ValueKey('loading'),
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                BabifixRingLoader.mono(size: 18, color: fg),
                if (widget.loadingLabel != null) ...[
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      widget.loadingLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                ],
              ],
            )
          : Row(
              key: ValueKey(widget.label),
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, color: fg, size: 19),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            ),
    );

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedScale(
        scale: (_pressed && _enabled && !reduce) ? 0.97 : 1.0,
        duration: BabifixDesign.durationTap,
        curve: BabifixDesign.curveOut,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
            onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
            onTapCancel: () {
              if (_pressed) setState(() => _pressed = false);
            },
            onTap: _enabled
                ? () {
                    if (variant == BabifixButtonVariant.primary ||
                        variant == BabifixButtonVariant.navy) {
                      HapticsService.medium();
                    } else {
                      HapticsService.light();
                    }
                    widget.onPressed?.call();
                  }
                : null,
            child: AnimatedContainer(
              duration: BabifixDesign.durationTap,
              curve: BabifixDesign.curveOut,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(radius),
                border: side != null ? Border.fromBorderSide(side) : null,
                boxShadow: shadows,
              ),
              alignment: Alignment.center,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
