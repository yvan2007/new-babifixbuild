import 'package:flutter/material.dart';
import '../../babifix_design_system.dart';

class BabifixLoadingIndicator extends StatelessWidget {
  const BabifixLoadingIndicator({super.key, this.message, this.size = 40});

  final String? message;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: isLight ? BabifixDesign.cyan : Colors.white,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class BabifixOverlayLoading extends StatelessWidget {
  const BabifixOverlayLoading({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: BabifixLoadingIndicator(message: message),
    );
  }
}
