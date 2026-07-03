class LocationPing {
  final String deliveryId;
  final String courierId;
  final double lat;
  final double lng;
  final DateTime recordedAt;

  const LocationPing({
    required this.deliveryId,
    required this.courierId,
    required this.lat,
    required this.lng,
    required this.recordedAt,
  });

  factory LocationPing.fromJson(Map<String, dynamic> json) => LocationPing(
        deliveryId: json['delivery_id'] as String,
        courierId: json['courier_id'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        recordedAt: DateTime.parse(json['recorded_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'delivery_id': deliveryId,
        'courier_id': courierId,
        'lat': lat,
        'lng': lng,
        'recorded_at': recordedAt.toIso8601String(),
      };
}
