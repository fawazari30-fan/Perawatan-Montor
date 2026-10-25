enum ScheduleStatus {
  upcoming('upcoming', 'Mendatang'),
  dueSoon('due_soon', 'Perlu dicek'),
  urgent('urgent', 'Segera'),
  snoozed('snoozed', 'Ditunda'),
  overdue('overdue', 'Terlambat');

  const ScheduleStatus(this.value, this.label);

  final String value;
  final String label;

  static ScheduleStatus fromValue(String value) =>
      ScheduleStatus.values.firstWhere(
        (status) => status.value == value,
        orElse: () => ScheduleStatus.upcoming,
      );
}

class MaintenanceType {
  const MaintenanceType({
    required this.code,
    required this.name,
    this.defaultIntervalKm,
    this.defaultIntervalDays,
  });

  final String code;
  final String name;
  final int? defaultIntervalKm;
  final int? defaultIntervalDays;

  static const defaults = [
    MaintenanceType(
      code: 'oil',
      name: 'Ganti Oli Mesin',
      defaultIntervalKm: 2000,
      defaultIntervalDays: 60,
    ),
    MaintenanceType(
      code: 'brake',
      name: 'Pemeriksaan Rem',
      defaultIntervalKm: 8000,
      defaultIntervalDays: 180,
    ),
    MaintenanceType(
      code: 'battery',
      name: 'Pemeriksaan Aki',
      defaultIntervalDays: 365,
    ),
    MaintenanceType(
      code: 'tire',
      name: 'Pemeriksaan Ban',
      defaultIntervalKm: 10000,
      defaultIntervalDays: 365,
    ),
    MaintenanceType(
      code: 'air_filter',
      name: 'Ganti Filter Udara',
      defaultIntervalKm: 8000,
      defaultIntervalDays: 365,
    ),
    MaintenanceType(
      code: 'service',
      name: 'Servis Berkala',
      defaultIntervalKm: 3000,
      defaultIntervalDays: 90,
    ),
    MaintenanceType(code: 'other', name: 'Lainnya'),
  ];
}

class MaintenanceSchedule {
  const MaintenanceSchedule({
    required this.id,
    required this.motorcycleId,
    required this.title,
    required this.typeCode,
    required this.weight,
    required this.remainingPct,
    required this.status,
    this.nextDueDate,
    this.nextDueKm,
    this.odometerKm = 0,
    this.intervalKm,
    this.intervalDays,
    this.lastDoneKm = 0,
    this.lastDoneDate,
    this.snoozedUntil,
  });

  final String id;
  final String motorcycleId;
  final String title;
  final String typeCode;
  final double weight;
  final double remainingPct;
  final ScheduleStatus status;
  final DateTime? nextDueDate;
  final int? nextDueKm;
  final int odometerKm;
  final int? intervalKm;
  final int? intervalDays;
  final int lastDoneKm;
  final DateTime? lastDoneDate;
  final DateTime? snoozedUntil;

  int? get kmLeft => nextDueKm == null ? null : nextDueKm! - odometerKm;
}
