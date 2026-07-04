import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../auth/auth_provider.dart';
import '../../core/supabase_client.dart';
import 'vendor_state_provider.dart';

class VendorOnboardingScreen extends ConsumerStatefulWidget {
  const VendorOnboardingScreen({super.key});

  @override
  ConsumerState<VendorOnboardingScreen> createState() => _VendorOnboardingScreenState();
}

class _VendorOnboardingScreenState extends ConsumerState<VendorOnboardingScreen> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
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
            idempotencyKey: _idempotencyKey,
          );
      ref.invalidate(myVendorProvider);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up your storefront'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: () => supabase.auth.signOut()),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Tell customers who you are before you start taking orders.'),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Storefront name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(labelText: 'Address (optional)'),
            ),
            const SizedBox(height: 20),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            FilledButton(
              onPressed: _isSubmitting ? null : _createStorefront,
              child: _isSubmitting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create storefront'),
            ),
          ],
        ),
      ),
    );
  }
}
