import '../../core/supabase_client.dart';
import '../models/location_ping.dart';

class DeliveriesRepository {
  const DeliveriesRepository();

  /// Batch-writes a buffered set of throttled GPS points in a single
  /// insert — see features/courier/location_service.dart for the batching
  /// logic that keeps this from being called once per raw GPS fix.
  Future<void> insertLocationPings(List<LocationPing> pings) async {
    if (pings.isEmpty) return;
    await supabase.from('location_pings').insert(pings.map((p) => p.toJson()).toList());
  }

  Future<String?> getDeliveryIdForOrder(String orderId) async {
    final row = await supabase.from('deliveries').select('id').eq('order_id', orderId).maybeSingle();
    return row?['id'] as String?;
  }

  Stream<LocationPing?> watchLatestPing(String deliveryId) {
    return supabase
        .from('location_pings')
        .stream(primaryKey: ['id'])
        .eq('delivery_id', deliveryId)
        .order('recorded_at')
        .map((rows) => rows.isEmpty ? null : LocationPing.fromJson(rows.last));
  }
}
