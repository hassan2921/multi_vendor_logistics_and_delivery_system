import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_provider.dart';
import '../../core/supabase_client.dart';
import '../../data/models/vendor.dart';
import 'order_cart_screen.dart';

final vendorsListProvider = FutureProvider((ref) => ref.watch(vendorsRepositoryProvider).listVendors());

class VendorListScreen extends ConsumerWidget {
  const VendorListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendorsAsync = ref.watch(vendorsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vendors near you'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => supabase.auth.signOut(),
          ),
        ],
      ),
      body: vendorsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load vendors: $err')),
        data: (vendors) {
          if (vendors.isEmpty) {
            return const Center(child: Text('No vendors available yet.'));
          }
          return ListView.builder(
            itemCount: vendors.length,
            itemBuilder: (context, index) => _VendorTile(vendor: vendors[index]),
          );
        },
      ),
    );
  }
}

class _VendorTile extends StatelessWidget {
  const _VendorTile({required this.vendor});

  final Vendor vendor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.storefront)),
      title: Text(vendor.name),
      subtitle: vendor.address != null ? Text(vendor.address!) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OrderCartScreen(vendor: vendor)),
      ),
    );
  }
}
