import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/providers/supabase_client_provider.dart';
import '../../../core/cache/offline_cache.dart';
import '../../schedule/data/local_schedule_notifications.dart';
import '../../notification/presentation/notification_controller.dart';
import '../../notification/data/push_notification_service.dart';
import '../../schedule/domain/entities/maintenance_schedule.dart';
import '../../schedule/presentation/controllers/schedule_controller.dart';
import '../../auth/presentation/controllers/auth_controller.dart';
import '../../motorcycle/domain/entities/motorcycle.dart';
import '../../motorcycle/presentation/controllers/motorcycle_controller.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(supabaseClientProvider).auth.currentUser;
    final firstName = (user?.userMetadata?['full_name'] as String? ?? '')
        .trim()
        .split(' ')
        .first;
    final hour = DateTime.now().hour;
    final greeting = hour < 11
        ? 'Selamat pagi'
        : hour < 15
        ? 'Selamat siang'
        : hour < 18
        ? 'Selamat sore'
        : 'Selamat malam';
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Rawat Motor',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          Consumer(
            builder: (context, ref, child) {
              final unread =
                  ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;
              return IconButton(
                tooltip: 'Notifikasi',
                onPressed: () => context.push('/notifications'),
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text('$unread'),
                  child: const Icon(Icons.notifications_none_rounded),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Profil dan pengaturan',
            onPressed: () => context.push('/profile'),
            icon: const Icon(Icons.account_circle_outlined),
          ),
          IconButton(
            tooltip: 'Keluar dari akun',
            onPressed: () => _confirmSignOut(context, ref),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const _OfflineBanner(),
          Text(
            '$greeting${firstName.isEmpty ? '' : ', $firstName'} 👋',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Siap menjaga motor tetap prima?',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 24),
          const _MotorcycleSection(),
          const SizedBox(height: 24),
          const _UpcomingMaintenanceSection(),
          const SizedBox(height: 24),
          Text(
            'Mulai dari sini',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          _NextStepCard(
            icon: Icons.event_note_rounded,
            title: 'Buat jadwal perawatan',
            subtitle: 'Atur pengingat berdasarkan kilometer atau waktu.',
            onTap: () => context.push('/schedules'),
          ),
          const SizedBox(height: 10),
          _NextStepCard(
            icon: Icons.receipt_long_rounded,
            title: 'Riwayat servis',
            subtitle: 'Catat tanggal, odometer, bengkel, dan biaya servis.',
            onTap: () => context.push('/records'),
          ),
          const SizedBox(height: 10),
          _NextStepCard(
            icon: Icons.monitor_heart_outlined,
            title: 'Pantau kondisi motor',
            subtitle: 'Lihat komponen yang perlu mendapat perhatian.',
            onTap: () => context.push('/monitoring'),
          ),
          const SizedBox(height: 18),
          const _MaintenanceTipCard(),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keluar dari akun?'),
        content: const Text('Anda perlu masuk kembali untuk mengakses data.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await LocalScheduleNotifications.instance.cancelAll();
      await PushNotificationService.unregisterCurrentDevice(
        ref.read(supabaseClientProvider),
      );
      final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
      if (userId != null) await OfflineCache.clearUser(userId);
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }
}

class _OfflineBanner extends ConsumerWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder(
    future: Connectivity().checkConnectivity(),
    builder: (context, snapshot) {
      if (!snapshot.hasData ||
          !snapshot.data!.contains(ConnectivityResult.none)) {
        return const SizedBox.shrink();
      }
      final userId = ref.watch(supabaseClientProvider).auth.currentUser?.id;
      final lastSynced = userId == null
          ? Future<DateTime?>.value(null)
          : OfflineCache.lastSyncedAt(userId, 'motorcycles');
      return FutureBuilder<DateTime?>(
        future: lastSynced,
        builder: (context, syncSnapshot) => Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF5DF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.cloud_off_outlined, color: Color(0xFF9C6A00)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  syncSnapshot.data == null
                      ? 'Offline. Menampilkan data terakhir yang tersimpan.'
                      : 'Offline. Data terakhir disinkronkan pukul ${DateFormat('HH:mm').format(syncSnapshot.data!)}.',
                  style: const TextStyle(color: Color(0xFF705315)),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _UpcomingMaintenanceSection extends ConsumerWidget {
  const _UpcomingMaintenanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedules = ref.watch(scheduleListControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Perawatan selanjutnya',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        schedules.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, stack) => const Text(
            'Jadwal belum dapat dimuat. Buka menu Jadwal untuk mencoba lagi.',
            style: TextStyle(color: AppColors.muted),
          ),
          data: (items) {
            if (items.isEmpty) {
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.event_available_outlined),
                  title: const Text('Belum ada jadwal perawatan'),
                  subtitle: const Text('Buat jadwal agar motor terawat.'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/schedules'),
                ),
              );
            }
            final nearest = [...items]
              ..sort((a, b) => a.remainingPct.compareTo(b.remainingPct));
            return Column(
              children: [
                for (final schedule in nearest.take(3))
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      onTap: () => context.push('/schedules'),
                      leading: Icon(
                        Icons.build_circle_outlined,
                        color: _scheduleColor(schedule.status),
                      ),
                      title: Text(schedule.title),
                      subtitle: Text(_dueSummary(schedule)),
                      trailing: const Icon(Icons.chevron_right_rounded),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.push('/schedules'),
                    child: const Text('Lihat semua jadwal'),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Color _scheduleColor(ScheduleStatus status) => switch (status) {
    ScheduleStatus.overdue => const Color(0xFFC83A3A),
    ScheduleStatus.urgent => const Color(0xFFE47722),
    ScheduleStatus.dueSoon => const Color(0xFFCB8511),
    ScheduleStatus.snoozed => AppColors.muted,
    ScheduleStatus.upcoming => AppColors.green,
  };

  String _dueSummary(MaintenanceSchedule schedule) {
    final parts = <String>[];
    final dueDate = schedule.nextDueDate;
    final days = dueDate == null
        ? null
        : DateUtils.dateOnly(dueDate)
              .difference(DateUtils.dateOnly(DateTime.now()))
              .inDays;
    if (days != null) {
      parts.add(days <= 0 ? 'Jatuh tempo hari ini' : '$days hari lagi');
    }
    final km = schedule.kmLeft;
    if (km != null) parts.add(km <= 0 ? 'Lewat ${km.abs()} km' : '$km km lagi');
    return parts.isEmpty ? schedule.status.label : parts.join(' • ');
  }
}

class _MaintenanceTipCard extends StatelessWidget {
  const _MaintenanceTipCard();

  static const _tips = [
    'Periksa tekanan ban secara berkala agar motor lebih stabil dan irit.',
    'Catat odometer setiap mengisi bahan bakar supaya pengingat km tetap akurat.',
    'Periksa ketebalan kampas rem saat servis berkala.',
  ];

  @override
  Widget build(BuildContext context) {
    final tip = _tips[DateTime.now().day % _tips.length];
    return Card(
      color: AppColors.paleBlue,
      child: ListTile(
        leading: const Icon(
          Icons.lightbulb_outline_rounded,
          color: AppColors.blue,
        ),
        title: const Text(
          'Tips perawatan',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(tip),
      ),
    );
  }
}

Future<void> _showUpdateOdometer(
  BuildContext context,
  WidgetRef ref,
  Motorcycle motorcycle,
) async {
  final input = TextEditingController(text: motorcycle.odometerKm.toString());
  var errorMessage = '';
  var isSaving = false;
  var updated = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Perbarui odometer',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.navy,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Angka terakhir: ${NumberFormat.decimalPattern('id_ID').format(motorcycle.odometerKm)} km',
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: input,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Odometer saat ini',
                suffixText: 'km',
              ),
            ),
            if (errorMessage.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                errorMessage,
                style: const TextStyle(color: Color(0xFF8C3232)),
              ),
            ],
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final km = int.tryParse(input.text);
                      if (km == null || km < 0) {
                        setSheetState(
                          () => errorMessage =
                              'Masukkan angka odometer yang valid.',
                        );
                        return;
                      }
                      if (km < motorcycle.odometerKm) {
                        setSheetState(
                          () => errorMessage = 'Odometer tidak boleh turun. Gunakan Edit motor untuk koreksi.',
                        );
                        return;
                      }
                      if (km - motorcycle.odometerKm > 1000) {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Pastikan angka odometer'),
                            content: const Text(
                              'Kenaikan lebih dari 1.000 km. Apakah angka ini sudah benar?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text('Periksa lagi'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                child: const Text('Ya, benar'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                      }

                      setSheetState(() {
                        isSaving = true;
                        errorMessage = '';
                      });
                      final result = await ref
                          .read(motorcycleListControllerProvider.notifier)
                          .updateOdometer(id: motorcycle.id, km: km);
                      if (!context.mounted) return;
                      result.match(
                        (failure) => setSheetState(() {
                          isSaving = false;
                          errorMessage = failure.message;
                        }),
                        (_) {
                          updated = true;
                          Navigator.of(sheetContext).pop();
                        },
                      );
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Simpan odometer'),
            ),
          ],
        ),
      ),
    ),
  );

  input.dispose();
  if (updated && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Odometer berhasil diperbarui.')),
    );
  }
}

