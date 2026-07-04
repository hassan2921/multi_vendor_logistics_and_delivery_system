import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_provider.dart';
import '../../core/supabase_client.dart';
import '../../data/models/order.dart';
import 'menu_management_screen.dart';
import 'order_detail_screen.dart';

/// Realtime-subscribed: new orders and status changes for this vendor show
/// up immediately without polling.
final _vendorOrdersProvider = StreamProvider.autoDispose<List<DeliveryOrder>>((ref) async* {
  final appUser = await ref.watch(currentAppUserProvider.future);
  if (appUser == null) {
    yield [];
    return;
  }

  final vendorRow = await supabase.from('vendors').select('id').eq('owner_user_id', appUser.id).maybeSingle();
  final vendorId = vendorRow?['id'] as String?;
  if (vendorId == null) {
    yield [];
    return;
  }

  yield* ref.watch(ordersRepositoryProvider).watchVendorOrders(vendorId);
});

class IncomingOrdersScreen extends ConsumerWidget {
  const IncomingOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(_vendorOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Incoming orders'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restaurant_menu),
            tooltip: 'Manage menu',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MenuManagementScreen()),
            ),
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => supabase.auth.signOut()),
        ],
      ),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load orders: $err')),
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text('No orders yet.'));
          }
          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
                title: Text('Order ${order.id.substring(0, 8)}'),
                subtitle: Text(order.status.label),
                trailing: Text('\$${(order.totalCents / 100).toStringAsFixed(2)}'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => OrderDetailScreen(order: order)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
