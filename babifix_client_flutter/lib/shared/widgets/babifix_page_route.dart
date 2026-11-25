import 'package:flutter/material.dart';
import '../../babifix_design_system.dart';

/// Transition de page BABIFIX rapide et fluide (courbe out-cubic, sans saccade).
Route<T> babifixRoute<T>(WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    pageBuilder: (ctx, _, __) => builder(ctx),
    transitionDuration: BabifixDesign.durationStandard,
    reverseTransitionDuration: const Duration(milliseconds: 210),
    transitionsBuilder: (ctx, animation, secondary, child) {
      final reduce = MediaQuery.maybeDisableAnimationsOf(ctx) ?? false;
      if (reduce) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: BabifixDesign.curveOut,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
