import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/providers/supabase_client_provider.dart';
import '../../data/local_schedule_notifications.dart';
import '../../../motorcycle/presentation/controllers/motorcycle_controller.dart';
import '../../data/repositories/supabase_schedule_repository.dart';
import '../../domain/entities/maintenance_schedule.dart';
import '../../domain/repositories/schedule_repository.dart';

final scheduleRepositoryProvider = Provider<ScheduleRepository>(
  (ref) => SupabaseScheduleRepository(ref.watch(supabaseClientProvider)),
);

final scheduleListControllerProvider =
    AsyncNotifierProvider<ScheduleListController, List<MaintenanceSchedule>>(
      ScheduleListController.new,
    );

class ScheduleListController extends AsyncNotifier<List<MaintenanceSchedule>> {
  late ScheduleRepository _repository;

  @override
  Future<List<MaintenanceSchedule>> build() async {
    _repository = ref.watch(scheduleRepositoryProvider);
    // Recompute schedule status whenever the selected motorcycle or its
    // odometer changes.
    ref.watch(motorcycleListControllerProvider);
    final motorcycleId = ref.watch(activeMotorcycleIdProvider);
    if (motorcycleId == null) {
      await LocalScheduleNotifications.instance.cancelAll();
      return const [];
    }
    final result = await _repository.getSchedules(motorcycleId);
    return await result.match((failure) => throw failure, (items) async {
      await _syncLocalNotifications(items);
      return items;
    });
  }

  Future<Either<Failure, MaintenanceSchedule>> createSchedule({
    required String typeCode,
    required String title,
    required int? intervalKm,
    required int? intervalDays,
    required int lastDoneKm,
    required DateTime lastDoneDate,
  }) async {
    final motorcycleId = ref.read(activeMotorcycleIdProvider);
    if (motorcycleId == null) {
      return left(const ValidationFailure('Pilih motor terlebih dahulu.'));
    }

    final result = await _repository.createSchedule(
      motorcycleId: motorcycleId,
      typeCode: typeCode,
      title: title,
      intervalKm: intervalKm,
      intervalDays: intervalDays,
      lastDoneKm: lastDoneKm,
      lastDoneDate: lastDoneDate,
    );
    await result.match((_) async {}, (_) async {
      await LocalScheduleNotifications.instance.requestPermission();
      await _reloadSchedules();
    });
    return result;
  }

  Future<Either<Failure, Unit>> updateSchedule({
    required String id,
    required String typeCode,
    required String title,
    required int? intervalKm,
    required int? intervalDays,
    required int lastDoneKm,
    required DateTime lastDoneDate,
  }) async {
    final result = await _repository.updateSchedule(
      id: id,
      typeCode: typeCode,
      title: title,
      intervalKm: intervalKm,
      intervalDays: intervalDays,
      lastDoneKm: lastDoneKm,
      lastDoneDate: lastDoneDate,
    );
    await result.match((_) async {}, (_) => _reloadSchedules());
    return result;
  }

  Future<Either<Failure, Unit>> snoozeSchedule(String id, int days) async {
    final result = await _repository.snoozeSchedule(id, days);
    await result.match((_) async {}, (_) => _reloadSchedules());
    return result;
  }

  Future<Either<Failure, Unit>> deactivateSchedule(String id) async {
    final result = await _repository.deactivateSchedule(id);
    await result.match((_) async {}, (_) => _reloadSchedules());
    return result;
  }

  Future<void> _reloadSchedules() async {
    final motorcycleId = ref.read(activeMotorcycleIdProvider);
    if (motorcycleId == null) return;
    final refreshed = await _repository.getSchedules(motorcycleId);
    await refreshed.match(
      (failure) async {
        state = AsyncError(failure, StackTrace.current);
      },
      (schedules) async {
        state = AsyncData(schedules);
        await _syncLocalNotifications(schedules);
      },
    );
  }

  Future<void> syncNotifications() async {
    final motorcycleId = ref.read(activeMotorcycleIdProvider);
    if (motorcycleId == null) {
      await LocalScheduleNotifications.instance.cancelAll();
      return;
    }
    final result = await ref
        .read(scheduleRepositoryProvider)
        .getSchedules(motorcycleId);
    await result.match(
      (_) async {},
      (schedules) => _syncLocalNotifications(schedules),
    );
  }

  Future<void> _syncLocalNotifications(
    List<MaintenanceSchedule> schedules,
  ) async {
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (userId == null) {
      await LocalScheduleNotifications.instance.cancelAll();
      return;
    }
    try {
      final settings = await ref
          .read(supabaseClientProvider)
          .from('user_settings')
          .select(
            'push_enabled, remind_days_before, remind_hour, remind_km_before',
          )
          .eq('user_id', userId)
          .maybeSingle();
      await LocalScheduleNotifications.instance.replaceAll(
        schedules,
        enabled: settings?['push_enabled'] as bool? ?? true,
        remindDaysBefore: settings?['remind_days_before'] as int? ?? 3,
        remindHour: settings?['remind_hour'] as int? ?? 7,
        remindKmBefore: settings?['remind_km_before'] as int? ?? 200,
      );
    } catch (_) {
      final preferences = await SharedPreferences.getInstance();
      final prefix = 'rawat_motor_cache:v1:$userId:notification_';
      await LocalScheduleNotifications.instance.replaceAll(
        schedules,
        enabled: preferences.getBool('${prefix}enabled') ?? true,
        remindDaysBefore: preferences.getInt('${prefix}days') ?? 3,
        remindHour: preferences.getInt('${prefix}hour') ?? 7,
        remindKmBefore: preferences.getInt('${prefix}km') ?? 200,
      );
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}
