class Vendor {
  final String id;
  final String name;
  final String? address;
  final double? lat;
  final double? lng;
  final bool isActive;

  const Vendor({
    required this.id,
    required this.name,
    this.address,
    this.lat,
    this.lng,
    this.isActive = true,
  });

  factory Vendor.fromJson(Map<String, dynamic> json) => Vendor(
        id: json['id'] as String,
        name: json['name'] as String,
        address: json['address'] as String?,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        isActive: json['is_active'] as bool? ?? true,
      );
}
