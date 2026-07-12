class Vendor {
  final String id;
  final String name;
  final String? address;
  final double? lat;
  final double? lng;
  final bool isActive;
  final String? category;
  final double ratingAvg;
  final int ratingCount;
  final String approvalStatus;
  final bool payoutsEnabled;
  final String? imageUrl;

  const Vendor({
    required this.id,
    required this.name,
    this.address,
    this.lat,
    this.lng,
    this.isActive = true,
    this.category,
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.approvalStatus = 'approved',
    this.payoutsEnabled = false,
    this.imageUrl,
  });

  bool get hasReviews => ratingCount > 0;

  factory Vendor.fromJson(Map<String, dynamic> json) => Vendor(
        id: json['id'] as String,
        name: json['name'] as String,
        address: json['address'] as String?,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        isActive: json['is_active'] as bool? ?? true,
        category: json['category'] as String?,
        ratingAvg: (json['rating_avg'] as num?)?.toDouble() ?? 0,
        ratingCount: json['rating_count'] as int? ?? 0,
        approvalStatus: json['approval_status'] as String? ?? 'approved',
        payoutsEnabled: json['payouts_enabled'] as bool? ?? false,
        imageUrl: json['image_url'] as String?,
      );
}
