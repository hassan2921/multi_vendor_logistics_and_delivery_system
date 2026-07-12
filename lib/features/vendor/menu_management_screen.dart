import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_provider.dart';
import '../../core/ui/formatting.dart';
import '../../core/widgets/async_views.dart';
import '../../core/widgets/network_thumbnail.dart';
import '../../data/models/product.dart';

final myProductsProvider = FutureProvider.autoDispose((ref) => ref.watch(vendorsRepositoryProvider).listMyProducts());

/// Prompts for a new price and persists it. Shared by the product card tap.
Future<void> _editProductPrice(BuildContext context, WidgetRef ref, Product product) async {
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

class MenuManagementScreen extends ConsumerWidget {
  const MenuManagementScreen({super.key});

  Future<void> _showAddProductDialog(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final descriptionController = TextEditingController();
    final categoryController = TextEditingController();
    final stockController = TextEditingController();
    final imageUrlController = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add menu item'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 12),
              TextField(
                controller: priceController,
                decoration: const InputDecoration(labelText: 'Price (\$)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: 'Description (optional)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: categoryController,
                decoration: const InputDecoration(labelText: 'Category (optional)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: stockController,
                decoration: const InputDecoration(
                  labelText: 'Stock (optional)',
                  helperText: 'Leave empty for unlimited',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: imageUrlController,
                decoration: const InputDecoration(labelText: 'Photo URL (optional)'),
                keyboardType: TextInputType.url,
              ),
            ],
          ),
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
          category: categoryController.text.trim().isEmpty ? null : categoryController.text.trim(),
          stockQuantity: int.tryParse(stockController.text.trim()),
          imageUrl: imageUrlController.text.trim().isEmpty ? null : imageUrlController.text.trim(),
        );
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddProductDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
      body: productsAsync.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => const AppListSkeleton(),
        error: (err, _) => AppErrorView(error: err, onRetry: () => ref.invalidate(myProductsProvider)),
        data: (products) {
          if (products.isEmpty) {
            return const AppEmptyState(
              icon: Icons.restaurant_menu_rounded,
              title: 'Your menu is empty',
              subtitle: 'Tap "Add item" to create your first menu item.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: products.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _ProductCard(product: products[index]),
          );
        },
      ),
    );
  }
}

class _ProductCard extends ConsumerWidget {
  const _ProductCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final details = [
      if (product.category != null) product.category!,
      if (product.stockQuantity != null) 'Stock: ${product.stockQuantity}',
    ].join('  ·  ');

    return Card(
      child: InkWell(
        onTap: () => _editProductPrice(context, ref, product),
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
                      const SizedBox(height: 2),
                      Text(
                        product.description!,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(details,
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          formatMoney(product.priceCents),
                          style: theme.textTheme.titleSmall
                              ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.edit_outlined, size: 14, color: scheme.onSurfaceVariant),
                        if (!product.isAvailable) ...[
                          const SizedBox(width: 10),
                          Text('Hidden',
                              style: theme.textTheme.labelMedium
                                  ?.copyWith(color: scheme.error, fontWeight: FontWeight.w600)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Switch(
                    value: product.isAvailable,
                    onChanged: (value) async {
                      await ref.read(vendorsRepositoryProvider).updateProduct(product.id, isAvailable: value);
                      ref.invalidate(myProductsProvider);
                    },
                  ),
                  if (product.stockQuantity != null)
                    TextButton.icon(
                      onPressed: () async {
                        await ref.read(vendorsRepositoryProvider).updateProduct(
                              product.id,
                              stockQuantity: product.stockQuantity! + 10,
                            );
                        ref.invalidate(myProductsProvider);
                      },
                      icon: const Icon(Icons.add_box_outlined, size: 18),
                      label: const Text('Restock'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
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
