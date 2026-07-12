class AppNotification {
  final String id;
  final String title;
  final String body;
  final Map<String, dynamic>? data;
  final bool read;
  final DateTime? createdAt;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    this.data,
    this.read = false,
    this.createdAt,
  });

  /// The order this notification is about, when it's an order event.
  String? get orderId => data?['order_id'] as String?;

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        data: json['data'] as Map<String, dynamic>?,
        read: json['read'] as bool? ?? false,
        createdAt: json['created_at'] == null ? null : DateTime.parse(json['created_at'] as String),
      );
}
