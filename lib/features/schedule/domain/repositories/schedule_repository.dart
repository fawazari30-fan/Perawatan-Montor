import 'package:fpdart/fpdart.dart';

import '../../../../core/error/failure.dart';
import '../entities/maintenance_schedule.dart';

abstract interface class ScheduleRepository {
  Future<Either<Failure, List<MaintenanceSchedule>>> getSchedules(
    String motorcycleId,
  );

  Future<Either<Failure, MaintenanceSchedule>> createSchedule({
    required String motorcycleId,
    required String typeCode,
    required String title,
    required int? intervalKm,
    required int? intervalDays,
    required int lastDoneKm,
    required DateTime lastDoneDate,
  });

  Future<Either<Failure, Unit>> updateSchedule({
    required String id,
    required String typeCode,
    required String title,
    required int? intervalKm,
    required int? intervalDays,
    required int lastDoneKm,
    required DateTime lastDoneDate,
  });

  Future<Either<Failure, Unit>> snoozeSchedule(String id, int days);

  Future<Either<Failure, Unit>> deactivateSchedule(String id);
}
