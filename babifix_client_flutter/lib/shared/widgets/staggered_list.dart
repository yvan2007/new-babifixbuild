import 'package:flutter/material.dart';

class StaggeredList extends StatelessWidget {
  const StaggeredList({
    super.key,
    required this.children,
    this.staggerDelay = const Duration(milliseconds: 50),
    this.animationDuration = const Duration(milliseconds: 400),
    this.slideOffset = 20.0,
  });

  final List<Widget> children;
  final Duration staggerDelay;
  final Duration animationDuration;
  final double slideOffset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < children.length; i++)
          _StaggeredItem(
            index: i,
            staggerDelay: staggerDelay,
            animationDuration: animationDuration,
            slideOffset: slideOffset,
            child: children[i],
          ),
      ],
    );
  }
}

class _StaggeredItem extends StatefulWidget {
  const _StaggeredItem({
    required this.index,
    required this.staggerDelay,
    required this.animationDuration,
    required this.slideOffset,
    required this.child,
  });

  final int index;
  final Duration staggerDelay;
  final Duration animationDuration;
  final double slideOffset;
  final Widget child;

  @override
  State<_StaggeredItem> createState() => _StaggeredItemState();
}

class _StaggeredItemState extends State<_StaggeredItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: Offset(0, widget.slideOffset),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    Future.delayed(widget.staggerDelay * widget.index, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Opacity(
        opacity: _opacity.value,
        child: Transform.translate(
          offset: _slide.value,
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
