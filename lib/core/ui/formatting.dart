import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api_client.dart';

/// Formats a cents amount as a currency string, e.g. `1999 -> "$19.99"`.
String formatMoney(int cents, {String symbol = '\$'}) =>
    '$symbol${(cents / 100).toStringAsFixed(2)}';

/// A short, human-friendly order reference derived from the (UUID) order id,
/// e.g. `"3F9A1C2D"`. Display-only.
String shortOrderId(String id) =>
    (id.length >= 8 ? id.substring(0, 8) : id).toUpperCase();

/// A compact relative timestamp, e.g. `"just now"`, `"5m ago"`, `"3h ago"`,
/// `"2d ago"`, falling back to an ISO date for anything older than a week.
String timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final local = time.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

/// Turns a raw exception into a message safe and pleasant to show a user.
///
/// Every screen used to render `e.toString()` directly, leaking things like
/// `ApiException(500): …` and `Exception: …`. This centralises the mapping so
/// users see a clean sentence instead.
String friendlyError(Object error) {
  if (error is ApiException) return error.message;
  if (error is AuthException) return error.message;
  if (error is PostgrestException) return error.message;
  if (error is StripeException) {
    return error.error.code == FailureCode.Canceled
        ? 'Payment cancelled.'
        : (error.error.localizedMessage ?? error.error.message ?? 'Payment failed. Please try again.');
  }

  final text = error.toString();
  if (text.contains('SocketException') ||
      text.contains('Failed host lookup') ||
      text.contains('Connection refused') ||
      text.contains('Network is unreachable')) {
    return 'No internet connection. Please check your network and try again.';
  }
  // Strip Dart's leading "Exception: " noise if present.
  return text.replaceFirst(RegExp(r'^Exception:\s*'), '');
}