Future<void> _deleteMotorcycle(
  BuildContext context,
  WidgetRef ref,
  Motorcycle motorcycle,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Hapus motor?'),
      content: Text(
        'Data ${motorcycle.displayName} akan disembunyikan dari akun Anda.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Hapus'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final result = await ref
      .read(motorcycleListControllerProvider.notifier)
      .deleteMotorcycle(motorcycle.id);
  if (!context.mounted) return;
  result.match(
    (failure) =>
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message))),
    (_) => ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Motor berhasil dihapus.'))),
  );
}

class _MotorcycleSection extends ConsumerWidget {
  const _MotorcycleSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(motorcycleListControllerProvider)
        .when(
          loading: () => const _LoadingCard(),
          error: (error, stack) => _ErrorCard(
            onRetry: () =>
                ref.read(motorcycleListControllerProvider.notifier).refresh(),
          ),
          data: (items) {
            if (items.isEmpty) return const _EmptyMotorcycleCard();
            final activeId = ref.watch(activeMotorcycleIdProvider);
            final selected = items.firstWhere(
              (motor) => motor.id == activeId,
              orElse: () => items.first,
            );
            return _MotorcycleCard(
              motorcycle: selected,
              items: items,
              activeId: selected.id,
              onSelect: (id) async {
                if (id == null) return;
                final result = await ref
                    .read(motorcycleListControllerProvider.notifier)
                    .setActiveMotorcycle(id);
                if (context.mounted) {
                  result.match(
                    (failure) => ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(failure.message))),
                    (_) {},
                  );
                }
              },
              onAdd: () => context.push('/motorcycles/new'),
              onEdit: () => context.push(
                '/motorcycles/${selected.id}/edit',
                extra: selected,
              ),
              onUpdateOdometer: () =>
                  _showUpdateOdometer(context, ref, selected),
              onDelete: () => _deleteMotorcycle(context, ref, selected),
            );
          },
        );
  }
}

