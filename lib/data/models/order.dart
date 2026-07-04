enum OrderStatus {
  pendingPayment,
  paid,
  accepted,
  preparing,
  readyForPickup,
  courierAssigned,
  pickedUp,
  inTransit,
  delivered,
  cancelled,
}

extension OrderStatusJson on OrderStatus {
  String get wireValue {
    switch (this) {
      case OrderStatus.pendingPayment:
        return 'pending_payment';
      case OrderStatus.paid:
        return 'paid';
      case OrderStatus.accepted:
        return 'accepted';
      case OrderStatus.preparing:
        return 'preparing';
      case OrderStatus.readyForPickup:
        return 'ready_for_pickup';
      case OrderStatus.courierAssigned:
        return 'courier_assigned';
      case OrderStatus.pickedUp:
        return 'picked_up';
      case OrderStatus.inTransit:
        return 'in_transit';
      case OrderStatus.delivered:
        return 'delivered';
      case OrderStatus.cancelled:
        return 'cancelled';
    }
  }

  static OrderStatus fromWire(String value) => OrderStatus.values.firstWhere(
        (s) => s.wireValue == value,
        orElse: () => OrderStatus.pendingPayment,
      );

  String get label {
    switch (this) {
      case OrderStatus.pendingPayment:
        return 'Awaiting payment';
      case OrderStatus.paid:
        return 'Paid';
      case OrderStatus.accepted:
        return 'Accepted by vendor';
      case OrderStatus.preparing:
        return 'Preparing';
      case OrderStatus.readyForPickup:
        return 'Ready for pickup';
      case OrderStatus.courierAssigned:
        return 'Courier assigned';
      case OrderStatus.pickedUp:
        return 'Picked up';
      case OrderStatus.inTransit:
        return 'On the way';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }
}

/// A cart line. [name]/[unitPriceCents] are only for local display — the
/// wire format sends just [productId]/[quantity], since the backend prices
/// every order from its own product catalog rather than trusting the client.
class OrderItem {
  final String productId;
  final String name;
  final int quantity;
  final int unitPriceCents;

  const OrderItem({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unitPriceCents,
  });

  OrderItem withQuantity(int quantity) => OrderItem(
        productId: productId,
        name: name,
        quantity: quantity,
        unitPriceCents: unitPriceCents,
      );

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'quantity': quantity,
      };
}

class DeliveryOrder {
  final String id;
  final String customerId;
  final String vendorId;
  final String? courierId;
  final OrderStatus status;
  final int totalCents;
  final String currency;
  final String? deliveryAddress;
  final double? deliveryLat;
  final double? deliveryLng;
  final DateTime? createdAt;

  const DeliveryOrder({
    required this.id,
    required this.customerId,
    required this.vendorId,
    required this.status,
    required this.totalCents,
    required this.currency,
    this.courierId,
    this.deliveryAddress,
    this.deliveryLat,
    this.deliveryLng,
    this.createdAt,
  });

  bool get isCancellableByCustomer => const {
        OrderStatus.pendingPayment,
        OrderStatus.paid,
        OrderStatus.accepted,
        OrderStatus.preparing,
      }.contains(status);

  factory DeliveryOrder.fromJson(Map<String, dynamic> json) => DeliveryOrder(
        id: json['id'] as String,
        customerId: json['customer_id'] as String,
        vendorId: json['vendor_id'] as String,
        courierId: json['courier_id'] as String?,
        status: OrderStatusJson.fromWire(json['status'] as String),
        totalCents: json['total_cents'] as int,
        currency: json['currency'] as String? ?? 'usd',
        deliveryAddress: json['delivery_address'] as String?,
        deliveryLat: (json['delivery_lat'] as num?)?.toDouble(),
        deliveryLng: (json['delivery_lng'] as num?)?.toDouble(),
        createdAt: json['created_at'] == null ? null : DateTime.parse(json['created_at'] as String),
      );
}
