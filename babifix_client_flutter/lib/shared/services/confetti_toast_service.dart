import 'dart:math';
import 'package:flutter/material.dart';

abstract class ConfettiService {
  static void show(BuildContext context, {String? message}) {
    final overlay = Overlay.of(context);
    final random = Random();
    final screenWidth = MediaQuery.of(context).size.width;

    final entries = List.generate(30, (index) {
      return _ConfettiParticle(
        x: random.nextDouble() * screenWidth,
        y: -random.nextDouble() * 200 - 50,
        color: [
          Colors.red,
          Colors.blue,
          Colors.green,
          Colors.yellow,
          Colors.purple,
          Colors.orange,
          Colors.pink,
        ][random.nextInt(7)],
        speed: random.nextDouble() * 3 + 2,
        angle: random.nextDouble() * 0.5 - 0.25,
        size: random.nextDouble() * 8 + 4,
      );
    });

    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) => _ConfettiWidget(
        entries: entries,
        message: message,
        onRemove: () => overlayEntry.remove(),
      ),
    );

    overlay.insert(overlayEntry);
  }

  static void showSuccess(BuildContext context, String message) {
    show(context, message: message);
  }

  static void showError(BuildContext context, String message) {
    final overlay = Overlay.of(context);

    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 50,
        left: 20,
        right: 20,
        child: Material(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: Colors.red.shade900,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => overlayEntry.remove(),
                  child: Icon(
                    Icons.close,
                    color: Colors.red.shade400,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 4), () {
      overlayEntry.remove();
    });
  }
}

class _ConfettiParticle {
  final double x;
  final double y;
  final Color color;
  final double speed;
  final double angle;
  final double size;

  _ConfettiParticle({
    required this.x,
    required this.y,
    required this.color,
    required this.speed,
    required this.angle,
    required this.size,
  });
}

class _ConfettiWidget extends StatefulWidget {
  final List<_ConfettiParticle> entries;
  final String? message;
  final VoidCallback onRemove;

  const _ConfettiWidget({
    required this.entries,
    required this.message,
    required this.onRemove,
  });

  @override
  State<_ConfettiWidget> createState() => _ConfettiWidgetState();
}

class _ConfettiWidgetState extends State<_ConfettiWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addListener(_update);
    _controller.forward();
  }

  void _update() {
    setState(() {
      _progress = _controller.value * 3;
    });
    if (_progress >= 3.0) {
      widget.onRemove();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Stack(
      children: [
        if (widget.message != null)
          Positioned(
            top: MediaQuery.of(context).size.height * 0.4,
            left: 0,
            right: 0,
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 500),
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.scale(
                      scale: 0.5 + (value * 0.5),
                      child: child,
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade700,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.message!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ...widget.entries.map((particle) {
          final y = particle.y + (_progress * 100 * particle.speed);
          final x = particle.x + (sin(_progress * 5 + particle.x) * 30);
          return Positioned(
            left: x,
            top: y,
            child: Transform.rotate(
              angle: _progress * particle.angle * 10,
              child: Container(
                width: particle.size,
                height: particle.size,
                decoration: BoxDecoration(
                  color: particle.color,
                  shape: BoxShape.rectangle,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class ToastService {
  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    final overlay = Overlay.of(context);

    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 50,
        left: 20,
        right: 20,
        child: Material(
          borderRadius: BorderRadius.circular(12),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 300),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, -20 * (1 - value)),
                  child: child,
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isError ? Colors.red.shade50 : Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isError ? Colors.red.shade200 : Colors.green.shade200,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    isError ? Icons.error_outline : Icons.check_circle_outline,
                    color: isError
                        ? Colors.red.shade700
                        : Colors.green.shade700,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message,
                      style: TextStyle(
                        color: isError
                            ? Colors.red.shade900
                            : Colors.green.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => overlayEntry.remove(),
                    child: Icon(
                      Icons.close,
                      color: isError
                          ? Colors.red.shade400
                          : Colors.green.shade400,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 3), () {
      overlayEntry.remove();
    });
  }

  static void success(BuildContext context, String message) {
    show(context, message, isError: false);
  }

  static void error(BuildContext context, String message) {
    show(context, message, isError: true);
  }
}
