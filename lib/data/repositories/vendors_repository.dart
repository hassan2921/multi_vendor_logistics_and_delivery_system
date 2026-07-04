import '../../core/api_client.dart';
import '../models/product.dart';
import '../models/vendor.dart';

class VendorsRepository {
  const VendorsRepository(this._api);

  final ApiClient _api;

  Future<List<Vendor>> listVendors() async {
    final res = await _api.get('/vendors');
    final vendors = res['vendors'] as List<dynamic>;
    return vendors.map((v) => Vendor.fromJson(v as Map<String, dynamic>)).toList();
  }

  /// Public menu browsing — no auth required.
  Future<List<Product>> listProducts(String vendorId) async {
    final res = await _api.get('/vendors/$vendorId/products');
    return (res['products'] as List<dynamic>).map((p) => Product.fromJson(p as Map<String, dynamic>)).toList();
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
  }) async {
    final res = await _api.post(
      '/vendors/me',
      {'name': name, 'address': ?address},
      idempotencyKey: idempotencyKey,
    );
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
  }) async {
    final res = await _api.post('/vendors/me/products', {
      'name': name,
      'priceCents': priceCents,
      'description': ?description,
    });
    return Product.fromJson(res['product'] as Map<String, dynamic>);
  }

  Future<Product> updateProduct(
    String productId, {
    int? priceCents,
    bool? isAvailable,
  }) async {
    final res = await _api.patch('/vendors/me/products/$productId', {
      'priceCents': ?priceCents,
      'isAvailable': ?isAvailable,
    });
    return Product.fromJson(res['product'] as Map<String, dynamic>);
  }
}
