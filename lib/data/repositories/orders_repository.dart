import '../../core/api_client.dart';
import '../../core/supabase_client.dart';
import '../models/order.dart';

class OrdersRepository {
  const OrdersRepository(this._api);

  final ApiClient _api;

  /// Writes go through the Express backend so business logic (total
  /// calculation, idempotency, role checks) stays server-side.
  ///
  /// [idempotencyKey] must be generated once per checkout attempt and
  /// reused if this call is retried, so a double-tap or network retry
  /// replays the original order instead of creating a duplicate.
  Future<DeliveryOrder> createOrder({
    required String vendorId,
    required List<OrderItem> items,
    required String idempotencyKey,
    String? deliveryAddress,
    double? deliveryLat,
    double? deliveryLng,
  }) async {
    final res = await _api.post(
      '/orders',
      {
        'vendorId': vendorId,
        'items': items.map((i) => i.toJson()).toList(),
        'deliveryAddress': ?deliveryAddress,
        'deliveryLat': ?deliveryLat,
        'deliveryLng': ?deliveryLng,
      },
      idempotencyKey: idempotencyKey,
    );
    return DeliveryOrder.fromJson(res['order'] as Map<String, dynamic>);
  }

  Future<DeliveryOrder> updateStatus(String orderId, OrderStatus status) async {
    final res = await _api.patch('/orders/$orderId/status', {'status': status.wireValue});
    return DeliveryOrder.fromJson(res['order'] as Map<String, dynamic>);
  }

  Future<DeliveryOrder> claimDelivery(String orderId) async {
    final res = await _api.post('/orders/$orderId/claim', {});
    return DeliveryOrder.fromJson(res['order'] as Map<String, dynamic>);
  }

  Future<List<Map<String, dynamic>>> listAvailableJobs() async {
    final res = await _api.get('/deliveries/available');
    return (res['jobs'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  /// Reads and live updates go straight to Supabase — RLS scopes what each
  /// role can see, and Realtime pushes status changes without polling.
  Stream<DeliveryOrder?> watchOrder(String orderId) {
    return supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', orderId)
        .map((rows) => rows.isEmpty ? null : DeliveryOrder.fromJson(rows.first));
  }

  Stream<List<DeliveryOrder>> watchVendorOrders(String vendorId) {
    return supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('vendor_id', vendorId)
        .map((rows) => rows.map(DeliveryOrder.fromJson).toList());
  }
}
