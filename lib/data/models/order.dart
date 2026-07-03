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

class OrderItem {
  final String name;
  final int quantity;
  final int unitPriceCents;

  const OrderItem({required this.name, required this.quantity, required this.unitPriceCents});

  Map<String, dynamic> toJson() => {
        'name': name,
        'quantity': quantity,
        'unit_price_cents': unitPriceCents,
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
  });

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
      );
}
