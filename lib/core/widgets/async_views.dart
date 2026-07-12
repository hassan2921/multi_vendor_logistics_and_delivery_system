import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/formatting.dart';

/// Shared presentation for the three non-happy async states — loading, error,
/// and empty — so every screen renders them consistently instead of the old
/// `Center(CircularProgressIndicator())` / raw `Text('$err')` pattern.

/// Delays showing [child] until [delay] elapses.
///
/// A provider's `loading:` widget is only mounted while it's actually loading,
/// so any load that resolves before [delay] unmounts this before the timer
/// fires — the placeholder never appears. That means fast loads (the common
/// case) skip the loading flash entirely, and only genuinely slow loads reveal
/// the skeleton/spinner. This is what stops the brief "tiles" flash on
/// navigation and tab switches across the app.
class DeferredLoading extends StatefulWidget {
  const DeferredLoading({
    super.key,
    required this.child,
    this.delay = const Duration(milliseconds: 300),
  });

  final Widget child;
  final Duration delay;

  @override
  State<DeferredLoading> createState() => _DeferredLoadingState();
}

class _DeferredLoadingState extends State<DeferredLoading> {
  bool _show = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _show ? widget.child : const SizedBox.shrink();
}

/// A single shimmering placeholder block.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 16, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Wraps [child] in an animated left-to-right shimmer sweep. Use around
/// [SkeletonBox] placeholders.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest;
    final highlight = Color.alphaBlend(scheme.surface.withValues(alpha: 0.6), base);

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [base, highlight, base],
            stops: [
              (t - 0.3).clamp(0.0, 1.0),
              t.clamp(0.0, 1.0),
              (t + 0.3).clamp(0.0, 1.0),
            ],
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}

/// A shimmering list of card-shaped placeholders — the default loading state
/// for list/feed screens.
class AppListSkeleton extends StatelessWidget {
  const AppListSkeleton({super.key, this.itemCount = 6, this.padding});

  final int itemCount;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => DeferredLoading(child: _skeleton(context));

  Widget _skeleton(BuildContext context) {
    return Shimmer(
      child: ListView.separated(
        padding: padding ?? const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, _) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const SkeletonBox(width: 48, height: 48, radius: 12),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonBox(width: 140, height: 14),
                    SizedBox(height: 10),
                    SkeletonBox(width: 90, height: 12),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              const SkeletonBox(width: 48, height: 14),
            ],
          ),
        ),
      ),
    );
  }
}

/// Centered spinner — for screens where a list skeleton doesn't fit (maps,
/// full-screen gates).
class AppLoading extends StatelessWidget {
  const AppLoading({super.key});

  @override
  Widget build(BuildContext context) =>
      const DeferredLoading(child: Center(child: CircularProgressIndicator()));
}

/// Friendly error state with an icon and an optional retry action.
class AppErrorView extends StatelessWidget {
  const AppErrorView({super.key, required this.error, this.onRetry, this.title});

  final Object error;
  final VoidCallback? onRetry;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: scheme.error),
            const SizedBox(height: 16),
            Text(
              title ?? 'Something went wrong',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              friendlyError(error),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Friendly empty state with an icon, title, optional subtitle and action.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: scheme.primary),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A compact inline error banner for form submissions — pass an already
/// human-friendly message (e.g. `friendlyError(err)`).
class InlineError extends StatelessWidget {
  const InlineError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 20, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders an [AsyncValue] with the shared loading/error/empty/data views.
/// Keeps stale data visible across refreshes to avoid spinner flicker.
extension AsyncValueUi<T> on AsyncValue<T> {
  Widget viewWhen({
    required Widget Function(T value) data,
    Widget? loading,
    VoidCallback? onRetry,
    String? errorTitle,
  }) {
    return when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      data: data,
      loading: () => loading ?? const AppListSkeleton(),
      error: (err, _) => AppErrorView(error: err, onRetry: onRetry, title: errorTitle),
    );
  }
}
