import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/formatting.dart';
import '../../core/widgets/async_views.dart';
import '../../data/models/courier_earnings.dart';

final courierEarningsProvider =
    FutureProvider.autoDispose((ref) => ref.watch(couriersRepositoryProvider).getEarnings());

class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final earningsAsync = ref.watch(courierEarningsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My earnings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(courierEarningsProvider),
          ),
        ],
      ),
      body: earningsAsync.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => const AppLoading(),
        error: (err, _) => AppErrorView(error: err, onRetry: () => ref.invalidate(courierEarningsProvider)),
        data: (earnings) {
          final count = earnings.deliveries.length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _EarningsHero(totalCents: earnings.totalCents, deliveryCount: count),
              const SizedBox(height: 20),
              if (earnings.deliveries.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Text(
                    'Complete deliveries to start earning.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                )
              else ...[
                Text(
                  'Recent payouts',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                for (final entry in earnings.deliveries) ...[
                  _EarningCard(entry: entry),
                  const SizedBox(height: 12),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _EarningsHero extends StatelessWidget {
  const _EarningsHero({required this.totalCents, required this.deliveryCount});

  final int totalCents;
  final int deliveryCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.coral, AppColors.amber],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.coral.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total earned',
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 6),
          Text(
            formatMoney(totalCents),
            style: theme.textTheme.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '$deliveryCount paid deliver${deliveryCount == 1 ? 'y' : 'ies'}',
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
          ),
        ],
      ),
    );
  }
}

class _EarningCard extends StatelessWidget {
  const _EarningCard({required this.entry});

  final EarningEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [
      if (entry.distanceKm != null) '${entry.distanceKm!.toStringAsFixed(1)} km',
      if (entry.deliveredAt != null) entry.deliveredAt!.toLocal().toString().substring(0, 16),
    ].join('  ·  ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.payments_rounded, color: AppColors.success),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order #${shortOrderId(entry.orderId)}',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            Text(
              formatMoney(entry.payoutCents),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800, color: AppColors.success),
            ),
          ],
        ),
      ),
    );
  }
}
