class Product {
  final String id;
  final String vendorId;
  final String name;
  final String? description;
  final int priceCents;
  final bool isAvailable;
  final String? category;

  /// null = inventory not tracked for this product.
  final int? stockQuantity;
  final String? imageUrl;

  const Product({
    required this.id,
    required this.vendorId,
    required this.name,
    required this.priceCents,
    this.description,
    this.isAvailable = true,
    this.category,
    this.stockQuantity,
    this.imageUrl,
  });

  bool get isOutOfStock => stockQuantity != null && stockQuantity! <= 0;

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        vendorId: json['vendor_id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        priceCents: json['price_cents'] as int,
        isAvailable: json['is_available'] as bool? ?? true,
        category: json['category'] as String?,
        stockQuantity: json['stock_quantity'] as int?,
        imageUrl: json['image_url'] as String?,
      );
}
