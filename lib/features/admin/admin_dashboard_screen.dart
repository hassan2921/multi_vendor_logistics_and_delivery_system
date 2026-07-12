import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_provider.dart';
import '../../core/supabase_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/formatting.dart';
import '../../core/widgets/async_views.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/status_badge.dart';
import '../../data/models/order.dart';
import '../../data/models/vendor.dart';

// Not autoDispose: the four tabs live in a TabBarView, so caching each result
// keeps a revisited tab instant instead of re-running the fetch (which would
// flash the loading skeleton every time you switch back). RefreshIndicator /
// the refresh buttons still invalidate to pull fresh data.
final _metricsProvider = FutureProvider((ref) => ref.watch(adminRepositoryProvider).getMetrics());
final _pendingVendorsProvider =
    FutureProvider((ref) => ref.watch(adminRepositoryProvider).listVendors(status: 'pending'));
final _recentOrdersProvider =
    FutureProvider((ref) => ref.watch(adminRepositoryProvider).listOrders());
final _promosProvider =
    FutureProvider((ref) => ref.watch(adminRepositoryProvider).listPromoCodes());

/// Back-office console: platform metrics, vendor approval queue, recent
/// orders, and promo code management.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin console'),
          actions: [
            IconButton(icon: const Icon(Icons.logout), onPressed: () => supabase.auth.signOut()),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Vendors'),
              Tab(text: 'Orders'),
              Tab(text: 'Promos'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_OverviewTab(), _VendorsTab(), _OrdersTab(), _PromosTab()],
        ),
      ),
    );
  }
}

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(_metricsProvider);

    return metricsAsync.when(
      loading: () => const AppLoading(),
      error: (err, _) => AppErrorView(error: err, onRetry: () => ref.invalidate(_metricsProvider)),
      data: (m) {
        final cards = <Widget>[
          StatCard(label: 'Total orders', value: '${m.ordersTotal}', icon: Icons.receipt_long_rounded),
          StatCard(
              label: 'Delivered',
              value: '${m.ordersDelivered}',
              icon: Icons.task_alt_rounded,
              color: AppColors.success),
          StatCard(
              label: 'Cancelled',
              value: '${m.ordersCancelled}',
              icon: Icons.cancel_rounded,
              color: AppColors.error),
          StatCard(
              label: 'GMV',
              value: formatMoney(m.gmvCents),
              icon: Icons.payments_rounded,
              color: AppColors.info),
          StatCard(
              label: 'Platform fees',
              value: formatMoney(m.platformFeesCents),
              icon: Icons.account_balance_rounded,
              color: AppColors.amber),
          StatCard(
              label: 'Vendors awaiting approval',
              value: '${m.vendorsPendingApproval}',
              icon: Icons.storefront_rounded,
              color: AppColors.warning),
          StatCard(
              label: 'Couriers online',
              value: '${m.activeCouriers}',
              icon: Icons.local_shipping_rounded,
              color: AppColors.success),
        ];
        final tt = Theme.of(context).textTheme;
        final scaler = MediaQuery.textScalerOf(context);
        // A single uniform cell height that fits a two-line label at any system
        // font scale — so every card is identical and none can clip.
        final valueH = scaler.scale(tt.headlineSmall?.fontSize ?? 24) * 1.25;
        final labelH = scaler.scale(tt.bodySmall?.fontSize ?? 12) * 1.35;
        final cellHeight = 32 + 36 + 12 + valueH + 4 + labelH * 2 + 8;
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(_metricsProvider),
          child: GridView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: cellHeight,
            ),
            children: cards,
          ),
        );
      },
    );
  }
}

class _VendorsTab extends ConsumerWidget {
  const _VendorsTab();

