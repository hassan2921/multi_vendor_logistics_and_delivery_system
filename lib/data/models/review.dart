class Review {
  final String id;
  final String orderId;
  final String vendorId;
  final int rating;
  final String? comment;
  final DateTime? createdAt;

  const Review({
    required this.id,
    required this.orderId,
    required this.vendorId,
    required this.rating,
    this.comment,
    this.createdAt,
  });

  factory Review.fromJson(Map<String, dynamic> json) => Review(
        id: json['id'] as String,
        orderId: json['order_id'] as String,
        vendorId: json['vendor_id'] as String,
        rating: json['rating'] as int,
        comment: json['comment'] as String?,
        createdAt: json['created_at'] == null ? null : DateTime.parse(json['created_at'] as String),
      );
}
