import 'package:flutter/material.dart';

import '../../data/models/order.dart';

/// Brand + semantic color tokens for the "warm & energetic" delivery theme.
///
/// These are raw brand values; the [ColorScheme]s in [AppTheme] are derived
/// from them. Semantic colors (success/warning/info) live here too since
/// Material's scheme has no first-class slot for them.
abstract final class AppColors {
  // Brand.
  static const coral = Color(0xFFF0502E); // primary
  static const coralDark = Color(0xFFC63D1F);
  static const amber = Color(0xFFF59E0B); // secondary / accent

  // Semantic.
  static const success = Color(0xFF12B76A);
  static const warning = Color(0xFFF79009);
  static const error = Color(0xFFF04438);
  static const info = Color(0xFF2E90FA);

  // Surfaces (warm-tinted neutrals).
  static const lightBackground = Color(0xFFFDFBF9);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceVariant = Color(0xFFF4EEE9);
  static const darkBackground = Color(0xFF17130F);
  static const darkSurface = Color(0xFF211B16);
  static const darkSurfaceVariant = Color(0xFF2C251F);
}

/// A semantic style (color + icon) for an order status, resolved against the
/// active [ColorScheme] so it reads correctly in light and dark mode.
class OrderStatusStyle {
  const OrderStatusStyle(this.color, this.icon);
  final Color color;
  final IconData icon;
}

OrderStatusStyle orderStatusStyle(OrderStatus status) {
  switch (status) {
    case OrderStatus.pendingPayment:
      return const OrderStatusStyle(AppColors.warning, Icons.hourglass_top_rounded);
    case OrderStatus.paid:
      return const OrderStatusStyle(AppColors.info, Icons.payments_rounded);
    case OrderStatus.accepted:
      return const OrderStatusStyle(AppColors.coral, Icons.check_circle_outline_rounded);
    case OrderStatus.preparing:
      return const OrderStatusStyle(AppColors.coral, Icons.restaurant_rounded);
    case OrderStatus.readyForPickup:
      return const OrderStatusStyle(AppColors.amber, Icons.shopping_bag_rounded);
    case OrderStatus.courierAssigned:
      return const OrderStatusStyle(AppColors.info, Icons.person_pin_circle_rounded);
    case OrderStatus.pickedUp:
      return const OrderStatusStyle(AppColors.info, Icons.local_shipping_rounded);
    case OrderStatus.inTransit:
      return const OrderStatusStyle(AppColors.info, Icons.navigation_rounded);
    case OrderStatus.delivered:
      return const OrderStatusStyle(AppColors.success, Icons.task_alt_rounded);
    case OrderStatus.cancelled:
      return const OrderStatusStyle(Color(0xFF98A2B3), Icons.cancel_rounded);
  }
}

/// Convenience accessor used by badges/timelines.
Color orderStatusColor(OrderStatus status) => orderStatusStyle(status).color;
