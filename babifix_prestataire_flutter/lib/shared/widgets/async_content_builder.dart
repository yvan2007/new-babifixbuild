import 'package:flutter/material.dart';

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
    this.emptyMessage = 'Aucun élément à afficher',
    this.emptyActionLabel,
    this.onEmptyAction,
    this.errorMessage = 'Une erreur est survenue',
    this.loadingWidget,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case AsyncStatus.loading:
        return loadingWidget ?? const _ShimmerSkeleton();
      case AsyncStatus.empty:
        return _EmptyState(
          message: emptyMessage,
          actionLabel: emptyActionLabel,
          onAction: onEmptyAction,
        );
      case AsyncStatus.error:
        return _ErrorState(
          message: errorMessage,
          onRetry: onRetry,
        );
      case AsyncStatus.content:
        return contentBuilder(data as T);
    }
  }
}

// ---------------------------------------------------------------------------
// Shimmer skeleton (loading placeholder)
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
      duration: const Duration(milliseconds: 1200),
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

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _shimmerBox(baseColor, highlightColor, height: 16, widthFactor: 0.6),
              const SizedBox(height: 12),
              _shimmerBox(baseColor, highlightColor, height: 100, widthFactor: 1.0),
              const SizedBox(height: 12),
              _shimmerBox(baseColor, highlightColor, height: 14, widthFactor: 0.8),
              const SizedBox(height: 8),
              _shimmerBox(baseColor, highlightColor, height: 14, widthFactor: 0.5),
              const SizedBox(height: 16),
              _shimmerBox(baseColor, highlightColor, height: 16, widthFactor: 0.4),
              const SizedBox(height: 12),
              _shimmerBox(baseColor, highlightColor, height: 80, widthFactor: 1.0),
            ],
          ),
        );
      },
    );
  }

  Widget _shimmerBox(
    Color baseColor,
    Color highlightColor, {
    required double height,
    required double widthFactor,
  }) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: LinearGradient(
            begin: Alignment(-1.0 + 2.0 * _controller.value, 0),
            end: Alignment(-1.0 + 2.0 * _controller.value + 1.0, 0),
            colors: [baseColor, highlightColor, baseColor],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 56,
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

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _ErrorState({
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 56,
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
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Réessayer'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
