import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../auth/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/formatting.dart';
import '../../core/widgets/async_views.dart';
import '../../core/widgets/status_badge.dart';
import '../../data/models/order.dart';
import 'location_service.dart';

class ActiveDeliveryScreen extends ConsumerStatefulWidget {
  const ActiveDeliveryScreen({super.key, required this.order});

  final DeliveryOrder order;

  @override
  ConsumerState<ActiveDeliveryScreen> createState() => _ActiveDeliveryScreenState();
}

class _ActiveDeliveryScreenState extends ConsumerState<ActiveDeliveryScreen> with WidgetsBindingObserver {
  LocationThrottleService? _locationService;
  OrderStatus _status = OrderStatus.courierAssigned;
  bool _isSharingLocation = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _status = widget.order.status;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _locationService?.handleAppLifecycleState(state);
  }

  Future<void> _startSharingLocation() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      final requested = await Geolocator.requestPermission();
      if (requested == LocationPermission.denied || requested == LocationPermission.deniedForever) {
        setState(() => _error = 'Location permission is required to share your position.');
        return;
      }
    }

    final deliveriesRepo = ref.read(deliveriesRepositoryProvider);
    final deliveryId = await deliveriesRepo.getDeliveryIdForOrder(widget.order.id);
    if (deliveryId == null) return;

    final courierId = ref.read(currentAppUserProvider).valueOrNull?.id;
    if (courierId == null) return;

    _locationService = LocationThrottleService(
      deliveryId: deliveryId,
      courierId: courierId,
      onBatchReady: deliveriesRepo.insertLocationPings,
    );
    await _locationService!.start();
    setState(() => _isSharingLocation = true);
  }

  Future<void> _advanceStatus(OrderStatus next) async {
    try {
      final updated = await ref.read(ordersRepositoryProvider).updateStatus(widget.order.id, next);
      setState(() {
        _status = updated.status;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationService?.stop();
    super.dispose();
  }

  /// The courier's next action for the current status, if any.
  (OrderStatus, String)? get _nextAction {
    switch (_status) {
      case OrderStatus.courierAssigned:
        return (OrderStatus.pickedUp, 'Mark picked up');
      case OrderStatus.pickedUp:
        return (OrderStatus.inTransit, 'Start delivering');
      case OrderStatus.inTransit:
        return (OrderStatus.delivered, 'Mark delivered');
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = _nextAction;

    return Scaffold(
      appBar: AppBar(title: Text('Order #${shortOrderId(widget.order.id)}')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StatusBadge(_status),
                        if (widget.order.deliveryAddress != null) ...[
                          const Divider(height: 24),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.location_on_outlined,
                                  size: 20, color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Deliver to',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                                    const SizedBox(height: 2),
                                    Text(widget.order.deliveryAddress!, style: theme.textTheme.bodyLarge),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  InlineError(_error!),
                  const SizedBox(height: 16),
                ],
                if (!_isSharingLocation)
                  FilledButton.icon(
                    onPressed: _startSharingLocation,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Start sharing my location'),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      foregroundColor: theme.colorScheme.onSecondaryContainer,
                    ),
                  )
                else
                  Card(
                    child: ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.location_on_rounded, color: AppColors.success),
                      ),
                      title: const Text('Sharing location'),
                      subtitle: const Text('Batched every 10s or 5 points, whichever comes first'),
                    ),
                  ),
              ],
            ),
          ),
          _ActionBar(next: next, onAdvance: _advanceStatus),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.next, required this.onAdvance});

  final (OrderStatus, String)? next;
  final ValueChanged<OrderStatus> onAdvance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: next == null
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 20, color: AppColors.success),
                    const SizedBox(width: 8),
                    Text('Delivery complete',
                        style: theme.textTheme.titleMedium?.copyWith(color: AppColors.success)),
                  ],
                )
              : FilledButton(
                  onPressed: () => onAdvance(next!.$1),
                  child: Text(next!.$2),
                ),
        ),
      ),
    );
  }
}
