import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/order.dart';
import '../../data/models/vendor.dart';
import 'checkout_screen.dart';

/// The schema's order_items are free-form line items (no product catalog
/// table), so the cart lets the customer add ad-hoc items directly.
class OrderCartScreen extends ConsumerStatefulWidget {
  const OrderCartScreen({super.key, required this.vendor});

  final Vendor vendor;

  @override
  ConsumerState<OrderCartScreen> createState() => _OrderCartScreenState();
}

class _OrderCartScreenState extends ConsumerState<OrderCartScreen> {
  final List<OrderItem> _items = [];
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _addressController = TextEditingController();

  int get _totalCents => _items.fold(0, (sum, item) => sum + item.quantity * item.unitPriceCents);

  void _addItem() {
    final name = _nameController.text.trim();
    final priceDollars = double.tryParse(_priceController.text.trim());
    if (name.isEmpty || priceDollars == null) return;

    setState(() {
      _items.add(OrderItem(name: name, quantity: 1, unitPriceCents: (priceDollars * 100).round()));
      _nameController.clear();
      _priceController.clear();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.vendor.name)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Item name'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _priceController,
                    decoration: const InputDecoration(labelText: 'Price (\$)'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                IconButton(icon: const Icon(Icons.add_circle), onPressed: _addItem),
              ],
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return ListTile(
                    title: Text(item.name),
                    trailing: Text('\$${(item.unitPriceCents / 100).toStringAsFixed(2)}'),
                  );
                },
              ),
            ),
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(labelText: 'Delivery address'),
            ),
            const SizedBox(height: 12),
            Text('Total: \$${(_totalCents / 100).toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _items.isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CheckoutScreen(
                            vendor: widget.vendor,
                            items: List.of(_items),
                            deliveryAddress: _addressController.text.trim(),
                          ),
                        ),
                      ),
              child: const Text('Checkout'),
            ),
          ],
        ),
      ),
    );
  }
}
