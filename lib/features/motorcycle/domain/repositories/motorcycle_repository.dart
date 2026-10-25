import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '../../../../core/error/failure.dart';
import '../entities/motorcycle.dart';

abstract interface class MotorcycleRepository {
  Future<Either<Failure, List<Motorcycle>>> getMotorcycles();

  Future<Either<Failure, String?>> getActiveMotorcycleId();

  Future<Either<Failure, Motorcycle>> createMotorcycle({
    required String brand,
    required String model,
    required MotorcycleType type,
    required int year,
    required String plateNumber,
    required int odometerKm,
    String? color,
  });

  Future<Either<Failure, Motorcycle>> updateMotorcycle({
    required String id,
    required String brand,
    required String model,
    required MotorcycleType type,
    required int year,
    required String plateNumber,
    required int odometerKm,
    String? color,
    String? correctionReason,
  });

  Future<Either<Failure, Motorcycle>> updateOdometer({
    required String id,
    required int km,
  });

  Future<Either<Failure, Unit>> softDeleteMotorcycle(String id);

  Future<Either<Failure, Motorcycle>> updateMotorcyclePhoto({
    required Motorcycle motorcycle,
    Uint8List? imageBytes,
    required bool removePhoto,
  });

  Future<Either<Failure, Unit>> setActiveMotorcycle(String? motorcycleId);
}
