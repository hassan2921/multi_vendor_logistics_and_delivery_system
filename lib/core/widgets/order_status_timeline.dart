import 'package:flutter/material.dart';

import '../../data/models/order.dart';
import '../theme/app_colors.dart';

/// A vertical progress tracker of an order's journey. Collapses the 10-state
/// [OrderStatus] enum onto six customer-facing milestones and marks each as
/// done / current / upcoming. Cancelled orders show a single error row.
class OrderStatusTimeline extends StatelessWidget {
  const OrderStatusTimeline(this.status, {super.key});

  final OrderStatus status;

  static const _milestones = <(String, IconData)>[
    ('Order placed', Icons.receipt_long_rounded),
    ('Accepted', Icons.check_circle_outline_rounded),
    ('Preparing', Icons.restaurant_rounded),
    ('Ready for pickup', Icons.shopping_bag_rounded),
    ('On the way', Icons.local_shipping_rounded),
    ('Delivered', Icons.home_rounded),
  ];

  /// How far along the milestone list [status] sits (−1 = not yet placed).
  int get _progress {
    switch (status) {
      case OrderStatus.pendingPayment:
        return -1;
      case OrderStatus.paid:
        return 0;
      case OrderStatus.accepted:
        return 1;
      case OrderStatus.preparing:
        return 2;
      case OrderStatus.readyForPickup:
      case OrderStatus.courierAssigned:
        return 3;
      case OrderStatus.pickedUp:
      case OrderStatus.inTransit:
        return 4;
      case OrderStatus.delivered:
        return 5;
      case OrderStatus.cancelled:
        return -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (status == OrderStatus.cancelled) {
      return Row(
        children: [
          Icon(Icons.cancel_rounded, color: scheme.error),
          const SizedBox(width: 12),
          Text(
            'Order cancelled',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.error),
          ),
        ],
      );
    }

    final progress = _progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _milestones.length; i++)
          _MilestoneRow(
            label: _milestones[i].$1,
            icon: _milestones[i].$2,
            state: i < progress
                ? _NodeState.done
                : i == progress
                    ? _NodeState.current
                    : _NodeState.upcoming,
            isLast: i == _milestones.length - 1,
          ),
      ],
    );
  }
}

enum _NodeState { done, current, upcoming }

class _MilestoneRow extends StatelessWidget {
  const _MilestoneRow({
    required this.label,
    required this.icon,
    required this.state,
    required this.isLast,
  });

  final String label;
  final IconData icon;
  final _NodeState state;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = state == _NodeState.done;
    final current = state == _NodeState.current;
    final active = done || current;

    final nodeColor = current ? AppColors.coral : (done ? AppColors.success : scheme.surfaceContainerHighest);
    final lineColor = done ? AppColors.success : scheme.outlineVariant;
    final textColor = active ? scheme.onSurface : scheme.onSurfaceVariant;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: active ? nodeColor : scheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                  border: current ? Border.all(color: AppColors.coral.withValues(alpha: 0.25), width: 4) : null,
                ),
                child: Icon(
                  done ? Icons.check_rounded : icon,
                  size: 18,
                  color: active ? Colors.white : scheme.onSurfaceVariant,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2.5, color: lineColor),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Padding(
            padding: EdgeInsets.only(top: 7, bottom: isLast ? 0 : 20),
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: textColor,
                    fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
