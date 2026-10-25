class ServiceRecord {
  const ServiceRecord({
    required this.id,
    required this.motorcycleId,
    required this.title,
    required this.typeCode,
    required this.serviceDate,
    required this.odometerKm,
    required this.cost,
    this.receiptPaths = const [],
    this.workshop,
    this.notes,
  });

  final String id;
  final String motorcycleId;
  final String title;
  final String typeCode;
  final DateTime serviceDate;
  final int odometerKm;
  final int cost;
  final List<String> receiptPaths;
  final String? workshop;
  final String? notes;
}
