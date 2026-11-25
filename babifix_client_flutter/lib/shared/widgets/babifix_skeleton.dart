import 'package:flutter/material.dart';
import '../../babifix_design_system.dart';

/// Systeme de squelettes de chargement calibres 1:1 sur la geometrie reelle
/// des pages BABIFIX (modes white, light et blue pris en charge).
class BabifixSkeletonScope extends StatefulWidget {
  const BabifixSkeletonScope({super.key, required this.child});
  final Widget child;

  @override
  State<BabifixSkeletonScope> createState() => _BabifixSkeletonScopeState();
}

class _BabifixSkeletonScopeState extends State<BabifixSkeletonScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    )..repeat();
    _anim = Tween<double>(begin: -1.6, end: 1.6).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      return _SkeletonInherited(sweepValue: 0.0, child: widget.child);
    }
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) =>
          _SkeletonInherited(sweepValue: _anim.value, child: child!),
      child: widget.child,
    );
  }
}

class _SkeletonInherited extends InheritedWidget {
  const _SkeletonInherited({required this.sweepValue, required super.child});
  final double sweepValue;

  static double? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_SkeletonInherited>()
      ?.sweepValue;

  @override
  bool updateShouldNotify(covariant _SkeletonInherited old) =>
      old.sweepValue != sweepValue;
}

class BabifixSkeletonBox extends StatelessWidget {
  const BabifixSkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = 8,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final sweep = _SkeletonInherited.maybeOf(context);
    if (sweep != null) {
      return _box(context, sweep);
    }
    return _StandaloneSkeletonBox(
      width: width,
      height: height,
      borderRadius: borderRadius,
    );
  }

  Widget _box(BuildContext context, double sweep) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF162744) : const Color(0xFFE7ECF3);
    final hi = isDark ? const Color(0xFF23395D) : const Color(0xFFF5F8FC);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment(sweep - 0.9, -0.2),
          end: Alignment(sweep + 0.9, 0.2),
          colors: [base, hi, base],
          stops: const [0.1, 0.5, 0.9],
        ),
      ),
    );
  }
}

class _StandaloneSkeletonBox extends StatefulWidget {
  const _StandaloneSkeletonBox({
    this.width,
    required this.height,
    required this.borderRadius,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<_StandaloneSkeletonBox> createState() => _StandaloneSkeletonBoxState();
}

class _StandaloneSkeletonBoxState extends State<_StandaloneSkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    )..repeat();
    _anim = Tween<double>(begin: -1.6, end: 1.6).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF162744) : const Color(0xFFE7ECF3);
    final hi = isDark ? const Color(0xFF23395D) : const Color(0xFFF5F8FC);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          gradient: LinearGradient(
            begin: Alignment(_anim.value - 0.9, -0.2),
            end: Alignment(_anim.value + 0.9, 0.2),
            colors: [base, hi, base],
            stops: const [0.1, 0.5, 0.9],
          ),
        ),
      ),
    );
  }
}

class BabifixSkeletonListTile extends StatelessWidget {
  const BabifixSkeletonListTile({super.key, this.margin});
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: BabifixDesign.surfaceOf(context),
        borderRadius: BorderRadius.circular(BabifixDesign.radiusMD),
        border: Border.all(color: BabifixDesign.borderOf(context)),
      ),
      child: const Row(
        children: [
          BabifixSkeletonBox(width: 42, height: 42, borderRadius: 12),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BabifixSkeletonBox(width: 140, height: 14, borderRadius: 6),
                SizedBox(height: 7),
                BabifixSkeletonBox(width: 96, height: 11, borderRadius: 5),
              ],
            ),
          ),
          SizedBox(width: 12),
          BabifixSkeletonBox(width: 74, height: 18, borderRadius: 6),
        ],
      ),
    );
  }
}

class BabifixSkeletonCard extends StatelessWidget {
  const BabifixSkeletonCard({super.key, this.lines = 2});
  final int lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BabifixDesign.surfaceOf(context),
        borderRadius: BorderRadius.circular(BabifixDesign.radiusLG),
        border: Border.all(color: BabifixDesign.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              BabifixSkeletonBox(width: 46, height: 46, borderRadius: 23),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BabifixSkeletonBox(width: 150, height: 15, borderRadius: 6),
                    SizedBox(height: 6),
                    BabifixSkeletonBox(width: 90, height: 11, borderRadius: 5),
                  ],
                ),
              ),
              BabifixSkeletonBox(width: 62, height: 24, borderRadius: 99),
            ],
          ),
          for (var i = 0; i < lines; i++) ...[
            SizedBox(height: i == 0 ? 14 : 8),
            BabifixSkeletonBox(
              width: i == lines - 1 ? 180 : double.infinity,
              height: 12,
              borderRadius: 6,
            ),
          ],
        ],
      ),
    );
  }
}
