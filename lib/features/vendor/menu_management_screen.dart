import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_provider.dart';
import '../../data/models/product.dart';

final myProductsProvider = FutureProvider.autoDispose((ref) => ref.watch(vendorsRepositoryProvider).listMyProducts());

class MenuManagementScreen extends ConsumerWidget {
  const MenuManagementScreen({super.key});

  Future<void> _showAddProductDialog(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final descriptionController = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add menu item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
            TextField(
              controller: priceController,
              decoration: const InputDecoration(labelText: 'Price (\$)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Add')),
        ],
      ),
    );

    if (created != true) return;

    final priceDollars = double.tryParse(priceController.text.trim());
    if (nameController.text.trim().isEmpty || priceDollars == null) return;

    await ref.read(vendorsRepositoryProvider).createProduct(
          name: nameController.text.trim(),
          priceCents: (priceDollars * 100).round(),
          description: descriptionController.text.trim().isEmpty ? null : descriptionController.text.trim(),
        );
    ref.invalidate(myProductsProvider);
  }

  Future<void> _togglePrice(BuildContext context, WidgetRef ref, Product product) async {
    final controller = TextEditingController(text: (product.priceCents / 100).toStringAsFixed(2));
    final newPrice = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update price for ${product.name}'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Price (\$)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(double.tryParse(controller.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newPrice == null) return;
    await ref.read(vendorsRepositoryProvider).updateProduct(product.id, priceCents: (newPrice * 100).round());
    ref.invalidate(myProductsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(myProductsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage menu'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(myProductsProvider)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddProductDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: productsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load menu: $err')),
        data: (products) {
          if (products.isEmpty) {
            return const Center(child: Text('No menu items yet. Tap + to add one.'));
          }
          return ListView.builder(
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return ListTile(
                title: Text(product.name),
                subtitle: product.description != null ? Text(product.description!) : null,
                onTap: () => _togglePrice(context, ref, product),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('\$${(product.priceCents / 100).toStringAsFixed(2)}'),
                    Switch(
                      value: product.isAvailable,
                      onChanged: (value) async {
                        await ref
                            .read(vendorsRepositoryProvider)
                            .updateProduct(product.id, isAvailable: value);
                        ref.invalidate(myProductsProvider);
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
