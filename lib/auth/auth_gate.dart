import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/user_role.dart';
import '../features/courier/available_jobs_screen.dart';
import '../features/customer/vendor_list_screen.dart';
import '../features/vendor/incoming_orders_screen.dart';
import 'auth_provider.dart';
import 'login_screen.dart';

/// Root router: shows the login flow when signed out, otherwise routes to
/// the screen for the signed-in user's role (customer/courier/vendor).
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appUserAsync = ref.watch(currentAppUserProvider);

    return appUserAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, _) => Scaffold(body: Center(child: Text('Something went wrong: $err'))),
      data: (appUser) {
        if (appUser == null) return const LoginScreen();

        switch (appUser.role) {
          case UserRole.customer:
            return const VendorListScreen();
          case UserRole.courier:
            return const AvailableJobsScreen();
          case UserRole.vendor:
            return const IncomingOrdersScreen();
        }
      },
    );
  }
}
