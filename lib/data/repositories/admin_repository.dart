import '../../core/api_client.dart';
import '../models/order.dart';
import '../models/vendor.dart';

class PlatformMetrics {
  final int ordersTotal;
  final int ordersDelivered;
  final int ordersCancelled;
  final int gmvCents;
  final int platformFeesCents;
  final int vendorsPendingApproval;
  final int activeCouriers;

  const PlatformMetrics({
    required this.ordersTotal,
    required this.ordersDelivered,
    required this.ordersCancelled,
    required this.gmvCents,
    required this.platformFeesCents,
    required this.vendorsPendingApproval,
    required this.activeCouriers,
  });

  factory PlatformMetrics.fromJson(Map<String, dynamic> json) => PlatformMetrics(
        ordersTotal: json['orders_total'] as int,
        ordersDelivered: json['orders_delivered'] as int,
        ordersCancelled: json['orders_cancelled'] as int,
        gmvCents: json['gmv_cents'] as int,
        platformFeesCents: json['platform_fees_cents'] as int,
        vendorsPendingApproval: json['vendors_pending_approval'] as int,
        activeCouriers: json['active_couriers'] as int,
      );
}

class AdminRepository {
  const AdminRepository(this._api);

  final ApiClient _api;

  Future<PlatformMetrics> getMetrics() async {
    final res = await _api.get('/admin/metrics');
    return PlatformMetrics.fromJson(res['metrics'] as Map<String, dynamic>);
  }

  Future<List<Vendor>> listVendors({String? status}) async {
    final qs = status == null ? '' : '?status=$status';
    final res = await _api.get('/admin/vendors$qs');
    return (res['vendors'] as List<dynamic>)
        .map((v) => Vendor.fromJson(v as Map<String, dynamic>))
        .toList();
  }

  Future<Vendor> setVendorApproval(String vendorId, String status) async {
    final res = await _api.patch('/admin/vendors/$vendorId/approval', {'status': status});
    return Vendor.fromJson(res['vendor'] as Map<String, dynamic>);
  }

  Future<List<DeliveryOrder>> listOrders({String? status}) async {
    final qs = status == null ? '' : '?status=$status';
    final res = await _api.get('/admin/orders$qs');
    return (res['orders'] as List<dynamic>)
        .map((o) => DeliveryOrder.fromJson(o as Map<String, dynamic>))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listPromoCodes() async {
    final res = await _api.get('/admin/promos');
    return (res['promoCodes'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<void> createPromoCode({
    required String code,
    required String discountType,
    required int discountValue,
    int? minSubtotalCents,
    int? maxDiscountCents,
    int? maxRedemptions,
  }) async {
    await _api.post('/admin/promos', {
      'code': code,
      'discountType': discountType,
      'discountValue': discountValue,
      'minSubtotalCents': ?minSubtotalCents,
      'maxDiscountCents': ?maxDiscountCents,
      'maxRedemptions': ?maxRedemptions,
    });
  }
}
