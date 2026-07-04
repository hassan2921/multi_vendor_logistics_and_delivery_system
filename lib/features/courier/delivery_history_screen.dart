import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_provider.dart';
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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load deliveries: $err')),
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text("You haven't claimed any deliveries yet."));
          }
          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              final isActive = order.status != OrderStatus.delivered && order.status != OrderStatus.cancelled;
              return ListTile(
                leading: Icon(isActive ? Icons.local_shipping : Icons.check_circle_outline),
                title: Text('Order ${order.id.substring(0, 8)}'),
                subtitle: Text(order.status.label),
                trailing: Text('\$${(order.totalCents / 100).toStringAsFixed(2)}'),
                onTap: isActive
                    ? () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => ActiveDeliveryScreen(order: order)),
                        )
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}
