class Product {
  final String id;
  final String vendorId;
  final String name;
  final String? description;
  final int priceCents;
  final bool isAvailable;

  const Product({
    required this.id,
    required this.vendorId,
    required this.name,
    required this.priceCents,
    this.description,
    this.isAvailable = true,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        vendorId: json['vendor_id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        priceCents: json['price_cents'] as int,
        isAvailable: json['is_available'] as bool? ?? true,
      );
}
