import 'package:fpdart/fpdart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/cache/offline_cache.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/maintenance_schedule.dart';
import '../../domain/repositories/schedule_repository.dart';

class SupabaseScheduleRepository implements ScheduleRepository {
  const SupabaseScheduleRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Either<Failure, List<MaintenanceSchedule>>> getSchedules(
    String motorcycleId,
  ) async {
    final userId = _client.auth.currentUser?.id;
    final cacheKey = 'schedules:$motorcycleId';
    try {
      final rows = await _client
          .from('v_schedule_status')
          .select()
          .eq('motorcycle_id', motorcycleId)
          .order('remaining_pct', ascending: true);
      if (userId != null) {
        await OfflineCache.saveRows(
          userId,
          cacheKey,
          rows.map((row) => Map<String, dynamic>.from(row)).toList(),
        );
      }
      return right(rows.map(_fromRow).toList());
    } on PostgrestException {
      return left(const ServerFailure('Jadwal perawatan belum dapat dimuat.'));
    } catch (_) {
      if (userId != null) {
        final cached = await OfflineCache.readRows(userId, cacheKey);
        if (cached != null) return right(cached.map(_fromRow).toList());
      }
      return left(const NetworkFailure());
    }
  }

  @override
  Future<Either<Failure, MaintenanceSchedule>> createSchedule({
    required String motorcycleId,
    required String typeCode,
    required String title,
    required int? intervalKm,
    required int? intervalDays,
    required int lastDoneKm,
    required DateTime lastDoneDate,
  }) async {
    try {
      final row = await _client.rpc(
        'rpc_create_schedule',
        params: {
          'p_motorcycle_id': motorcycleId,
          'p_type_code': typeCode,
          'p_title': title,
          'p_interval_km': intervalKm,
          'p_interval_days': intervalDays,
          'p_last_done_km': lastDoneKm,
          'p_last_done_date': _dateString(lastDoneDate),
        },
      );
      return right(
        _fromScheduleRow(Map<String, dynamic>.from(row as Map), typeCode),
      );
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        return left(const ValidationFailure('Jadwal ini sudah tersedia.'));
      }
      return left(const ServerFailure('Jadwal belum dapat disimpan.'));
    } catch (_) {
      return left(const NetworkFailure());
    }
  }

  MaintenanceSchedule _fromRow(Map<String, dynamic> row) {
    final date =
        row['effective_due_date'] as String? ?? row['next_due_date'] as String?;
    return MaintenanceSchedule(
      id: row['id'] as String,
      motorcycleId: row['motorcycle_id'] as String,
      title: row['title'] as String,
      typeCode: row['type_code'] as String,
      weight: (row['weight'] as num).toDouble(),
      remainingPct: (row['remaining_pct'] as num).toDouble(),
      status: ScheduleStatus.fromValue(row['status'] as String),
      nextDueDate: date == null ? null : DateTime.parse(date),
      nextDueKm: (row['next_due_km'] as num?)?.toInt(),
      odometerKm: (row['odometer_km'] as num).toInt(),
      intervalKm: (row['interval_km'] as num?)?.toInt(),
      intervalDays: (row['interval_days'] as num?)?.toInt(),
      lastDoneKm: (row['last_done_km'] as num).toInt(),
      lastDoneDate: DateTime.parse(row['last_done_date'] as String),
      snoozedUntil: row['snoozed_until'] == null
          ? null
          : DateTime.parse(row['snoozed_until'] as String),
    );
  }

  MaintenanceSchedule _fromScheduleRow(
    Map<String, dynamic> row,
    String typeCode,
  ) => MaintenanceSchedule(
    id: row['id'] as String,
    motorcycleId: row['motorcycle_id'] as String,
    title: row['title'] as String,
    typeCode: typeCode,
    weight: switch (typeCode) {
      'oil' || 'brake' => 0.25,
      'battery' || 'tire' => 0.15,
      'air_filter' => 0.10,
      'service' || 'other' => 0.10,
      _ => 0,
    },
    remainingPct: 1,
    status: ScheduleStatus.upcoming,
    nextDueDate: row['interval_days'] == null
        ? null
        : DateTime.parse(row['last_done_date'] as String)
              .add(Duration(days: row['interval_days'] as int)),
    nextDueKm: row['interval_km'] == null
        ? null
        : (row['last_done_km'] as int) + (row['interval_km'] as int),
    intervalKm: (row['interval_km'] as num?)?.toInt(),
    intervalDays: (row['interval_days'] as num?)?.toInt(),
    lastDoneKm: (row['last_done_km'] as num).toInt(),
    lastDoneDate: DateTime.parse(row['last_done_date'] as String),
    snoozedUntil: row['snoozed_until'] == null
        ? null
        : DateTime.parse(row['snoozed_until'] as String),
  );

  @override
  Future<Either<Failure, Unit>> updateSchedule({
    required String id,
    required String typeCode,
    required String title,
    required int? intervalKm,
    required int? intervalDays,
    required int lastDoneKm,
    required DateTime lastDoneDate,
  }) async {
    try {
      await _client.rpc(
        'rpc_update_schedule',
        params: {
          'p_schedule_id': id,
          'p_type_code': typeCode,
          'p_title': title,
          'p_interval_km': intervalKm,
          'p_interval_days': intervalDays,
          'p_last_done_km': lastDoneKm,
          'p_last_done_date': _dateString(lastDoneDate),
        },
      );
      return right(unit);
    } on PostgrestException catch (error) {
      if (error.message.contains('MOTORCYCLE_NOT_FOUND')) {
        return left(
          const ValidationFailure('Motor untuk jadwal ini tidak ditemukan.'),
        );
      }
      return left(const ServerFailure('Jadwal belum dapat diperbarui.'));
    } catch (_) {
      return left(const NetworkFailure());
    }
  }

  @override
  Future<Either<Failure, Unit>> snoozeSchedule(String id, int days) async {
    try {
      await _client.rpc(
        'rpc_snooze_schedule',
        params: {'p_schedule_id': id, 'p_days': days},
      );
      return right(unit);
    } on PostgrestException {
      return left(const ServerFailure('Pengingat belum dapat ditunda.'));
    } catch (_) {
      return left(const NetworkFailure());
    }
  }

  @override
  Future<Either<Failure, Unit>> deactivateSchedule(String id) async {
    try {
      await _client.rpc(
        'rpc_deactivate_schedule',
        params: {'p_schedule_id': id},
      );
      return right(unit);
    } on PostgrestException {
      return left(const ServerFailure('Jadwal belum dapat dinonaktifkan.'));
    } catch (_) {
      return left(const NetworkFailure());
    }
  }

  String _dateString(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
