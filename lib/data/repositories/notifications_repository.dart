import '../../core/api_client.dart';
import '../../core/supabase_client.dart';
import '../models/app_notification.dart';

class NotificationsRepository {
  const NotificationsRepository(this._api);

  final ApiClient _api;

  Future<List<AppNotification>> listMine() async {
    final res = await _api.get('/notifications');
    return (res['notifications'] as List<dynamic>)
        .map((n) => AppNotification.fromJson(n as Map<String, dynamic>))
        .toList();
  }

  Future<void> markRead(String notificationId) async {
    await _api.post('/notifications/$notificationId/read', {});
  }

  /// Registers this device for FCM push (backend skips sending if Firebase
  /// isn't configured server-side, so calling this is always safe).
  Future<void> registerDeviceToken(String token, {String platform = 'android'}) async {
    await _api.post('/notifications/device-token', {'token': token, 'platform': platform});
  }

  /// Live inbox for the signed-in user via Supabase Realtime — this is what
  /// makes in-app notifications work with zero Firebase setup. RLS restricts
  /// the stream to the user's own rows.
  Stream<List<AppNotification>> watchMine(String appUserId) {
    return supabase
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', appUserId)
        .order('created_at')
        .map((rows) => rows.map(AppNotification.fromJson).toList());
  }
}
