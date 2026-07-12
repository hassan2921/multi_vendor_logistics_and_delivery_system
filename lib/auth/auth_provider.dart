import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb show AuthState;

import '../core/api_client.dart';
import '../core/supabase_client.dart';
import '../data/models/app_user.dart';
import '../data/repositories/addresses_repository.dart';
import '../data/repositories/admin_repository.dart';
import '../data/repositories/couriers_repository.dart';
import '../data/repositories/deliveries_repository.dart';
import '../data/repositories/notifications_repository.dart';
import '../data/repositories/orders_repository.dart';
import '../data/repositories/payments_repository.dart';
import '../data/repositories/vendors_repository.dart';

final apiClientProvider = Provider<ApiClient>((ref) => const ApiClient());

final ordersRepositoryProvider = Provider((ref) => OrdersRepository(ref.watch(apiClientProvider)));
final vendorsRepositoryProvider = Provider((ref) => VendorsRepository(ref.watch(apiClientProvider)));
final paymentsRepositoryProvider = Provider((ref) => PaymentsRepository(ref.watch(apiClientProvider)));
final deliveriesRepositoryProvider = Provider((ref) => const DeliveriesRepository());
final addressesRepositoryProvider = Provider((ref) => AddressesRepository(ref.watch(apiClientProvider)));
final couriersRepositoryProvider = Provider((ref) => CouriersRepository(ref.watch(apiClientProvider)));
final notificationsRepositoryProvider =
    Provider((ref) => NotificationsRepository(ref.watch(apiClientProvider)));
final adminRepositoryProvider = Provider((ref) => AdminRepository(ref.watch(apiClientProvider)));

/// Emits every Supabase auth state change (sign-in, sign-out, token refresh).
final authStateChangesProvider = StreamProvider<sb.AuthState>((ref) {
  return supabase.auth.onAuthStateChange;
});

/// Resolves the app-level `users` row (with role) for the signed-in
/// Supabase auth user, re-fetching whenever the auth state changes.
final currentAppUserProvider = FutureProvider<AppUser?>((ref) async {
  final authState = ref.watch(authStateChangesProvider).valueOrNull;
  final session = authState?.session ?? supabase.auth.currentSession;
  if (session == null) return null;

  final row = await supabase
      .from('users')
      .select()
      .eq('auth_user_id', session.user.id)
      .maybeSingle();

  if (row == null) return null;
  return AppUser.fromJson(row);
});
