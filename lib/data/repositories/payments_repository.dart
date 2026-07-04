import '../../core/api_client.dart';

class PaymentsRepository {
  const PaymentsRepository(this._api);

  final ApiClient _api;

  /// Server creates the PaymentIntent and returns only the client_secret —
  /// the Stripe secret key never reaches this client.
  ///
  /// The key is derived from the order id: retrying payment for the same
  /// order replays the original intent instead of minting a second one.
  Future<String> createPaymentIntent(String orderId) async {
    final res = await _api.post(
      '/payments/intent',
      {'orderId': orderId},
      idempotencyKey: 'payment-intent-$orderId',
    );
    return res['clientSecret'] as String;
  }
}
