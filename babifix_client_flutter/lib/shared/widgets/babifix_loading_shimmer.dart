import 'package:flutter/material.dart';
import '../../babifix_design_system.dart';

class BabifixLoadingShimmer extends StatefulWidget {
  const BabifixLoadingShimmer({
    super.key,
    this.width,
    this.height = 20,
    this.borderRadius,
  });

  final double? width;
  final double height;
  final double? borderRadius;

  @override
  State<BabifixLoadingShimmer> createState() => _BabifixLoadingShimmerState();
}

class _BabifixLoadingShimmerState extends State<BabifixLoadingShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _animation = Tween<double>(
      begin: -2,
      end: 2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              widget.borderRadius ?? BabifixDesign.radiusSM,
            ),
            gradient: LinearGradient(
              begin: Alignment(_animation.value - 1, 0),
              end: Alignment(_animation.value + 1, 0),
              colors: isLight
                  ? [
                      const Color(0xFFE2E8F0),
                      const Color(0xFFF1F5F9),
                      const Color(0xFFE2E8F0),
                    ]
                  : [
                      const Color(0xFF1E293B),
                      const Color(0xFF334155),
                      const Color(0xFF1E293B),
                    ],
            ),
          ),
        );
      },
    );
  }
}

class BabifixCardShimmer extends StatelessWidget {
  const BabifixCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(BabifixDesign.spaceLG),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(BabifixDesign.radiusLG),
        boxShadow: BabifixDesign.cardShadow(
          Theme.of(context).brightness == Brightness.light,
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BabifixLoadingShimmer(width: 48, height: 48, borderRadius: 24),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BabifixLoadingShimmer(height: 16),
                    SizedBox(height: 8),
                    BabifixLoadingShimmer(width: 100, height: 12),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          BabifixLoadingShimmer(height: 14),
          SizedBox(height: 8),
          BabifixLoadingShimmer(width: 200, height: 14),
        ],
      ),
    );
  }
}
