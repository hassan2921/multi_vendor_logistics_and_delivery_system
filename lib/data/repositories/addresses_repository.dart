import '../../core/api_client.dart';
import '../models/address.dart';

class AddressesRepository {
  const AddressesRepository(this._api);

  final ApiClient _api;

  Future<List<Address>> listMine() async {
    final res = await _api.get('/addresses');
    return (res['addresses'] as List<dynamic>)
        .map((a) => Address.fromJson(a as Map<String, dynamic>))
        .toList();
  }

  Future<Address> create({
    required String label,
    required String addressLine,
    double? lat,
    double? lng,
    bool isDefault = false,
  }) async {
    final res = await _api.post('/addresses', {
      'label': label,
      'addressLine': addressLine,
      'lat': ?lat,
      'lng': ?lng,
      'isDefault': isDefault,
    });
    return Address.fromJson(res['address'] as Map<String, dynamic>);
  }

  Future<Address> setDefault(String addressId) async {
    final res = await _api.patch('/addresses/$addressId', {'isDefault': true});
    return Address.fromJson(res['address'] as Map<String, dynamic>);
  }

  Future<void> delete(String addressId) => _api.delete('/addresses/$addressId');
}
