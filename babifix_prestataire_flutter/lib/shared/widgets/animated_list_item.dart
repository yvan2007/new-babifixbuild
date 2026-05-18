/// AnimatedListItem — Fade + slide animation pour chaque item d'une liste.
///
/// L'item entre en glissant légèrement depuis le bas avec un fade.
/// Le décalage `index * delay` produit un effet de cascade naturel.
///
/// Usage :
///   ListView.builder(
///     itemCount: items.length,
///     itemBuilder: (_, i) => AnimatedListItem(
///       index: i,
///       child: MyTile(items[i]),
///     ),
///   )
import 'package:flutter/material.dart';

class AnimatedListItem extends StatefulWidget {
  final int index;
  final Widget child;
  final Duration duration;
  final Duration delayPerIndex;
  final int maxStagger;
  final Offset slideFrom;

  const AnimatedListItem({
    super.key,
    required this.index,
    required this.child,
    this.duration = const Duration(milliseconds: 380),
    this.delayPerIndex = const Duration(milliseconds: 45),
    this.maxStagger = 12,
    this.slideFrom = const Offset(0, 0.06),
  });

  @override
  State<AnimatedListItem> createState() => _AnimatedListItemState();
}

class _AnimatedListItemState extends State<AnimatedListItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    final i = widget.index.clamp(0, widget.maxStagger);
    Future.delayed(widget.delayPerIndex * i, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: widget.slideFrom,
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}
