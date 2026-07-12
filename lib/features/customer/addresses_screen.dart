import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_provider.dart';
import '../../core/widgets/async_views.dart';
import '../../data/models/address.dart';

final myAddressesProvider =
    FutureProvider.autoDispose((ref) => ref.watch(addressesRepositoryProvider).listMine());

class AddressesScreen extends ConsumerWidget {
  const AddressesScreen({super.key});

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    final labelController = TextEditingController();
    final lineController = TextEditingController();
    var makeDefault = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add address'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                decoration: const InputDecoration(labelText: 'Label (Home, Work…)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: lineController,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              const SizedBox(height: 4),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Set as default'),
                value: makeDefault,
                onChanged: (v) => setDialogState(() => makeDefault = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (saved != true) return;
    final label = labelController.text.trim();
    final line = lineController.text.trim();
    if (label.isEmpty || line.isEmpty) return;

    await ref.read(addressesRepositoryProvider).create(
          label: label,
          addressLine: line,
          isDefault: makeDefault,
        );
    ref.invalidate(myAddressesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addressesAsync = ref.watch(myAddressesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My addresses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: addressesAsync.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => const AppListSkeleton(),
        error: (err, _) => AppErrorView(error: err, onRetry: () => ref.invalidate(myAddressesProvider)),
        data: (addresses) {
          if (addresses.isEmpty) {
            return const AppEmptyState(
              icon: Icons.location_on_outlined,
              title: 'No saved addresses',
              subtitle: 'Tap the + button to add your first delivery address.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: addresses.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _AddressCard(address: addresses[index]),
          );
        },
      ),
    );
  }
}

class _AddressCard extends ConsumerWidget {
  const _AddressCard({required this.address});

  final Address address;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final repo = ref.read(addressesRepositoryProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                address.isDefault ? Icons.home_rounded : Icons.location_on_outlined,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          address.label,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (address.isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Default',
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    address.addressLine,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (!address.isDefault)
              IconButton(
                icon: const Icon(Icons.star_outline_rounded),
                tooltip: 'Make default',
                onPressed: () async {
                  await repo.setDefault(address.id);
                  ref.invalidate(myAddressesProvider);
                },
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Delete',
              color: scheme.error,
              onPressed: () async {
                await repo.delete(address.id);
                ref.invalidate(myAddressesProvider);
              },
            ),
          ],
        ),
      ),
    );
  }
}
