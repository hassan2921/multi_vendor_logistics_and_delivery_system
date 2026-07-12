import '../../core/api_client.dart';
import '../../core/supabase_client.dart';
import '../models/order.dart';
import '../models/order_quote.dart';
import '../models/review.dart';

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
    int? tipCents,
    String? promoCode,
  }) async {
    final res = await _api.post(
      '/orders',
      {
        'vendorId': vendorId,
        'items': items.map((i) => i.toJson()).toList(),
        'deliveryAddress': ?deliveryAddress,
        'deliveryLat': ?deliveryLat,
        'deliveryLng': ?deliveryLng,
        'tipCents': ?tipCents,
        'promoCode': ?promoCode,
      },
      idempotencyKey: idempotencyKey,
    );
    return DeliveryOrder.fromJson(res['order'] as Map<String, dynamic>);
  }

  /// Server-side price preview (fees, discount, ETA). The checkout screen
  /// re-quotes whenever the tip or promo code changes, so what the customer
  /// sees is exactly what createOrder will charge.
  Future<OrderQuote> quote({
    required String vendorId,
    required List<OrderItem> items,
    double? deliveryLat,
    double? deliveryLng,
    int? tipCents,
    String? promoCode,
  }) async {
    final res = await _api.post('/orders/quote', {
      'vendorId': vendorId,
      'items': items.map((i) => i.toJson()).toList(),
      'deliveryLat': ?deliveryLat,
      'deliveryLng': ?deliveryLng,
      'tipCents': ?tipCents,
      'promoCode': ?promoCode,
    });
    return OrderQuote.fromJson(res['quote'] as Map<String, dynamic>);
  }

  Future<Review> submitReview(String orderId, {required int rating, String? comment}) async {
    final res = await _api.post('/orders/$orderId/review', {
      'rating': rating,
      'comment': ?comment,
    });
    return Review.fromJson(res['review'] as Map<String, dynamic>);
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

  /// Role-agnostic history: the backend resolves what "mine" means from the
  /// caller's app role (customer's own orders, courier's claimed
  /// deliveries, or the signed-in vendor's storefront orders).
  Future<List<DeliveryOrder>> listMine() async {
    final res = await _api.get('/orders/mine');
    return (res['orders'] as List<dynamic>)
        .map((o) => DeliveryOrder.fromJson(o as Map<String, dynamic>))
        .toList();
  }

  Future<DeliveryOrder> cancelOrder(String orderId) async {
    final res = await _api.post('/orders/$orderId/cancel', {});
    return DeliveryOrder.fromJson(res['order'] as Map<String, dynamic>);
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
