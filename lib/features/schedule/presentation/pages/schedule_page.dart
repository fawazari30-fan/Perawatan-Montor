import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/maintenance_schedule.dart';
import '../controllers/schedule_controller.dart';

class SchedulePage extends ConsumerWidget {
  const SchedulePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedules = ref.watch(scheduleListControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Jadwal perawatan')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/schedules/new'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Buat jadwal'),
      ),
      body: schedules.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Jadwal belum dapat dimuat.'),
              TextButton(
                onPressed: () =>
                    ref.read(scheduleListControllerProvider.notifier).refresh(),
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
        data: (items) => items.isEmpty
            ? const _EmptySchedules()
            : RefreshIndicator(
                onRefresh: () =>
                    ref.read(scheduleListControllerProvider.notifier).refresh(),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) =>
                      _ScheduleCard(schedule: items[index]),
                ),
              ),
      ),
    );
  }
}

class _EmptySchedules extends StatelessWidget {
  const _EmptySchedules();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.event_available_rounded,
            size: 52,
            color: AppColors.blue,
          ),
          const SizedBox(height: 16),
          const Text(
            'Belum ada jadwal perawatan',
            style: TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Buat jadwal agar Anda mendapat pengingat sebelum servis berikutnya.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => context.push('/schedules/new'),
            child: const Text('Buat jadwal pertama'),
          ),
        ],
      ),
    ),
  );
}

class _ScheduleCard extends ConsumerWidget {
  const _ScheduleCard({required this.schedule});

  final MaintenanceSchedule schedule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = switch (schedule.status) {
      ScheduleStatus.overdue => const Color(0xFFC83A3A),
      ScheduleStatus.urgent => const Color(0xFFE47722),
      ScheduleStatus.dueSoon => const Color(0xFFCB8511),
      ScheduleStatus.snoozed => AppColors.muted,
      ScheduleStatus.upcoming => AppColors.green,
    };
    final date = schedule.nextDueDate == null
        ? null
        : DateFormat('d MMM yyyy', 'id_ID').format(schedule.nextDueDate!);
    final kmLeft = schedule.kmLeft;
    final kmDescription = kmLeft == null
        ? null
        : kmLeft < 0
        ? 'Lewat ${NumberFormat.decimalPattern('id_ID').format(kmLeft.abs())} km'
        : '$kmLeft km lagi';
    final snoozeDescription =
        schedule.status == ScheduleStatus.snoozed &&
            schedule.snoozedUntil != null
        ? 'Ditunda sampai ${DateFormat('d MMM', 'id_ID').format(schedule.snoozedUntil!)}'
        : null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.build_circle_outlined, color: color),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      schedule.title,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      [?date, ?kmDescription, ?snoozeDescription].join(' • '),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Kelola jadwal',
                onSelected: (action) => _handleAction(context, ref, action),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit jadwal')),
                  PopupMenuItem(value: 'snooze_1', child: Text('Tunda 1 hari')),
                  PopupMenuItem(value: 'snooze_3', child: Text('Tunda 3 hari')),
                  PopupMenuItem(value: 'snooze_7', child: Text('Tunda 7 hari')),
                  PopupMenuItem(
                    value: 'deactivate',
                    child: Text('Nonaktifkan jadwal'),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  schedule.status.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => context.push('/records/new', extra: schedule),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: const Text('Tandai selesai'),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    if (action == 'edit') {
      await context.push('/schedules/${schedule.id}/edit', extra: schedule);
      return;
    }
    if (action.startsWith('snooze_')) {
      final days = int.parse(action.substring('snooze_'.length));
      final result = await ref
          .read(scheduleListControllerProvider.notifier)
          .snoozeSchedule(schedule.id, days);
      if (!context.mounted) return;
      result.match(
        (failure) =>
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(failure.message))),
        (_) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pengingat ditunda selama $days hari.')),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nonaktifkan jadwal?'),
        content: Text('Pengingat “${schedule.title}” akan dihentikan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Nonaktifkan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await ref
        .read(scheduleListControllerProvider.notifier)
        .deactivateSchedule(schedule.id);
    if (!context.mounted) return;
    result.match(
      (failure) =>
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(failure.message))),
      (_) => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jadwal berhasil dinonaktifkan.')),
      ),
    );
  }
}
