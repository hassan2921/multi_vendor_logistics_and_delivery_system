import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../auth/auth_provider.dart';
import '../../core/supabase_client.dart';
import '../../core/ui/formatting.dart';
import '../../core/widgets/async_views.dart';
import 'vendor_state_provider.dart';

class VendorOnboardingScreen extends ConsumerStatefulWidget {
  const VendorOnboardingScreen({super.key});

  @override
  ConsumerState<VendorOnboardingScreen> createState() => _VendorOnboardingScreenState();
}

class _VendorOnboardingScreenState extends ConsumerState<VendorOnboardingScreen> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _imageUrlController = TextEditingController();
  // Onboarding is idempotency-protected server-side, so a retried submit
  // (e.g. after a dropped response) can't create two storefronts.
  final String _idempotencyKey = const Uuid().v4();

  bool _isSubmitting = false;
  String? _error;

  Future<void> _createStorefront() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Storefront name is required');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await ref.read(vendorsRepositoryProvider).onboard(
            name: name,
            address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
            imageUrl: _imageUrlController.text.trim().isEmpty ? null : _imageUrlController.text.trim(),
            idempotencyKey: _idempotencyKey,
          );
      ref.invalidate(myVendorProvider);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up your storefront'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: () => supabase.auth.signOut()),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(Icons.storefront_rounded, size: 34, color: theme.colorScheme.primary),
                ),
                const SizedBox(height: 20),
                Text(
                  'Welcome aboard!',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tell customers who you are before you start taking orders.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Storefront name',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _addressController,
                          decoration: const InputDecoration(
                            labelText: 'Address (optional)',
                            prefixIcon: Icon(Icons.location_on_outlined),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _imageUrlController,
                          decoration: const InputDecoration(
                            labelText: 'Cover photo URL (optional)',
                            prefixIcon: Icon(Icons.image_outlined),
                          ),
                          keyboardType: TextInputType.url,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          InlineError(_error!),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _isSubmitting ? null : _createStorefront,
                          child: _isSubmitting
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                )
                              : const Text('Create storefront'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