class _MotorcycleCard extends StatelessWidget {
  const _MotorcycleCard({
    required this.motorcycle,
    required this.items,
    required this.activeId,
    required this.onSelect,
    required this.onAdd,
    required this.onEdit,
    required this.onUpdateOdometer,
    required this.onDelete,
  });

  final Motorcycle motorcycle;
  final List<Motorcycle> items;
  final String activeId;
  final ValueChanged<String?> onSelect;
  final VoidCallback onAdd;
  final VoidCallback onEdit;
  final VoidCallback onUpdateOdometer;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final km = NumberFormat.decimalPattern('id_ID')
        .format(motorcycle.odometerKm);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _MotorcyclePhoto(path: motorcycle.photoPath),
              const Spacer(),
              if (items.length > 1)
                DropdownButton<String>(
                  value: activeId,
                  dropdownColor: AppColors.navy,
                  underline: const SizedBox.shrink(),
                  iconEnabledColor: Colors.white,
                  style: const TextStyle(color: Colors.white),
                  items: items
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: onSelect,
                ),
              PopupMenuButton<String>(
                tooltip: 'Kelola motor',
                iconColor: Colors.white,
                onSelected: (action) {
                  switch (action) {
                    case 'edit':
                      onEdit();
                    case 'odometer':
                      onUpdateOdometer();
                    case 'delete':
                      onDelete();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit motor')),
                  PopupMenuItem(
                    value: 'odometer',
                    child: Text('Perbarui odometer'),
                  ),
                  PopupMenuItem(value: 'delete', child: Text('Hapus motor')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            motorcycle.displayName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${motorcycle.plateNumber}  •  ${motorcycle.year}  •  ${motorcycle.type.label}',
            style: const TextStyle(color: Color(0xFFD5E0F0)),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Icon(
                Icons.speed_rounded,
                color: Color(0xFFD5E0F0),
                size: 19,
              ),
              const SizedBox(width: 8),
              Text(
                '$km km',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onAdd,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Tambah motor'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MotorcyclePhoto extends StatelessWidget {
  const _MotorcyclePhoto({this.path});
  final String? path;

  @override
  Widget build(BuildContext context) {
    final photoPath = path;
    if (photoPath == null) {
      return const Icon(
        Icons.two_wheeler_rounded,
        color: Colors.white,
        size: 30,
      );
    }
    return FutureBuilder<String>(
      future: Supabase.instance.client.storage
          .from('motorcycle-photos')
          .createSignedUrl(photoPath, 3600),
      builder: (context, snapshot) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: snapshot.hasData
            ? Image.network(
                snapshot.data!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
              )
            : const SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  Icons.two_wheeler_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
      ),
    );
  }
}

class _EmptyMotorcycleCard extends StatelessWidget {
  const _EmptyMotorcycleCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.navy,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.two_wheeler_rounded, color: Colors.white, size: 30),
        const SizedBox(height: 22),
        const Text(
          'Tambahkan motor pertama',
          style: TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Simpan informasi motor untuk mulai mencatat perawatan.',
          style: TextStyle(color: Color(0xFFD5E0F0), height: 1.5),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () => context.push('/motorcycles/new'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppColors.navy,
          ),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Tambah motor'),
        ),
      ],
    ),
  );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) => Container(
    height: 150,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
    ),
    child: const Center(child: CircularProgressIndicator()),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      children: [
        const Text('Data motor belum dapat dimuat.'),
        TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
      ],
    ),
  );
}

class _NextStepCard extends StatelessWidget {
  const _NextStepCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.paleBlue,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: AppColors.blue),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
