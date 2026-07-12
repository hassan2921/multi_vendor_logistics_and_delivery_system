import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_provider.dart';
import '../../core/supabase_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/formatting.dart';
import '../../core/widgets/async_views.dart';
import '../../core/widgets/status_badge.dart';
import '../../data/models/order.dart';
import '../shared/notifications_screen.dart';
import 'menu_management_screen.dart';
import 'order_detail_screen.dart';
import 'payouts_screen.dart';
import 'vendor_state_provider.dart';

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

/// Lets the vendor edit their storefront profile (name, address, cover
/// photo). This is the only way an *existing* vendor can set a photo, since
/// onboarding runs once.
Future<void> _showEditStorefrontDialog(BuildContext context, WidgetRef ref) async {
  final vendor = ref.read(myVendorProvider).valueOrNull;
  final nameController = TextEditingController(text: vendor?.name ?? '');
  final addressController = TextEditingController(text: vendor?.address ?? '');
  final imageUrlController = TextEditingController(text: vendor?.imageUrl ?? '');

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Edit storefront'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Storefront name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: imageUrlController,
              decoration: const InputDecoration(
                labelText: 'Cover photo URL',
                helperText: 'Leave empty to remove the photo',
              ),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save')),
      ],
    ),
  );

  if (saved != true) return;
  final name = nameController.text.trim();
  if (name.isEmpty) return;

  try {
    await ref.read(vendorsRepositoryProvider).updateMyVendor(
          name: name,
          address: addressController.text.trim().isEmpty ? null : addressController.text.trim(),
          // Empty string = clear the photo (repo sends explicit null).
          imageUrl: imageUrlController.text.trim(),
        );
    ref.invalidate(myVendorProvider);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not update storefront: ${friendlyError(e)}')));
    }
  }
}

class IncomingOrdersScreen extends ConsumerWidget {
  const IncomingOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(_vendorOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Incoming orders'),
        actions: [
          const NotificationsBell(),
          IconButton(
            icon: const Icon(Icons.storefront_outlined),
            tooltip: 'Edit storefront',
            onPressed: () => _showEditStorefrontDialog(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.restaurant_menu),
            tooltip: 'Manage menu',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MenuManagementScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            tooltip: 'Payouts',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PayoutsScreen()),
            ),
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => supabase.auth.signOut()),
        ],
      ),
      body: ordersAsync.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => const AppListSkeleton(),
        error: (err, _) => AppErrorView(error: err),
        data: (orders) {
          if (orders.isEmpty) {
            return const AppEmptyState(
              icon: Icons.inbox_rounded,
              title: 'No orders yet',
              subtitle: 'New orders will appear here the moment they come in.',
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

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final DeliveryOrder order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = orderStatusStyle(order.status);

    return Card(
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => OrderDetailScreen(order: order)),
        ),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMoney(order.totalCents),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
