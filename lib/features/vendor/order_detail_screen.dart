import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_provider.dart';
import '../../core/ui/formatting.dart';
import '../../core/widgets/order_status_timeline.dart';
import '../../core/widgets/status_badge.dart';
import '../../data/models/order.dart';

class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({super.key, required this.order});

  final DeliveryOrder order;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  late OrderStatus _status = widget.order.status;
  bool _isUpdating = false;

  static const _vendorTransitions = <OrderStatus, OrderStatus>{
    OrderStatus.paid: OrderStatus.accepted,
    OrderStatus.accepted: OrderStatus.preparing,
    OrderStatus.preparing: OrderStatus.readyForPickup,
  };

  Future<void> _advance() async {
    final next = _vendorTransitions[_status];
    if (next == null) return;

    setState(() => _isUpdating = true);
    try {
      final updated = await ref.read(ordersRepositoryProvider).updateStatus(widget.order.id, next);
      setState(() => _status = updated.status);
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nextStatus = _vendorTransitions[_status];

    return Scaffold(
      appBar: AppBar(title: Text('Order #${shortOrderId(widget.order.id)}')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: StatusBadge(_status)),
                            Text(
                              formatMoney(widget.order.totalCents),
                              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        if (widget.order.deliveryAddress != null) ...[
                          const Divider(height: 24),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.location_on_outlined,
                                  size: 20, color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Deliver to',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                                    const SizedBox(height: 2),
                                    Text(widget.order.deliveryAddress!, style: theme.textTheme.bodyLarge),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Progress',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 20),
                        OrderStatusTimeline(_status),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          _ActionBar(
            nextStatus: nextStatus,
            isUpdating: _isUpdating,
            onAdvance: _advance,
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.nextStatus, required this.isUpdating, required this.onAdvance});

  final OrderStatus? nextStatus;
  final bool isUpdating;
  final VoidCallback onAdvance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: nextStatus == null
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline_rounded,
                        size: 20, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      'No further action needed',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                )
              : FilledButton(
                  onPressed: isUpdating ? null : onAdvance,
                  child: isUpdating
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : Text('Mark as ${nextStatus!.label}'),
                ),
        ),
      ),
    );
  }
}
