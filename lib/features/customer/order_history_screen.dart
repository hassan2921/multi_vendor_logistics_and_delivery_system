import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_provider.dart';
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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load orders: $err')),
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text("You haven't placed any orders yet."));
          }
          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) => _OrderTile(order: orders[index]),
          );
        },
      ),
    );
  }
}

class _OrderTile extends ConsumerWidget {
  const _OrderTile({required this.order});

  final DeliveryOrder order;

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not cancel: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
      title: Text('Order ${order.id.substring(0, 8)}'),
      subtitle: Text(order.status.label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('\$${(order.totalCents / 100).toStringAsFixed(2)}'),
          if (order.isCancellableByCustomer)
            IconButton(
              icon: const Icon(Icons.cancel_outlined),
              tooltip: 'Cancel order',
              onPressed: () => _cancel(context, ref),
            ),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TrackingScreen(orderId: order.id)),
      ),
    );
  }
}
