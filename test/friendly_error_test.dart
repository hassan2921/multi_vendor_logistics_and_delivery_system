import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor_logistics_and_delivery_system/core/api_client.dart';
import 'package:multi_vendor_logistics_and_delivery_system/core/ui/formatting.dart';

void main() {
  group('friendlyError', () {
    test('maps a cancelled payment sheet to a calm message, not a stack dump', () {
      const cancelled = StripeException(
        error: LocalizedErrorMessage(code: FailureCode.Canceled, message: 'The payment flow has been canceled'),
      );
      expect(friendlyError(cancelled), 'Payment cancelled.');
    });

    test('surfaces the localized Stripe message for real payment failures', () {
      const failed = StripeException(
        error: LocalizedErrorMessage(
          code: FailureCode.Failed,
          localizedMessage: 'Your card was declined.',
        ),
      );
      expect(friendlyError(failed), 'Your card was declined.');
    });

    test('falls back to a generic sentence when Stripe gives no message', () {
      const failed = StripeException(
        error: LocalizedErrorMessage(code: FailureCode.Failed),
      );
      expect(friendlyError(failed), 'Payment failed. Please try again.');
    });

    test('uses the server-provided message for ApiExceptions', () {
      expect(
        friendlyError(ApiException(502, 'Payment provider error: Connect is not enabled.')),
        'Payment provider error: Connect is not enabled.',
      );
    });

    test('turns raw socket errors into a human sentence', () {
      expect(
        friendlyError(Exception('SocketException: Connection refused')),
        'No internet connection. Please check your network and try again.',
      );
    });
  });
}
