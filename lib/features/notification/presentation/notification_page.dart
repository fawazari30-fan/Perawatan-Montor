import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/notification_item.dart';
import 'notification_controller.dart';

class NotificationPage extends ConsumerWidget {
  const NotificationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationListControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifikasi'),
        actions: [
          TextButton(
            onPressed:
                notifications.valueOrNull?.any((item) => !item.isRead) != true
                ? null
                : () => ref
                      .read(notificationListControllerProvider.notifier)
                      .markAllRead(),
            child: const Text('Tandai dibaca'),
          ),
        ],
      ),
      body: notifications.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Notifikasi belum dapat dimuat.'),
              TextButton(
                onPressed: () => ref
                    .read(notificationListControllerProvider.notifier)
                    .refresh(),
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
        data: (items) => items.isEmpty
            ? const _EmptyNotifications()
            : _NotificationList(items: items),
      ),
    );
  }
}

class _NotificationList extends ConsumerWidget {
  const _NotificationList({required this.items});

  final List<NotificationItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateUtils.dateOnly(DateTime.now());
    final todayItems = items
        .where((item) => DateUtils.isSameDay(item.createdAt, today))
        .toList();
    final previousItems = items
        .where((item) => !DateUtils.isSameDay(item.createdAt, today))
        .toList();
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(notificationListControllerProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (todayItems.isNotEmpty) ...[
            const _SectionTitle('Hari ini'),
            for (final item in todayItems) _NotificationTile(item: item),
          ],
          if (previousItems.isNotEmpty) ...[
            const _SectionTitle('Sebelumnya'),
            for (final item in previousItems) _NotificationTile(item: item),
          ],
        ],
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.item});

  final NotificationItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    color: item.isRead ? Colors.white : AppColors.paleBlue,
    child: ListTile(
      onTap: () async {
        if (!item.isRead) {
          await ref
              .read(notificationListControllerProvider.notifier)
              .markRead(item.id);
        }
        if (context.mounted) {
          context.go(item.scheduleId == null ? '/home' : '/schedules');
        }
      },
      leading: Icon(
        item.type == 'odometer'
            ? Icons.speed_rounded
            : Icons.build_circle_outlined,
        color: AppColors.blue,
      ),
      title: Text(
        item.title,
        style: TextStyle(
          fontWeight: item.isRead ? FontWeight.w600 : FontWeight.w800,
          color: AppColors.navy,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '${item.body}\n${DateFormat('d MMM, HH:mm', 'id_ID').format(item.createdAt)}',
        ),
      ),
      isThreeLine: true,
      trailing: item.isRead
          ? null
          : const Icon(Icons.circle, size: 10, color: AppColors.blue),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
    child: Text(
      title,
      style: const TextStyle(
        color: AppColors.navy,
        fontWeight: FontWeight.w800,
        fontSize: 16,
      ),
    ),
  );
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 52,
            color: AppColors.blue,
          ),
          SizedBox(height: 14),
          Text(
            'Belum ada notifikasi',
            style: TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Pengingat perawatan akan muncul di sini.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}
