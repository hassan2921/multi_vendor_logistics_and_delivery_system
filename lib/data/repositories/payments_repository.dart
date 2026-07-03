import '../../core/api_client.dart';

class PaymentsRepository {
  const PaymentsRepository(this._api);

  final ApiClient _api;

  /// Server creates the PaymentIntent and returns only the client_secret —
  /// the Stripe secret key never reaches this client.
  Future<String> createPaymentIntent(String orderId) async {
    final res = await _api.post('/payments/intent', {'orderId': orderId}, idempotent: true);
    return res['clientSecret'] as String;
  }
}
