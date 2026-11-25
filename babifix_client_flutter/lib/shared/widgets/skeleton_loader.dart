import 'package:flutter/material.dart';
import '../../babifix_design_system.dart';
import 'babifix_skeleton.dart';

class SkeletonLoader extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonLoader({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return BabifixSkeletonBox(
      width: width,
      height: height,
      borderRadius: borderRadius,
    );
  }
}

class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BabifixDesign.surfaceOf(context),
        borderRadius: BorderRadius.circular(BabifixDesign.radiusLG),
        border: Border.all(color: BabifixDesign.borderOf(context)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonLoader(width: 48, height: 48, borderRadius: 24),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLoader(width: 150, height: 16),
                    SizedBox(height: 8),
                    SkeletonLoader(width: 100, height: 12),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          SkeletonLoader(height: 13),
          SizedBox(height: 8),
          SkeletonLoader(width: 200, height: 13),
          SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SkeletonLoader(width: 84, height: 30, borderRadius: 12),
              SkeletonLoader(width: 64, height: 30, borderRadius: 12),
            ],
          ),
        ],
      ),
    );
  }
}

class SkeletonList extends StatelessWidget {
  final int itemCount;

  const SkeletonList({super.key, this.itemCount = 5});

  @override
  Widget build(BuildContext context) {
    return BabifixSkeletonScope(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: itemCount,
        itemBuilder: (context, index) => const SkeletonCard(),
      ),
    );
  }
}

class SkeletonPrestataireCard extends StatelessWidget {
  const SkeletonPrestataireCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BabifixDesign.surfaceOf(context),
        borderRadius: BorderRadius.circular(BabifixDesign.radiusLG),
        border: Border.all(color: BabifixDesign.borderOf(context)),
      ),
      child: const Row(
        children: [
          SkeletonLoader(width: 66, height: 66, borderRadius: 14),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLoader(width: 130, height: 15),
                SizedBox(height: 7),
                SkeletonLoader(width: 88, height: 12),
                SizedBox(height: 7),
                Row(
                  children: [
                    SkeletonLoader(width: 60, height: 12),
                    SizedBox(width: 12),
                    SkeletonLoader(width: 44, height: 12),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
