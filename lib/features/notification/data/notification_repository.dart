import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/notification_item.dart';

class NotificationRepository {
  const NotificationRepository(this._client);

  final SupabaseClient _client;

  Future<List<NotificationItem>> getAll() async {
    final rows = await _client
        .from('notification_inbox')
        .select()
        .order('created_at', ascending: false)
        .limit(100);
    return rows
        .map((row) => NotificationItem.fromJson(row))
        .toList(growable: false);
  }

  Future<int> unreadCount() async {
    final rows = await _client
        .from('notification_inbox')
        .select('id')
        .isFilter('read_at', null);
    return rows.length;
  }

  Future<void> markAllRead() async {
    await _client.rpc('rpc_mark_all_notifications_read');
  }

  Future<void> markRead(String id) async {
    await _client
        .from('notification_inbox')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id);
  }
}
