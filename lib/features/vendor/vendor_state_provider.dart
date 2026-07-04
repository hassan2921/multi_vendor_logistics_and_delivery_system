import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_provider.dart';
import '../../data/models/vendor.dart';

/// Null means the signed-in vendor user hasn't created their storefront yet
/// — drives the onboarding-vs-dashboard branch for the vendor role.
final myVendorProvider = FutureProvider.autoDispose<Vendor?>((ref) {
  return ref.watch(vendorsRepositoryProvider).getMyVendor();
});
