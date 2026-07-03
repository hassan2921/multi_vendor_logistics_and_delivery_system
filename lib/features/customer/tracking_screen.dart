import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../auth/auth_provider.dart';
import '../../data/models/location_ping.dart';
import '../../data/models/order.dart';

class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  String? _deliveryId;

  @override
  void initState() {
    super.initState();
    ref.read(deliveriesRepositoryProvider).getDeliveryIdForOrder(widget.orderId).then((id) {
      if (mounted) setState(() => _deliveryId = id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(_orderStreamProvider(widget.orderId));

    return Scaffold(
      appBar: AppBar(title: const Text('Track your order')),
      body: Column(
        children: [
          orderAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (err, _) => Text('Error: $err'),
            data: (order) => order == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      order.status.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
          ),
          Expanded(
            child: _deliveryId == null
                ? const Center(child: CircularProgressIndicator())
                : _LiveMap(deliveryId: _deliveryId!),
          ),
        ],
      ),
    );
  }
}

final _orderStreamProvider = StreamProvider.family<DeliveryOrder?, String>((ref, orderId) {
  return ref.watch(ordersRepositoryProvider).watchOrder(orderId);
});

final _pingStreamProvider = StreamProvider.family<LocationPing?, String>((ref, deliveryId) {
  return ref.watch(deliveriesRepositoryProvider).watchLatestPing(deliveryId);
});

class _LiveMap extends ConsumerStatefulWidget {
  const _LiveMap({required this.deliveryId});

  final String deliveryId;

  @override
  ConsumerState<_LiveMap> createState() => _LiveMapState();
}

class _LiveMapState extends ConsumerState<_LiveMap> {
  static const _fallbackCenter = LatLng(37.7749, -122.4194);

  GoogleMapController? _mapController;

  @override
  Widget build(BuildContext context) {
    // Recenters the camera every time a new (throttled/batched) courier
    // ping arrives via Supabase Realtime.
    ref.listen(_pingStreamProvider(widget.deliveryId), (previous, next) {
      final ping = next.valueOrNull;
      if (ping != null && _mapController != null) {
        _mapController!.animateCamera(CameraUpdate.newLatLng(LatLng(ping.lat, ping.lng)));
      }
    });

    final ping = ref.watch(_pingStreamProvider(widget.deliveryId)).valueOrNull;
    final position = ping == null ? _fallbackCenter : LatLng(ping.lat, ping.lng);

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: position, zoom: 14),
      onMapCreated: (controller) => _mapController = controller,
      markers: ping == null
          ? {}
          : {
              Marker(
                markerId: const MarkerId('courier'),
                position: position,
                infoWindow: const InfoWindow(title: 'Your courier'),
              ),
            },
    );
  }
}