  Future<void> _setApproval(WidgetRef ref, Vendor vendor, String status) async {
    await ref.read(adminRepositoryProvider).setVendorApproval(vendor.id, status);
    ref.invalidate(_pendingVendorsProvider);
    ref.invalidate(_metricsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendorsAsync = ref.watch(_pendingVendorsProvider);

    return vendorsAsync.when(
      loading: () => const AppListSkeleton(),
      error: (err, _) => AppErrorView(error: err, onRetry: () => ref.invalidate(_pendingVendorsProvider)),
      data: (vendors) {
        if (vendors.isEmpty) {
          return const AppEmptyState(
            icon: Icons.verified_rounded,
            title: 'All caught up',
            subtitle: 'No vendors are awaiting approval.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: vendors.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final vendor = vendors[index];
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
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.storefront_rounded, color: theme.colorScheme.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(vendor.name,
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(vendor.address ?? 'No address',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _setApproval(ref, vendor, 'rejected'),
                            icon: const Icon(Icons.close_rounded, size: 18),
                            label: const Text('Reject'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.colorScheme.error,
                              minimumSize: const Size(0, 44),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _setApproval(ref, vendor, 'approved'),
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text('Approve'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.success,
                              minimumSize: const Size(0, 44),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _OrdersTab extends ConsumerWidget {
  const _OrdersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(_recentOrdersProvider);

    return ordersAsync.when(
      loading: () => const AppListSkeleton(),
      error: (err, _) => AppErrorView(error: err, onRetry: () => ref.invalidate(_recentOrdersProvider)),
      data: (orders) {
        if (orders.isEmpty) {
          return const AppEmptyState(
            icon: Icons.receipt_long_rounded,
            title: 'No orders yet',
            subtitle: 'Orders across the platform will appear here.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(_recentOrdersProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final DeliveryOrder order = orders[index];
              final theme = Theme.of(context);
              final style = orderStatusStyle(order.status);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: style.color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(style.icon, color: style.color, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Order #${shortOrderId(order.id)}',
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            StatusBadge(order.status, compact: true),
                          ],
                        ),
                      ),
                      Text(
                        formatMoney(order.totalCents),
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _PromosTab extends ConsumerWidget {
  const _PromosTab();

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final codeController = TextEditingController();
    final valueController = TextEditingController();
    var discountType = 'percent';

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New promo code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Code'),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'percent', label: Text('% off')),
                  ButtonSegment(value: 'fixed', label: Text('¢ off')),
                ],
                selected: {discountType},
                onSelectionChanged: (s) => setDialogState(() => discountType = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valueController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: discountType == 'percent' ? 'Percent (1–100)' : 'Amount in cents',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Create')),
          ],
        ),
      ),
    );

    if (created != true) return;
    final code = codeController.text.trim();
    final value = int.tryParse(valueController.text.trim());
    if (code.isEmpty || value == null || value <= 0) return;

    try {
      await ref.read(adminRepositoryProvider).createPromoCode(
            code: code,
            discountType: discountType,
            discountValue: value,
          );
      ref.invalidate(_promosProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not create promo: ${friendlyError(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promosAsync = ref.watch(_promosProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New promo'),
      ),
      body: promosAsync.when(
        loading: () => const AppListSkeleton(),
        error: (err, _) => AppErrorView(error: err, onRetry: () => ref.invalidate(_promosProvider)),
        data: (promos) {
          if (promos.isEmpty) {
            return const AppEmptyState(
              icon: Icons.local_offer_outlined,
              title: 'No promo codes',
              subtitle: 'Tap "New promo" to create your first discount code.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: promos.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final promo = promos[index];
              final type = promo['discount_type'] as String;
              final value = promo['discount_value'] as int;
              final isActive = promo['is_active'] as bool? ?? true;
              final theme = Theme.of(context);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: AppColors.amber.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.local_offer_rounded, color: AppColors.amber),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(promo['code'] as String,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                )),
                            const SizedBox(height: 2),
                            Text(
                              '${type == 'percent' ? '$value% off' : '${formatMoney(value)} off'}'
                              '  ·  used ${promo['redemption_count']} time(s)',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: (isActive ? AppColors.success : theme.colorScheme.onSurfaceVariant)
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          isActive ? 'active' : 'inactive',
                          style: TextStyle(
                            color: isActive ? AppColors.success : theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
