import 'package:flutter/material.dart';
import '../services/haptics_service.dart';
import '../../babifix_design_system.dart';

class BabifixButton extends StatelessWidget {
  const BabifixButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.isOutlined = false,
    this.icon,
    this.width,
  });

  final String label;
  final VoidCallback onPressed;
  final bool isLoading;
  final bool isOutlined;
  final IconData? icon;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    if (isOutlined) {
      return SizedBox(
        width: width,
        child: OutlinedButton(
          onPressed: isLoading
              ? null
              : () {
                  HapticsService.light();
                  onPressed();
                },
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BabifixDesign.radiusMD),
            ),
            side: BorderSide(
              color: isLight ? BabifixDesign.navy : BabifixDesign.cyan,
            ),
          ),
          child: _child(isLight ? BabifixDesign.navy : BabifixDesign.cyan),
        ),
      );
    }

    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading
              ? null
              : () {
                  HapticsService.medium();
                  onPressed();
                },
          borderRadius: BorderRadius.circular(BabifixDesign.radiusMD),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BabifixDesign.radiusMD),
              gradient: isLoading ? null : BabifixDesign.accentGradient,
              boxShadow: isLoading ? null : BabifixDesign.cyanGlowShadow(),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: _child(Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _child(Color color) {
    if (isLoading) {
      return SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
        ],
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

class BabifixIconButton extends StatelessWidget {
  const BabifixIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 44,
    this.backgroundColor,
    this.iconColor,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final Color? backgroundColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Material(
      color:
          backgroundColor ??
          (isLight ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B)),
      borderRadius: BorderRadius.circular(size / 2),
      child: InkWell(
        onTap: () {
          HapticsService.selection();
          onPressed();
        },
        borderRadius: BorderRadius.circular(size / 2),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            color: iconColor ?? (isLight ? BabifixDesign.navy : Colors.white),
            size: size * 0.45,
          ),
        ),
      ),
    );
  }
}
