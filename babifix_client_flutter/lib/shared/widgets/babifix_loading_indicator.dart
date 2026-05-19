import 'package:flutter/material.dart';

import 'babifix_ring_loader.dart';

/// Loader BABIFIX (4 anneaux Uiverse + couleurs principales cyan/navy).
/// Identique partout dans l'app — n'utilise jamais le
/// CircularProgressIndicator natif.
class BabifixLoadingIndicator extends StatelessWidget {
  const BabifixLoadingIndicator({super.key, this.message, this.size = 56});

  final String? message;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BabifixRingLoader(size: size),
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
