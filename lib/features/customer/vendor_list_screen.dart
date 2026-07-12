import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_provider.dart';
import '../../core/supabase_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/async_views.dart';
import '../../core/widgets/network_thumbnail.dart';
import '../../data/models/vendor.dart';
import '../shared/notifications_screen.dart';
import 'addresses_screen.dart';
import 'order_cart_screen.dart';
import 'order_history_screen.dart';

/// Search text + category filter, applied server-side.
final vendorSearchProvider = StateProvider<String>((ref) => '');
final vendorCategoryProvider = StateProvider<String?>((ref) => null);

final vendorsListProvider = FutureProvider((ref) {
  final search = ref.watch(vendorSearchProvider);
  final category = ref.watch(vendorCategoryProvider);
  return ref.watch(vendorsRepositoryProvider).listVendors(
        search: search,
        category: category,
        sortByRating: true,
      );
});

class VendorListScreen extends ConsumerWidget {
  const VendorListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendorsAsync = ref.watch(vendorsListProvider);
    final selectedCategory = ref.watch(vendorCategoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vendors near you'),
        actions: [
          const NotificationsBell(),
          IconButton(
            icon: const Icon(Icons.location_on_outlined),
            tooltip: 'My addresses',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddressesScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: 'My orders',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OrderHistoryScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => supabase.auth.signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search vendors',
                isDense: true,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (value) =>
                  ref.read(vendorSearchProvider.notifier).state = value.trim(),
            ),
          ),
          Expanded(
            child: vendorsAsync.when(
              skipLoadingOnReload: true,
              skipLoadingOnRefresh: true,
              loading: () => const AppListSkeleton(),
              error: (err, _) => AppErrorView(
                error: err,
                onRetry: () => ref.invalidate(vendorsListProvider),
              ),
              data: (vendors) {
                // Categories are derived from what's actually on offer.
                final categories = vendors
                    .map((v) => v.category)
                    .whereType<String>()
                    .toSet()
                    .toList()
                  ..sort();

                return Column(
                  children: [
                    if (categories.isNotEmpty || selectedCategory != null)
                      SizedBox(
                        height: 48,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            for (final category in {...categories, ?selectedCategory})
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  label: Text(category),
                                  selected: selectedCategory == category,
                                  onSelected: (selected) => ref
                                      .read(vendorCategoryProvider.notifier)
                                      .state = selected ? category : null,
                                ),
                              ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: vendors.isEmpty
                          ? const AppEmptyState(
                              icon: Icons.storefront_outlined,
                              title: 'No vendors found',
                              subtitle: 'Try a different search or category.',
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: vendors.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 12),
                              itemBuilder: (context, index) => _VendorCard(vendor: vendors[index]),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _VendorCard extends StatelessWidget {
  const _VendorCard({required this.vendor});

  final Vendor vendor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => OrderCartScreen(vendor: vendor)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              NetworkThumbnail(
                url: vendor.imageUrl,
                fallbackIcon: Icons.storefront_rounded,
                size: 56,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vendor.name,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (vendor.address != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        vendor.address!,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (vendor.hasReviews)
                          _RatingPill(avg: vendor.ratingAvg, count: vendor.ratingCount)
                        else
                          _Tag(label: 'New', color: scheme.tertiary),
                        if (vendor.category != null) ...[
                          const SizedBox(width: 8),
                          _Tag(label: vendor.category!, color: scheme.onSurfaceVariant),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.avg, required this.count});

  final double avg;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 14, color: AppColors.amber),
          const SizedBox(width: 3),
          Text(
            '${avg.toStringAsFixed(1)} ($count)',
            style: const TextStyle(
              color: Color(0xFF8A5A00),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}
