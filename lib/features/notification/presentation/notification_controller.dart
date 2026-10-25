import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_client_provider.dart';
import '../data/notification_repository.dart';
import '../domain/notification_item.dart';

final notificationRepositoryProvider = Provider(
  (ref) => NotificationRepository(ref.watch(supabaseClientProvider)),
);

final notificationListControllerProvider =
    AsyncNotifierProvider<NotificationListController, List<NotificationItem>>(
      NotificationListController.new,
    );

final unreadNotificationCountProvider = FutureProvider<int>(
  (ref) => ref.watch(notificationRepositoryProvider).unreadCount(),
);

class NotificationListController extends AsyncNotifier<List<NotificationItem>> {
  late NotificationRepository _repository;

  @override
  Future<List<NotificationItem>> build() async {
    _repository = ref.watch(notificationRepositoryProvider);
    return _repository.getAll();
  }

  Future<void> markAllRead() async {
    await _repository.markAllRead();
    ref.invalidate(unreadNotificationCountProvider);
    state = await AsyncValue.guard(_repository.getAll);
  }

  Future<void> markRead(String id) async {
    await _repository.markRead(id);
    ref.invalidate(unreadNotificationCountProvider);
    state = await AsyncValue.guard(_repository.getAll);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repository.getAll);
  }
}
