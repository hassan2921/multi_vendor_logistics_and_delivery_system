import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_provider.dart';
import '../../core/ui/formatting.dart';
import '../../core/widgets/async_views.dart';
import '../../core/widgets/network_thumbnail.dart';
import '../../core/widgets/quantity_stepper.dart';
import '../../data/models/address.dart';
import '../../data/models/order.dart';
import '../../data/models/product.dart';
import '../../data/models/vendor.dart';
import 'addresses_screen.dart';
import 'checkout_screen.dart';
import 'vendor_reviews_screen.dart';

// autoDispose: a plain .family caches one entry per vendor ever visited,
// growing for the whole session.
final _vendorProductsProvider = FutureProvider.autoDispose.family<List<Product>, String>(
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

  /// Saved address chosen from the address book; carries coordinates so the
  /// backend can quote a distance-based delivery fee and ETA.
  Address? _selectedAddress;

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
    final addresses = ref.watch(myAddressesProvider).valueOrNull ?? const <Address>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.vendor.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.reviews_outlined),
            tooltip: 'Reviews',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => VendorReviewsScreen(vendor: widget.vendor)),
            ),
          ),
        ],
      ),
      body: productsAsync.when(
        loading: () => const AppListSkeleton(),
        error: (err, _) => AppErrorView(
          error: err,
          onRetry: () => ref.invalidate(_vendorProductsProvider(widget.vendor.id)),
        ),
        data: (products) {
          if (products.isEmpty) {
            return const AppEmptyState(
              icon: Icons.restaurant_menu_rounded,
              title: 'Menu coming soon',
              subtitle: 'This vendor has no items on their menu yet.',
            );
          }

          final cart = _buildCart(products);
          final totalCents = cart.fold(0, (sum, item) => sum + item.quantity * item.unitPriceCents);
          final itemCount = cart.fold(0, (sum, item) => sum + item.quantity);

          return Column(
            children: [
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: products.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _ProductCard(
                    product: products[index],
                    quantity: _quantities[products[index].id] ?? 0,
                    onSetQuantity: (q) => _setQuantity(products[index].id, q),
                  ),
                ),
              ),
              _CheckoutBar(
                addresses: addresses,
                addressController: _addressController,
                selectedAddress: _selectedAddress,
                itemCount: itemCount,
                totalCents: totalCents,
                onAddressSelected: (address) => setState(() {
                  _selectedAddress = address;
                  if (address != null) _addressController.text = address.addressLine;
                }),
                onAddressEdited: () => setState(() {
                  // Manual edits break the link to the saved address (and its
                  // coordinates).
                  if (_selectedAddress != null &&
                      _addressController.text != _selectedAddress!.addressLine) {
                    _selectedAddress = null;
                  }
                }),
                onCheckout: cart.isEmpty || _addressController.text.trim().isEmpty
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CheckoutScreen(
                              vendor: widget.vendor,
                              items: cart,
                              deliveryAddress: _addressController.text.trim(),
                              deliveryLat: _selectedAddress?.lat,
                              deliveryLng: _selectedAddress?.lng,
                            ),
                          ),
                        ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.quantity,
    required this.onSetQuantity,
  });

  final Product product;
  final int quantity;
  final ValueChanged<int> onSetQuantity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lowStock = product.stockQuantity != null &&
        product.stockQuantity! > 0 &&
        product.stockQuantity! <= 5;
    final atMax = product.stockQuantity != null && quantity >= product.stockQuantity!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NetworkThumbnail(url: product.imageUrl, fallbackIcon: Icons.restaurant_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (product.description != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      product.description!,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    formatMoney(product.priceCents),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (product.isOutOfStock)
                    _StockTag(label: 'Out of stock', color: scheme.error)
                  else if (lowStock)
                    _StockTag(label: 'Only ${product.stockQuantity} left', color: theme.colorScheme.tertiary),
                ],
              ),
            ),
            const SizedBox(width: 12),
            QuantityStepper(
              quantity: quantity,
              onDecrement: quantity > 0 ? () => onSetQuantity(quantity - 1) : null,
              onIncrement: product.isOutOfStock || atMax ? null : () => onSetQuantity(quantity + 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockTag extends StatelessWidget {
  const _StockTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// Sticky bottom bar: address selection + running total + checkout CTA.
class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({
    required this.addresses,
    required this.addressController,
    required this.selectedAddress,
    required this.itemCount,
    required this.totalCents,
    required this.onAddressSelected,
    required this.onAddressEdited,
    required this.onCheckout,
  });

  final List<Address> addresses;
  final TextEditingController addressController;
  final Address? selectedAddress;
  final int itemCount;
  final int totalCents;
  final ValueChanged<Address?> onAddressSelected;
  final VoidCallback onAddressEdited;
  final VoidCallback? onCheckout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (addresses.isNotEmpty)
                DropdownButtonFormField<Address?>(
                  initialValue: selectedAddress,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Saved address',
                    prefixIcon: Icon(Icons.location_on_outlined),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Type manually')),
                    for (final address in addresses)
                      DropdownMenuItem(
                        value: address,
                        child: Text('${address.label} — ${address.addressLine}',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: onAddressSelected,
                ),
              if (addresses.isNotEmpty) const SizedBox(height: 12),
              TextField(
                controller: addressController,
                decoration: InputDecoration(
                  labelText: 'Delivery address *',
                  prefixIcon: const Icon(Icons.home_outlined),
                  isDense: true,
                  helperText: addressController.text.trim().isEmpty
                      ? 'Required to checkout'
                      : null,
                ),
                onChanged: (_) => onAddressEdited(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        itemCount == 0 ? 'No items' : '$itemCount item${itemCount == 1 ? '' : 's'}',
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      Text(
                        formatMoney(totalCents),
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: onCheckout,
                      child: const Text('Checkout'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
