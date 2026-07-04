import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_provider.dart';
import '../../data/models/order.dart';
import '../../data/models/product.dart';
import '../../data/models/vendor.dart';
import 'checkout_screen.dart';

final _vendorProductsProvider = FutureProvider.family<List<Product>, String>(
  (ref, vendorId) => ref.watch(vendorsRepositoryProvider).listProducts(vendorId),
);

class OrderCartScreen extends ConsumerStatefulWidget {
  const OrderCartScreen({super.key, required this.vendor});

  final Vendor vendor;

  @override
  ConsumerState<OrderCartScreen> createState() => _OrderCartScreenState();
}

class _OrderCartScreenState extends ConsumerState<OrderCartScreen> {
  // productId -> quantity
  final Map<String, int> _quantities = {};
  final _addressController = TextEditingController();

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  void _setQuantity(String productId, int quantity) {
    setState(() {
      if (quantity <= 0) {
        _quantities.remove(productId);
      } else {
        _quantities[productId] = quantity;
      }
    });
  }

  List<OrderItem> _buildCart(List<Product> products) {
    final byId = {for (final p in products) p.id: p};
    return _quantities.entries
        .where((e) => byId.containsKey(e.key))
        .map((e) => OrderItem(
              productId: e.key,
              name: byId[e.key]!.name,
              quantity: e.value,
              unitPriceCents: byId[e.key]!.priceCents,
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(_vendorProductsProvider(widget.vendor.id));

    return Scaffold(
      appBar: AppBar(title: Text(widget.vendor.name)),
      body: productsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load menu: $err')),
        data: (products) {
          if (products.isEmpty) {
            return const Center(child: Text('This vendor has no items on their menu yet.'));
          }

          final cart = _buildCart(products);
          final totalCents = cart.fold(0, (sum, item) => sum + item.quantity * item.unitPriceCents);

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    final quantity = _quantities[product.id] ?? 0;
                    return ListTile(
                      title: Text(product.name),
                      subtitle: product.description != null ? Text(product.description!) : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('\$${(product.priceCents / 100).toStringAsFixed(2)}'),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: quantity > 0 ? () => _setQuantity(product.id, quantity - 1) : null,
                          ),
                          Text('$quantity'),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => _setQuantity(product.id, quantity + 1),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _addressController,
                      decoration: const InputDecoration(labelText: 'Delivery address'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Total: \$${(totalCents / 100).toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: cart.isEmpty
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CheckoutScreen(
                                    vendor: widget.vendor,
                                    items: cart,
                                    deliveryAddress: _addressController.text.trim(),
                                  ),
                                ),
                              ),
                      child: const Text('Checkout'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
