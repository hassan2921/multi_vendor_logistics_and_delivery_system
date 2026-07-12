import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/async_views.dart';
import '../../core/widgets/rating_stars.dart';
import '../../data/models/review.dart';
import '../../data/models/vendor.dart';

// autoDispose: a plain .family caches one entry per vendor ever visited,
// growing for the whole session.
final _vendorReviewsProvider = FutureProvider.autoDispose.family<List<Review>, String>(
  (ref, vendorId) => ref.watch(vendorsRepositoryProvider).listReviews(vendorId),
);

class VendorReviewsScreen extends ConsumerWidget {
  const VendorReviewsScreen({super.key, required this.vendor});

  final Vendor vendor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(_vendorReviewsProvider(vendor.id));

    return Scaffold(
      appBar: AppBar(title: Text('${vendor.name} — reviews')),
      body: reviewsAsync.when(
        loading: () => const AppListSkeleton(),
        error: (err, _) => AppErrorView(
          error: err,
          onRetry: () => ref.invalidate(_vendorReviewsProvider(vendor.id)),
        ),
        data: (reviews) {
          if (reviews.isEmpty) {
            return const AppEmptyState(
              icon: Icons.reviews_outlined,
              title: 'No reviews yet',
              subtitle: 'Be the first to order and leave a review!',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: reviews.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == 0) return _RatingSummary(vendor: vendor, reviewCount: reviews.length);
              return _ReviewCard(review: reviews[index - 1]);
            },
          );
        },
      ),
    );
  }
}

class _RatingSummary extends StatelessWidget {
  const _RatingSummary({required this.vendor, required this.reviewCount});

  final Vendor vendor;
  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vendor.ratingAvg.toStringAsFixed(1),
                  style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                RatingStars(vendor.ratingAvg, size: 18),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                '$reviewCount review${reviewCount == 1 ? '' : 's'}',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${review.rating}',
                    style: const TextStyle(color: Color(0xFF8A5A00), fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 12),
                RatingStars(review.rating.toDouble()),
              ],
            ),
            if (review.comment != null) ...[
              const SizedBox(height: 12),
              Text(review.comment!, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}
