import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../auth/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/async_views.dart';
import '../../core/widgets/order_status_timeline.dart';
import '../../core/widgets/status_badge.dart';
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
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Track your order')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 280,
              child: _deliveryId == null
                  ? Container(
                      color: scheme.surfaceContainerHighest,
                      child: const Center(child: CircularProgressIndicator()),
                    )
                  : _LiveMap(deliveryId: _deliveryId!),
            ),
          ),
          const SizedBox(height: 16),
          orderAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => AppErrorView(error: err),
            data: (order) {
              if (order == null) return const SizedBox.shrink();
              return Column(
                children: [
                  _StatusHeaderCard(order: order),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Order progress',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 20),
                          OrderStatusTimeline(order.status),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatusHeaderCard extends StatelessWidget {
  const _StatusHeaderCard({required this.order});

  final DeliveryOrder order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = orderStatusStyle(order.status);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: style.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(style.icon, color: style.color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your order',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  StatusBadge(order.status),
                ],
              ),
            ),
            if (order.etaMinutes != null && order.status != OrderStatus.delivered)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('ETA', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  Text(
                    '~${order.etaMinutes} min',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.coral,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// autoDispose matters here: these hold live Supabase Realtime channels, and
// without it every tracked order/delivery would keep its websocket
// subscription alive for the rest of the session after the screen is popped.
final _orderStreamProvider = StreamProvider.autoDispose.family<DeliveryOrder?, String>((ref, orderId) {
  return ref.watch(ordersRepositoryProvider).watchOrder(orderId);
});

final _pingStreamProvider = StreamProvider.autoDispose.family<LocationPing?, String>((ref, deliveryId) {
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

  final MapController _mapController = MapController();
  // move() throws if called before FlutterMap has laid out, so gate camera
  // updates on onMapReady.
  bool _mapReady = false;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Recenters the camera every time a new (throttled/batched) courier
    // ping arrives via Supabase Realtime.
    ref.listen(_pingStreamProvider(widget.deliveryId), (previous, next) {
      final ping = next.valueOrNull;
      if (ping != null && _mapReady) {
        _mapController.move(LatLng(ping.lat, ping.lng), _mapController.camera.zoom);
      }
    });

    final ping = ref.watch(_pingStreamProvider(widget.deliveryId)).valueOrNull;
    final position = ping == null ? _fallbackCenter : LatLng(ping.lat, ping.lng);
    final scheme = Theme.of(context).colorScheme;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: position,
        initialZoom: 14,
        onMapReady: () => _mapReady = true,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          // OSM's tile usage policy requires an identifying user agent.
          userAgentPackageName: 'com.example.multi_vendor_logistics_and_delivery_system',
        ),
        if (ping != null)
          MarkerLayer(
            markers: [
              Marker(
                point: position,
                width: 44,
                height: 44,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
                    ],
                  ),
                  child: Icon(Icons.delivery_dining, color: scheme.onPrimary, size: 24),
                ),
              ),
            ],
          ),
        const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
      ],
    );
  }
}
