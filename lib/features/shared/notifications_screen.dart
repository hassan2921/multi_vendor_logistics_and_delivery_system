import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_provider.dart';
import '../../core/ui/formatting.dart';
import '../../core/widgets/async_views.dart';
import '../../data/models/app_notification.dart';

/// Live in-app inbox, streamed over Supabase Realtime — no Firebase setup
/// needed. (When the backend has FCM configured, the same events also
/// arrive as system push notifications.)
final notificationsStreamProvider = StreamProvider.autoDispose<List<AppNotification>>((ref) async* {
  final appUser = await ref.watch(currentAppUserProvider.future);
  if (appUser == null) {
    yield [];
    return;
  }
  yield* ref.watch(notificationsRepositoryProvider).watchMine(appUser.id);
});

/// App-bar bell with an unread badge; reusable across role home screens.
class NotificationsBell extends ConsumerWidget {
  const NotificationsBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref
            .watch(notificationsStreamProvider)
            .valueOrNull
            ?.where((n) => !n.read)
            .length ??
        0;

    return IconButton(
      tooltip: 'Notifications',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      ),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: notificationsAsync.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => const AppListSkeleton(),
        error: (err, _) => AppErrorView(error: err),
        data: (notifications) {
          if (notifications.isEmpty) {
            return const AppEmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'No notifications',
              subtitle: "You're all caught up — nothing here yet.",
            );
          }
          final sorted = [...notifications]..sort((a, b) {
              final at = a.createdAt ?? DateTime(0);
              final bt = b.createdAt ?? DateTime(0);
              return bt.compareTo(at);
            });
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: sorted.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _NotificationCard(notification: sorted[index]),
          );
        },
      ),
    );
  }
}

class _NotificationCard extends ConsumerWidget {
  const _NotificationCard({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unread = !notification.read;

    return Card(
      child: InkWell(
        onTap: unread ? () => ref.read(notificationsRepositoryProvider).markRead(notification.id) : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: (unread ? scheme.primary : scheme.onSurfaceVariant).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  unread ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                  color: unread ? scheme.primary : scheme.onSurfaceVariant,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (unread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 8, top: 4),
                            decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.body,
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    if (notification.createdAt != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        timeAgo(notification.createdAt!),
                        style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
