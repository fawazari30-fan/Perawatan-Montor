enum MotorcycleType {
  matic('matic', 'Matic'),
  bebek('bebek', 'Bebek'),
  sport('sport', 'Sport'),
  lainnya('lainnya', 'Lainnya');

  const MotorcycleType(this.value, this.label);

  final String value;
  final String label;

  static MotorcycleType fromValue(String value) => MotorcycleType.values
      .firstWhere((type) => type.value == value, orElse: () => lainnya);
}

class Motorcycle {
  const Motorcycle({
    required this.id,
    required this.brand,
    required this.model,
    required this.type,
    required this.year,
    required this.plateNumber,
    required this.odometerKm,
    this.color,
    this.photoPath,
  });

  final String id;
  final String brand;
  final String model;
  final MotorcycleType type;
  final int year;
  final String plateNumber;
  final int odometerKm;
  final String? color;
  final String? photoPath;

  String get displayName => '$brand $model';
}
