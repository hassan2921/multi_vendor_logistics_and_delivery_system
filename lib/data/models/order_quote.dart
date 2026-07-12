/// Server-computed checkout preview. Every number comes from the backend's
/// pricing engine — the app never does its own fee math.
class OrderQuote {
  final int subtotalCents;
  final int deliveryFeeCents;
  final int discountCents;
  final int tipCents;
  final int totalCents;
  final double? distanceKm;
  final int? etaMinutes;
  final String? promoCode;

  const OrderQuote({
    required this.subtotalCents,
    required this.deliveryFeeCents,
    required this.discountCents,
    required this.tipCents,
    required this.totalCents,
    this.distanceKm,
    this.etaMinutes,
    this.promoCode,
  });

  factory OrderQuote.fromJson(Map<String, dynamic> json) => OrderQuote(
        subtotalCents: json['subtotal_cents'] as int,
        deliveryFeeCents: json['delivery_fee_cents'] as int,
        discountCents: json['discount_cents'] as int,
        tipCents: json['tip_cents'] as int,
        totalCents: json['total_cents'] as int,
        distanceKm: (json['distance_km'] as num?)?.toDouble(),
        etaMinutes: json['eta_minutes'] as int?,
        promoCode: json['promo_code'] as String?,
      );
}
