import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../auth/auth_provider.dart';
import '../../core/supabase_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/formatting.dart';
import '../../core/widgets/async_views.dart';
import '../shared/notifications_screen.dart';
import 'active_delivery_screen.dart';
import 'delivery_history_screen.dart';
import 'earnings_screen.dart';

final availableJobsProvider = FutureProvider((ref) => ref.watch(ordersRepositoryProvider).listAvailableJobs());

/// Whether this courier is opted into auto-dispatch. Local state only; the
/// backend is updated on every toggle.
final courierAvailableProvider = StateProvider<bool>((ref) => false);

class AvailableJobsScreen extends ConsumerWidget {
  const AvailableJobsScreen({super.key});

  Future<void> _toggleAvailability(BuildContext context, WidgetRef ref, bool isAvailable) async {
    ref.read(courierAvailableProvider.notifier).state = isAvailable;

    double? lat;
    double? lng;
    if (isAvailable) {
      // Best-effort position so dispatch can rank by distance; going
      // available without location still works (backend just won't
      // auto-assign until a location ping arrives).
      try {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          await Geolocator.requestPermission();
        }
        final position = await Geolocator.getCurrentPosition();
        lat = position.latitude;
        lng = position.longitude;
      } catch (_) {}
    }

    try {
      await ref
          .read(couriersRepositoryProvider)
          .setAvailability(isAvailable: isAvailable, lat: lat, lng: lng);
    } catch (e) {
      ref.read(courierAvailableProvider.notifier).state = !isAvailable;
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not update availability: ${friendlyError(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(availableJobsProvider);
    final isAvailable = ref.watch(courierAvailableProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Available deliveries'),
        actions: [
          const NotificationsBell(),
          IconButton(
            icon: const Icon(Icons.payments_outlined),
            tooltip: 'My earnings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EarningsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'My deliveries',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DeliveryHistoryScreen()),
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(availableJobsProvider)),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => supabase.auth.signOut()),
        ],
      ),
      body: Column(
        children: [
          _AvailabilityCard(
            isAvailable: isAvailable,
            onChanged: (value) => _toggleAvailability(context, ref, value),
          ),
          Expanded(
            child: jobsAsync.when(
              skipLoadingOnReload: true,
              skipLoadingOnRefresh: true,
              loading: () => const AppListSkeleton(),
              error: (err, _) => AppErrorView(error: err, onRetry: () => ref.invalidate(availableJobsProvider)),
              data: (jobs) {
                if (jobs.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.local_shipping_outlined,
                    title: 'No deliveries right now',
                    subtitle: 'No orders are ready for pickup. Pull to refresh or check back soon.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: jobs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final job = jobs[index];
                    return _JobCard(
                      orderId: job['id'] as String,
                      address: job['delivery_address'] as String?,
                      onClaim: () async {
                        final order =
                            await ref.read(ordersRepositoryProvider).claimDelivery(job['id'] as String);
                        if (context.mounted) {
                          ref.invalidate(availableJobsProvider);
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => ActiveDeliveryScreen(order: order)),
                          );
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailabilityCard extends StatelessWidget {
  const _AvailabilityCard({required this.isAvailable, required this.onChanged});

  final bool isAvailable;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = isAvailable ? AppColors.success : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(isAvailable ? Icons.bolt_rounded : Icons.bolt_outlined, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAvailable ? "You're online" : "You're offline",
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      isAvailable
                          ? 'Nearby ready orders are assigned to you automatically'
                          : 'You can still claim jobs from the list below',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Switch(value: isAvailable, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.orderId, required this.address, required this.onClaim});

  final String orderId;
  final String? address;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.local_shipping_rounded, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order #${shortOrderId(orderId)}',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    address ?? 'No address provided',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: onClaim,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: const Text('Claim'),
            ),
          ],
        ),
      ),
    );
  }
}
