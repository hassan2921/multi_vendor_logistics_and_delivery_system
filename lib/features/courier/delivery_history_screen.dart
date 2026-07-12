import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/formatting.dart';
import '../../core/widgets/async_views.dart';
import '../../core/widgets/status_badge.dart';
import '../../data/models/order.dart';
import 'active_delivery_screen.dart';

final myDeliveriesProvider = FutureProvider.autoDispose((ref) => ref.watch(ordersRepositoryProvider).listMine());

class DeliveryHistoryScreen extends ConsumerWidget {
  const DeliveryHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(myDeliveriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My deliveries'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(myDeliveriesProvider)),
        ],
      ),
      body: ordersAsync.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => const AppListSkeleton(),
        error: (err, _) => AppErrorView(error: err, onRetry: () => ref.invalidate(myDeliveriesProvider)),
        data: (orders) {
          if (orders.isEmpty) {
            return const AppEmptyState(
              icon: Icons.local_shipping_outlined,
              title: 'No deliveries yet',
              subtitle: "You haven't claimed any deliveries yet.",
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _DeliveryCard(order: orders[index]),
          );
        },
      ),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({required this.order});

  final DeliveryOrder order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = order.status != OrderStatus.delivered && order.status != OrderStatus.cancelled;
    final style = orderStatusStyle(order.status);

    return Card(
      child: InkWell(
        onTap: isActive
            ? () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ActiveDeliveryScreen(order: order)),
                )
            : null,
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
                    Text(
                      'Order #${shortOrderId(order.id)}',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    StatusBadge(order.status, compact: true),
                  ],
                ),
              ),
              Text(
                formatMoney(order.totalCents),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (isActive) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
