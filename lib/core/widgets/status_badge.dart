import 'package:flutter/material.dart';

import '../../data/models/order.dart';
import '../theme/app_colors.dart';

/// A compact, color-coded pill for an [OrderStatus] — icon + label tinted with
/// the status' semantic color.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key, this.compact = false});

  final OrderStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = orderStatusStyle(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: compact ? 12 : 15, color: style.color),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(
              color: style.color,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 11 : 12.5,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
