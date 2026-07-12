class Address {
  final String id;
  final String label;
  final String addressLine;
  final double? lat;
  final double? lng;
  final bool isDefault;

  const Address({
    required this.id,
    required this.label,
    required this.addressLine,
    this.lat,
    this.lng,
    this.isDefault = false,
  });

  factory Address.fromJson(Map<String, dynamic> json) => Address(
        id: json['id'] as String,
        label: json['label'] as String,
        addressLine: json['address_line'] as String,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        isDefault: json['is_default'] as bool? ?? false,
      );
}
