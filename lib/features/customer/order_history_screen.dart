import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/formatting.dart';
import '../../core/widgets/async_views.dart';
import '../../core/widgets/status_badge.dart';
import '../../data/models/order.dart';
import 'tracking_screen.dart';

final myOrdersProvider = FutureProvider.autoDispose((ref) => ref.watch(ordersRepositoryProvider).listMine());

class OrderHistoryScreen extends ConsumerWidget {
  const OrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(myOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My orders'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(myOrdersProvider)),
        ],
      ),
      body: ordersAsync.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => const AppListSkeleton(),
        error: (err, _) => AppErrorView(error: err, onRetry: () => ref.invalidate(myOrdersProvider)),
        data: (orders) {
          if (orders.isEmpty) {
            return const AppEmptyState(
              icon: Icons.receipt_long_rounded,
              title: 'No orders yet',
              subtitle: "You haven't placed any orders yet. When you do, they'll show up here.",
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _OrderCard(order: orders[index]),
          );
        },
      ),
    );
  }
}

class _OrderCard extends ConsumerWidget {
  const _OrderCard({required this.order});

  final DeliveryOrder order;

  Future<void> _rate(BuildContext context, WidgetRef ref) async {
    var rating = 5;
    final commentController = TextEditingController();

    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rate your order'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (i) => IconButton(
                    icon: Icon(
                      i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: AppColors.amber,
                      size: 32,
                    ),
                    onPressed: () => setDialogState(() => rating = i + 1),
                  ),
                ),
              ),
              TextField(
                controller: commentController,
                decoration: const InputDecoration(labelText: 'Comment (optional)'),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Submit')),
          ],
        ),
      ),
    );
    if (submitted != true) return;

    try {
      final comment = commentController.text.trim();
      await ref.read(ordersRepositoryProvider).submitReview(
            order.id,
            rating: rating,
            comment: comment.isEmpty ? null : comment,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks for your review!')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not submit review: ${friendlyError(e)}')));
      }
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: const Text('If it was already paid, a refund will be issued automatically.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep order')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Cancel order')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(ordersRepositoryProvider).cancelOrder(order.id);
      ref.invalidate(myOrdersProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not cancel: ${friendlyError(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final style = orderStatusStyle(order.status);
    final canRate = order.status == OrderStatus.delivered;
    final canCancel = order.isCancellableByCustomer;

    return Card(
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TrackingScreen(orderId: order.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
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
                ],
              ),
              if (canRate || canCancel) ...[
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (canRate)
                      TextButton.icon(
                        onPressed: () => _rate(context, ref),
                        icon: const Icon(Icons.star_outline_rounded, size: 18),
                        label: const Text('Rate'),
                      ),
                    if (canCancel)
                      TextButton.icon(
                        onPressed: () => _cancel(context, ref),
                        icon: const Icon(Icons.cancel_outlined, size: 18),
                        label: const Text('Cancel'),
                        style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
