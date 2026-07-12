class CourierEarnings {
  final int totalCents;
  final List<EarningEntry> deliveries;

  const CourierEarnings({required this.totalCents, required this.deliveries});

  factory CourierEarnings.fromJson(Map<String, dynamic> json) => CourierEarnings(
        totalCents: json['total_cents'] as int,
        deliveries: (json['deliveries'] as List<dynamic>)
            .map((d) => EarningEntry.fromJson(d as Map<String, dynamic>))
            .toList(),
      );
}

class EarningEntry {
  final String id;
  final String orderId;
  final int payoutCents;
  final double? distanceKm;
  final DateTime? deliveredAt;

  const EarningEntry({
    required this.id,
    required this.orderId,
    required this.payoutCents,
    this.distanceKm,
    this.deliveredAt,
  });

  factory EarningEntry.fromJson(Map<String, dynamic> json) => EarningEntry(
        id: json['id'] as String,
        orderId: json['order_id'] as String,
        payoutCents: json['courier_payout_cents'] as int,
        distanceKm: (json['distance_km'] as num?)?.toDouble(),
        deliveredAt:
            json['delivered_at'] == null ? null : DateTime.parse(json['delivered_at'] as String),
      );
}
