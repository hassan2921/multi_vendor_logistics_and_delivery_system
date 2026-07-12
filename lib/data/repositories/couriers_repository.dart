import '../../core/api_client.dart';
import '../models/courier_earnings.dart';

class CouriersRepository {
  const CouriersRepository(this._api);

  final ApiClient _api;

  /// Toggles the courier in/out of the auto-dispatch pool. Location is sent
  /// along when available so dispatch can rank by distance.
  Future<void> setAvailability({required bool isAvailable, double? lat, double? lng}) async {
    await _api.post('/couriers/availability', {
      'isAvailable': isAvailable,
      'lat': ?lat,
      'lng': ?lng,
    });
  }

  Future<CourierEarnings> getEarnings() async {
    final res = await _api.get('/couriers/earnings');
    return CourierEarnings.fromJson(res['earnings'] as Map<String, dynamic>);
  }
}
