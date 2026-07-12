import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/formatting.dart';
import '../../core/widgets/async_views.dart';

final connectStatusProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(vendorsRepositoryProvider).refreshConnectStatus(),
);

/// Stripe Connect onboarding for vendor payouts. The backend creates the
/// Express account + hosted onboarding link; the vendor opens it in a
/// browser, and this screen re-checks status afterwards.
class PayoutsScreen extends ConsumerStatefulWidget {
  const PayoutsScreen({super.key});

  @override
  ConsumerState<PayoutsScreen> createState() => _PayoutsScreenState();
}

class _PayoutsScreenState extends ConsumerState<PayoutsScreen> {
  bool _isRequestingLink = false;

  Future<void> _startOnboarding() async {
    setState(() => _isRequestingLink = true);
    try {
      final url = await ref.read(vendorsRepositoryProvider).startConnectOnboarding();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Complete Stripe onboarding'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Open this link in a browser to set up your payout account:'),
              const SizedBox(height: 12),
              SelectableText(url, style: const TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url));
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Copy link'),
            ),
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
          ],
        ),
      );
      ref.invalidate(connectStatusProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not start onboarding: ${friendlyError(e)}')));
      }
    } finally {
      if (mounted) setState(() => _isRequestingLink = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusAsync = ref.watch(connectStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payouts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Re-check status',
            onPressed: () => ref.invalidate(connectStatusProvider),
          ),
        ],
      ),
      body: statusAsync.when(
        loading: () => const AppLoading(),
        error: (err, _) => AppErrorView(error: err, onRetry: () => ref.invalidate(connectStatusProvider)),
        data: (payoutsEnabled) {
          final accent = payoutsEnabled ? AppColors.success : AppColors.warning;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              payoutsEnabled ? Icons.verified_rounded : Icons.warning_amber_rounded,
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              payoutsEnabled ? 'Payouts enabled' : 'Payouts not set up',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        payoutsEnabled
                            ? 'Your share of each delivered order is transferred to your Stripe account automatically.'
                            : 'Until onboarding is complete, your earnings are held by the platform.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (!payoutsEnabled)
                FilledButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: Text(_isRequestingLink ? 'Preparing link…' : 'Set up payouts with Stripe'),
                  onPressed: _isRequestingLink ? null : _startOnboarding,
                ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 20, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'How you get paid: for every delivered order you receive the item subtotal '
                        'minus the platform commission. Delivery fees and tips go to the courier.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
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
