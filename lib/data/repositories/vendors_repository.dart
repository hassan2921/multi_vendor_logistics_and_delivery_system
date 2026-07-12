import '../../core/api_client.dart';
import '../models/product.dart';
import '../models/review.dart';
import '../models/vendor.dart';

class VendorsRepository {
  const VendorsRepository(this._api);

  final ApiClient _api;

  Future<List<Vendor>> listVendors({
    String? search,
    String? category,
    double? minRating,
    bool sortByRating = false,
  }) async {
    final query = <String, String>{
      if (search != null && search.isNotEmpty) 'search': search,
      if (category != null && category.isNotEmpty) 'category': category,
      if (minRating != null) 'minRating': '$minRating',
      if (sortByRating) 'sort': 'rating',
    };
    final qs = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    final res = await _api.get('/vendors$qs');
    final vendors = res['vendors'] as List<dynamic>;
    return vendors.map((v) => Vendor.fromJson(v as Map<String, dynamic>)).toList();
  }

  /// Public menu browsing — no auth required.
  Future<List<Product>> listProducts(String vendorId, {String? search, String? category}) async {
    final query = <String, String>{
      if (search != null && search.isNotEmpty) 'search': search,
      if (category != null && category.isNotEmpty) 'category': category,
    };
    final qs = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    final res = await _api.get('/vendors/$vendorId/products$qs');
    return (res['products'] as List<dynamic>).map((p) => Product.fromJson(p as Map<String, dynamic>)).toList();
  }

  Future<List<Review>> listReviews(String vendorId) async {
    final res = await _api.get('/vendors/$vendorId/reviews');
    return (res['reviews'] as List<dynamic>).map((r) => Review.fromJson(r as Map<String, dynamic>)).toList();
  }

  /// Starts (or resumes) Stripe Connect onboarding; returns the hosted
  /// onboarding URL for the vendor to open in a browser.
  Future<String> startConnectOnboarding() async {
    final res = await _api.post('/vendors/me/connect/onboard', {});
    return res['url'] as String;
  }

  Future<bool> refreshConnectStatus() async {
    final res = await _api.get('/vendors/me/connect/status');
    return res['payoutsEnabled'] as bool? ?? false;
  }

  /// Returns null if this vendor user hasn't created their storefront yet
  /// (drives the onboarding-vs-dashboard branch in the vendor role gate).
  Future<Vendor?> getMyVendor() async {
    try {
      final res = await _api.get('/vendors/me');
      return Vendor.fromJson(res['vendor'] as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Idempotent: safe to retry if the app doesn't hear back the first time.
  Future<Vendor> onboard({
    required String name,
    required String idempotencyKey,
    String? address,
    String? imageUrl,
  }) async {
    final res = await _api.post(
      '/vendors/me',
      {'name': name, 'address': ?address, 'imageUrl': ?imageUrl},
      idempotencyKey: idempotencyKey,
    );
    return Vendor.fromJson(res['vendor'] as Map<String, dynamic>);
  }

  /// Updates the signed-in vendor's storefront profile. Null params are left
  /// unchanged; pass an empty string for [imageUrl] to clear the photo (sent
  /// as an explicit JSON null, which the backend treats as "remove").
  Future<Vendor> updateMyVendor({String? name, String? address, String? imageUrl}) async {
    final res = await _api.patch('/vendors/me', {
      'name': ?name,
      'address': ?address,
      if (imageUrl != null) 'imageUrl': imageUrl.isEmpty ? null : imageUrl,
    });
    return Vendor.fromJson(res['vendor'] as Map<String, dynamic>);
  }

  Future<List<Product>> listMyProducts() async {
    final res = await _api.get('/vendors/me/products');
    return (res['products'] as List<dynamic>).map((p) => Product.fromJson(p as Map<String, dynamic>)).toList();
  }

  Future<Product> createProduct({
    required String name,
    required int priceCents,
    String? description,
    String? category,
    int? stockQuantity,
    String? imageUrl,
  }) async {
    final res = await _api.post('/vendors/me/products', {
      'name': name,
      'priceCents': priceCents,
      'description': ?description,
      'category': ?category,
      'stockQuantity': ?stockQuantity,
      'imageUrl': ?imageUrl,
    });
    return Product.fromJson(res['product'] as Map<String, dynamic>);
  }

  Future<Product> updateProduct(
    String productId, {
    int? priceCents,
    bool? isAvailable,
    String? category,
    int? stockQuantity,
  }) async {
    final res = await _api.patch('/vendors/me/products/$productId', {
      'priceCents': ?priceCents,
      'isAvailable': ?isAvailable,
      'category': ?category,
      'stockQuantity': ?stockQuantity,
    });
    return Product.fromJson(res['product'] as Map<String, dynamic>);
  }
}
