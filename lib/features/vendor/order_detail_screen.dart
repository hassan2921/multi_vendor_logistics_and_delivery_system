import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_provider.dart';
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
    final nextStatus = _vendorTransitions[_status];

    return Scaffold(
      appBar: AppBar(title: Text('Order ${widget.order.id.substring(0, 8)}')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Status: ${_status.label}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Total: \$${(widget.order.totalCents / 100).toStringAsFixed(2)}'),
            if (widget.order.deliveryAddress != null) ...[
              const SizedBox(height: 8),
              Text('Deliver to: ${widget.order.deliveryAddress}'),
            ],
            const SizedBox(height: 24),
            if (nextStatus != null)
              FilledButton(
                onPressed: _isUpdating ? null : _advance,
                child: _isUpdating
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Mark as ${nextStatus.label}'),
              )
            else
              const Text('No further vendor action needed for this order.'),
          ],
        ),
      ),
    );
  }
}
