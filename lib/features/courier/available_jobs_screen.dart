import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_provider.dart';
import '../../core/supabase_client.dart';
import 'active_delivery_screen.dart';

final availableJobsProvider = FutureProvider((ref) => ref.watch(ordersRepositoryProvider).listAvailableJobs());

class AvailableJobsScreen extends ConsumerWidget {
  const AvailableJobsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(availableJobsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Available deliveries'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(availableJobsProvider)),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => supabase.auth.signOut()),
        ],
      ),
      body: jobsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load jobs: $err')),
        data: (jobs) {
          if (jobs.isEmpty) {
            return const Center(child: Text('No deliveries ready for pickup right now.'));
          }
          return ListView.builder(
            itemCount: jobs.length,
            itemBuilder: (context, index) {
              final job = jobs[index];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.local_shipping)),
                title: Text('Order ${(job['id'] as String).substring(0, 8)}'),
                subtitle: Text(job['delivery_address'] as String? ?? 'No address provided'),
                trailing: FilledButton(
                  onPressed: () async {
                    final order = await ref.read(ordersRepositoryProvider).claimDelivery(job['id'] as String);
                    if (context.mounted) {
                      ref.invalidate(availableJobsProvider);
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => ActiveDeliveryScreen(order: order)),
                      );
                    }
                  },
                  child: const Text('Claim'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
