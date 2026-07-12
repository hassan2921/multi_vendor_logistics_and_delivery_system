import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart' hide Card;
import 'package:uuid/uuid.dart';

import '../../auth/auth_provider.dart';
import '../../core/api_client.dart';
import '../../core/ui/formatting.dart';
import '../../core/widgets/async_views.dart';
import '../../data/models/order.dart';
import '../../data/models/order_quote.dart';
import '../../data/models/vendor.dart';
import 'tracking_screen.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({
    super.key,
    required this.vendor,
    required this.items,
    this.deliveryAddress,
    this.deliveryLat,
    this.deliveryLng,
  });

  final Vendor vendor;
  final List<OrderItem> items;
  final String? deliveryAddress;
  final double? deliveryLat;
  final double? deliveryLng;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  // Generated once for the lifetime of this checkout screen: if the user
  // double-taps "Pay" or retries after a network drop / cancelled payment
  // sheet, the same key is sent again and the backend replays the original
  // order instead of creating a duplicate.
  final String _idempotencyKey = const Uuid().v4();

  final _promoController = TextEditingController();

  static const _tipChoicesCents = [0, 100, 200, 500];
  int _tipCents = 0;

  /// Applied promo (validated server-side via the quote call); null = none.
  String? _promoCode;
  String? _promoError;

  OrderQuote? _quote;
  bool _isQuoting = false;
  bool _isProcessing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshQuote();
  }

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
  }

  /// Every price on this screen comes from the backend's pricing engine —
  /// the quote is re-fetched whenever the tip or promo changes so the
  /// preview always matches what createOrder will charge.
  Future<void> _refreshQuote() async {
    setState(() {
      _isQuoting = true;
      _promoError = null;
    });
    try {
      final quote = await ref.read(ordersRepositoryProvider).quote(
            vendorId: widget.vendor.id,
            items: widget.items,
            deliveryLat: widget.deliveryLat,
            deliveryLng: widget.deliveryLng,
            tipCents: _tipCents,
            promoCode: _promoCode,
          );
      setState(() => _quote = quote);
    } on ApiException catch (e) {
      if (_promoCode != null) {
        // The promo was the rejected input — drop it and show why.
        setState(() {
          _promoCode = null;
          _promoError = e.message;
        });
        unawaited(_refreshQuote());
      } else {
        setState(() => _error = e.message);
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _isQuoting = false);
    }
  }

  void _applyPromo() {
    final code = _promoController.text.trim();
    if (code.isEmpty) return;
    setState(() => _promoCode = code);
    _refreshQuote();
  }

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
        deliveryLat: widget.deliveryLat,
        deliveryLng: widget.deliveryLng,
        tipCents: _tipCents,
        promoCode: _promoCode,
        idempotencyKey: _idempotencyKey,
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
    } on StripeException catch (e) {
      // Closing the payment sheet is a normal action, not an error — the
      // order stays retryable (same idempotency key + PaymentIntent).
      if (e.error.code == FailureCode.Canceled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment cancelled — you have not been charged. Tap Pay to try again.'),
            ),
          );
        }
      } else {
        setState(() => _error = friendlyError(e));
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quote = _quote;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Order summary.
                _SectionCard(
                  title: widget.vendor.name,
                  icon: Icons.storefront_rounded,
                  child: Column(
                    children: [
                      for (final item in widget.items)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              _QtyChip(item.quantity),
                              const SizedBox(width: 10),
                              Expanded(child: Text(item.name, style: theme.textTheme.bodyLarge)),
                              Text(
                                formatMoney(item.quantity * item.unitPriceCents),
                                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Tip selector.
                Text('Add a tip for your courier',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: _tipChoicesCents
                      .map(
                        (cents) => ChoiceChip(
                          label: Text(cents == 0 ? 'No tip' : formatMoney(cents)),
                          selected: _tipCents == cents,
                          onSelected: (_) {
                            setState(() => _tipCents = cents);
                            _refreshQuote();
                          },
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 20),

                // Promo code.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _promoController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: 'Promo code',
                          prefixIcon: const Icon(Icons.local_offer_outlined),
                          errorText: _promoError,
                          suffixIcon: _promoCode != null
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    setState(() {
                                      _promoCode = null;
                                      _promoController.clear();
                                    });
                                    _refreshQuote();
                                  },
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 56,
                      child: OutlinedButton(
                        // The theme's minimumSize is Size.fromHeight (infinite
                        // width), which a Row can't satisfy — bound it here.
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
                        onPressed: _isQuoting ? null : _applyPromo,
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Server-computed price breakdown.
                _SectionCard(
                  title: 'Payment summary',
                  icon: Icons.receipt_long_rounded,
                  child: quote == null
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : Column(
                          children: [
                            _quoteRow('Subtotal', formatMoney(quote.subtotalCents)),
                            _quoteRow(
                              quote.distanceKm == null
                                  ? 'Delivery fee'
                                  : 'Delivery fee (${quote.distanceKm!.toStringAsFixed(1)} km)',
                              formatMoney(quote.deliveryFeeCents),
                            ),
                            if (quote.discountCents > 0)
                              _quoteRow('Discount (${quote.promoCode})',
                                  '-${formatMoney(quote.discountCents)}',
                                  valueColor: theme.colorScheme.tertiary),
                            if (quote.tipCents > 0) _quoteRow('Tip', formatMoney(quote.tipCents)),
                            const Divider(height: 20),
                            _quoteRow('Total', formatMoney(quote.totalCents), emphasize: true),
                            if (quote.etaMinutes != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Row(
                                  children: [
                                    Icon(Icons.schedule_rounded,
                                        size: 16, color: theme.colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Estimated delivery in ~${quote.etaMinutes} min',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  InlineError(_error!),
                ],
              ],
            ),
          ),
          _PayBar(
            label: quote == null ? 'Pay & place order' : 'Pay ${formatMoney(quote.totalCents)}',
            isProcessing: _isProcessing,
            onPay: _isProcessing || _isQuoting || quote == null ? null : _payAndPlaceOrder,
          ),
        ],
      ),
    );
  }

  Widget _quoteRow(String label, String value, {bool emphasize = false, Color? valueColor}) {
    final theme = Theme.of(context);
    final style = emphasize
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)
        : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style?.copyWith(color: valueColor)),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _QtyChip extends StatelessWidget {
  const _QtyChip(this.quantity);

  final int quantity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$quantity×',
        style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 13),
      ),
    );
  }
}

class _PayBar extends StatelessWidget {
  const _PayBar({required this.label, required this.isProcessing, required this.onPay});

  final String label;
  final bool isProcessing;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
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
          child: FilledButton(
            onPressed: onPay,
            child: isProcessing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : Text(label),
          ),
        ),
      ),
    );
  }
}
