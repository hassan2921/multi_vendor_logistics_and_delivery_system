import '../../core/api_client.dart';
import '../models/vendor.dart';

class VendorsRepository {
  const VendorsRepository(this._api);

  final ApiClient _api;

  Future<List<Vendor>> listVendors() async {
    final res = await _api.get('/vendors');
    final vendors = res['vendors'] as List<dynamic>;
    return vendors.map((v) => Vendor.fromJson(v as Map<String, dynamic>)).toList();
  }
}
