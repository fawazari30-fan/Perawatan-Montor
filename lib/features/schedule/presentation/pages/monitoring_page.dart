import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/maintenance_schedule.dart';
import '../controllers/schedule_controller.dart';

class MonitoringPage extends ConsumerWidget {
  const MonitoringPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedules = ref.watch(scheduleListControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Monitoring motor')),
      body: schedules.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Data monitoring belum dapat dimuat.'),
              TextButton(
                onPressed: () =>
                    ref.read(scheduleListControllerProvider.notifier).refresh(),
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
        data: (items) => items.isEmpty
            ? const _EmptyMonitoring()
            : _MonitoringContent(schedules: items),
      ),
    );
  }
}

class _MonitoringContent extends StatelessWidget {
  const _MonitoringContent({required this.schedules});

  final List<MaintenanceSchedule> schedules;

  @override
  Widget build(BuildContext context) {
    final totalWeight = schedules.fold<double>(
      0,
      (sum, item) => sum + item.weight,
    );
    final score = totalWeight == 0
        ? 0
        : (schedules.fold<double>(
                    0,
                    (sum, item) => sum + item.remainingPct * item.weight,
                  ) /
                  totalWeight *
                  100)
              .round();
    final label = score >= 80
        ? 'Kondisi Baik'
        : score >= 60
        ? 'Perlu Perhatian'
        : 'Perlu Servis';
    final alerts = schedules
        .where(
          (item) =>
              item.status != ScheduleStatus.upcoming &&
              item.status != ScheduleStatus.snoozed,
        )
        .toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 92,
                height: 92,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: score / 100,
                      strokeWidth: 8,
                      backgroundColor: Colors.white24,
                      color: score >= 80
                          ? const Color(0xFF59D6A6)
                          : score >= 60
                          ? const Color(0xFFFFCD62)
                          : const Color(0xFFFF8C69),
                    ),
                    Center(
                      child: Text(
                        '$score',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Skor kesehatan',
                      style: TextStyle(color: Color(0xFFD5E0F0)),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${schedules.length} komponen dipantau',
                      style: const TextStyle(color: Color(0xFFD5E0F0)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (alerts.isNotEmpty) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFB66A00),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${alerts.length} jadwal perlu perhatian. Periksa daftar jadwal dan lakukan perawatan sesuai kebutuhan.',
                    style: const TextStyle(
                      color: Color(0xFF79521C),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 22),
        const Text(
          'Kondisi komponen',
          style: TextStyle(
            color: AppColors.navy,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        for (final item in schedules) ...[
          _ComponentCard(schedule: item),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ComponentCard extends StatelessWidget {
  const _ComponentCard({required this.schedule});

  final MaintenanceSchedule schedule;

  @override
  Widget build(BuildContext context) {
    final color = switch (schedule.status) {
      ScheduleStatus.overdue => const Color(0xFFC83A3A),
      ScheduleStatus.urgent => const Color(0xFFE47722),
      ScheduleStatus.dueSoon => const Color(0xFFCB8511),
      ScheduleStatus.snoozed => AppColors.muted,
      ScheduleStatus.upcoming => AppColors.green,
    };
    final percent = (schedule.remainingPct * 100).round();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  schedule.title,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                schedule.status.label,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: schedule.remainingPct.clamp(0, 1),
              minHeight: 8,
              backgroundColor: AppColors.paleBlue,
              color: color,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '$percent% sisa interval',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _EmptyMonitoring extends StatelessWidget {
  const _EmptyMonitoring();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.monitor_heart_outlined,
            size: 52,
            color: AppColors.blue,
          ),
          const SizedBox(height: 16),
          const Text(
            'Belum ada data monitoring',
            style: TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Buat jadwal perawatan agar skor kesehatan dan kondisi komponen dapat dihitung.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, height: 1.5),
          ),
        ],
      ),
    ),
  );
}
