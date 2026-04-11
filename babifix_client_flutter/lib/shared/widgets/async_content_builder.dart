import 'package:flutter/material.dart';

import '../../features/auth/biometric_login_screen.dart';

enum AsyncStatus { loading, empty, error, content }

class AsyncContentBuilder<T> extends StatelessWidget {
  final AsyncStatus status;
  final T? data;
  final VoidCallback? onRetry;
  final Widget Function(T data) contentBuilder;
  final String emptyMessage;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final String errorMessage;
  final Widget? loadingWidget;

  const AsyncContentBuilder({
    super.key,
    required this.status,
    this.data,
    this.onRetry,
    required this.contentBuilder,
    this.emptyMessage = 'Aucun élément trouvé',
    this.emptyActionLabel,
    this.onEmptyAction,
    this.errorMessage = 'Une erreur est survenue',
    this.loadingWidget,
  });

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      AsyncStatus.loading => loadingWidget ?? const _ShimmerSkeleton(),
      AsyncStatus.empty => _EmptyView(
        message: emptyMessage,
        actionLabel: emptyActionLabel,
        onAction: onEmptyAction,
      ),
      AsyncStatus.error => _ErrorView(message: errorMessage, onRetry: onRetry),
      AsyncStatus.content =>
        data != null
            ? contentBuilder(data as T)
            : const _EmptyView(message: 'Aucun élément trouvé'),
    };
  }
}

// ---------------------------------------------------------------------------
// Shimmer skeleton (loading)
// ---------------------------------------------------------------------------

class _ShimmerSkeleton extends StatefulWidget {
  const _ShimmerSkeleton();

  @override
  State<_ShimmerSkeleton> createState() => _ShimmerSkeletonState();
}

class _ShimmerSkeletonState extends State<_ShimmerSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.surfaceContainerHighest;
    final highlightColor = theme.colorScheme.surface;

    return CustomAnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _shimmerBox(baseColor, highlightColor, double.infinity, 16),
              const SizedBox(height: 12),
              _shimmerBox(baseColor, highlightColor, double.infinity, 120),
              const SizedBox(height: 12),
              _shimmerBox(baseColor, highlightColor, 200, 16),
              const SizedBox(height: 12),
              _shimmerBox(baseColor, highlightColor, double.infinity, 120),
              const SizedBox(height: 12),
              _shimmerBox(baseColor, highlightColor, 140, 16),
            ],
          ),
        );
      },
    );
  }

  Widget _shimmerBox(
    Color baseColor,
    Color highlightColor,
    double width,
    double height,
  ) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment(-1.0 + 2.0 * _controller.value, 0),
          end: Alignment(-1.0 + 2.0 * _controller.value + 1.0, 0),
          colors: [baseColor, highlightColor, baseColor],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyView extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyView({required this.message, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error state
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _ErrorView({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 64,
              color: theme.colorScheme.error.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
