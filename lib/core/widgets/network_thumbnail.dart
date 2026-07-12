import 'package:flutter/material.dart';

/// A rounded network image with a loading shimmer and a graceful icon
/// fallback when [url] is null or fails to load — used anywhere a
/// product/vendor photo is optional.
class NetworkThumbnail extends StatelessWidget {
  const NetworkThumbnail({
    super.key,
    required this.url,
    required this.fallbackIcon,
    this.size = 64,
    this.radius = 14,
  });

  final String? url;
  final IconData fallbackIcon;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(radius);

    Widget placeholder() => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.10),
            borderRadius: borderRadius,
          ),
          child: Icon(fallbackIcon, color: scheme.primary, size: size * 0.44),
        );

    final imageUrl = url;
    if (imageUrl == null || imageUrl.isEmpty) return placeholder();

    return ClipRRect(
      borderRadius: borderRadius,
      child: Image.network(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => placeholder(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            width: size,
            height: size,
            color: scheme.surfaceContainerHighest,
            child: Center(
              child: SizedBox(
                width: size * 0.3,
                height: size * 0.3,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                      : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
