import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../../auth/auth_provider.dart';
import '../../data/models/order.dart';
import '../../data/models/vendor.dart';
import 'tracking_screen.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({
    super.key,
    required this.vendor,
    required this.items,
    this.deliveryAddress,
  });

  final Vendor vendor;
  final List<OrderItem> items;
  final String? deliveryAddress;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  bool _isProcessing = false;
  String? _error;

  int get _totalCents => widget.items.fold(0, (sum, item) => sum + item.quantity * item.unitPriceCents);

  Future<void> _payAndPlaceOrder() async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      final ordersRepo = ref.read(ordersRepositoryProvider);
      final paymentsRepo = ref.read(paymentsRepositoryProvider);

      // 1. Create the order server-side (idempotency-protected — safe to
      // retry this whole flow if the network drops mid-checkout).
      final order = await ordersRepo.createOrder(
        vendorId: widget.vendor.id,
        items: widget.items,
        deliveryAddress: widget.deliveryAddress,
      );

      // 2. Server creates the Stripe PaymentIntent, we only ever see the
      // client secret — the secret key stays on the backend.
      final clientSecret = await paymentsRepo.createPaymentIntent(order.id);

      // 3. Confirm payment with Stripe's PaymentSheet (test mode).
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Logistics Demo',
        ),
      );
      await Stripe.instance.presentPaymentSheet();

      // 4. Stripe's webhook (backend/src/services/stripe.service.ts) marks
      // the order 'paid' asynchronously; the tracking screen picks that up
      // via a Realtime subscription rather than us setting it here.
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => TrackingScreen(orderId: order.id)),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.vendor.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...widget.items.map(
              (item) => ListTile(
                title: Text(item.name),
                trailing: Text('\$${(item.unitPriceCents / 100).toStringAsFixed(2)}'),
              ),
            ),
            const Divider(),
            Text(
              'Total: \$${(_totalCents / 100).toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            FilledButton(
              onPressed: _isProcessing ? null : _payAndPlaceOrder,
              child: _isProcessing
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Pay & place order'),
            ),
          ],
        ),
      ),
    );
  }
}
