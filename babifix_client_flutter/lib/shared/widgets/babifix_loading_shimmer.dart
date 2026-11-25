import 'package:flutter/material.dart';
import '../../babifix_design_system.dart';
import 'babifix_skeleton.dart';

class BabifixLoadingShimmer extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return BabifixSkeletonBox(
      width: width,
      height: height,
      borderRadius: borderRadius ?? BabifixDesign.radiusSM,
    );
  }
}

class BabifixCardShimmer extends StatelessWidget {
  const BabifixCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return const BabifixSkeletonCard(lines: 2);
  }
}
