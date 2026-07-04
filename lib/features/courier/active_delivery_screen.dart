import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../auth/auth_provider.dart';
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
    final updated = await ref.read(ordersRepositoryProvider).updateStatus(widget.order.id, next);
    setState(() => _status = updated.status);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationService?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Order ${widget.order.id.substring(0, 8)}')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Status: ${_status.label}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 24),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (!_isSharingLocation)
              FilledButton.icon(
                onPressed: _startSharingLocation,
                icon: const Icon(Icons.my_location),
                label: const Text('Start sharing my location'),
              )
            else
              const ListTile(
                leading: Icon(Icons.location_on, color: Colors.green),
                title: Text('Sharing location'),
                subtitle: Text('Batched every 10s or 5 points, whichever comes first'),
              ),
            const SizedBox(height: 24),
            if (_status == OrderStatus.courierAssigned)
              OutlinedButton(
                onPressed: () => _advanceStatus(OrderStatus.pickedUp),
                child: const Text('Mark picked up'),
              ),
            if (_status == OrderStatus.pickedUp)
              OutlinedButton(
                onPressed: () => _advanceStatus(OrderStatus.inTransit),
                child: const Text('Start delivering'),
              ),
            if (_status == OrderStatus.inTransit)
              FilledButton(
                onPressed: () => _advanceStatus(OrderStatus.delivered),
                child: const Text('Mark delivered'),
              ),
          ],
        ),
      ),
    );
  }
}
