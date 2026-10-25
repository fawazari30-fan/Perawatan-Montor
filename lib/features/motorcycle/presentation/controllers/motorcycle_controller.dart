import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/providers/supabase_client_provider.dart';
import '../../data/repositories/supabase_motorcycle_repository.dart';
import '../../domain/entities/motorcycle.dart';
import '../../domain/repositories/motorcycle_repository.dart';

final motorcycleRepositoryProvider = Provider<MotorcycleRepository>(
  (ref) => SupabaseMotorcycleRepository(ref.watch(supabaseClientProvider)),
);

final activeMotorcycleIdProvider = StateProvider<String?>((ref) => null);

final motorcycleListControllerProvider =
    AsyncNotifierProvider<MotorcycleListController, List<Motorcycle>>(
      MotorcycleListController.new,
    );

class MotorcycleListController extends AsyncNotifier<List<Motorcycle>> {
  late MotorcycleRepository _repository;

  @override
  Future<List<Motorcycle>> build() async {
    _repository = ref.watch(motorcycleRepositoryProvider);
    final rows = await _repository.getMotorcycles();
    final motorcycles = rows.match(
      (failure) => throw failure,
      (items) => items,
    );

    final activeResult = await _repository.getActiveMotorcycleId();
    final storedId = activeResult.getOrElse((_) => null);
    final activeId = motorcycles.any((motor) => motor.id == storedId)
        ? storedId
        : motorcycles.isEmpty
        ? null
        : motorcycles.first.id;
    ref.read(activeMotorcycleIdProvider.notifier).state = activeId;
    return motorcycles;
  }

  Future<Either<Failure, Motorcycle>> addMotorcycle({
    required String brand,
    required String model,
    required MotorcycleType type,
    required int year,
    required String plateNumber,
    required int odometerKm,
    String? color,
  }) async {
    final result = await _repository.createMotorcycle(
      brand: brand,
      model: model,
      type: type,
      year: year,
      plateNumber: plateNumber,
      odometerKm: odometerKm,
      color: color,
    );
    result.match((_) {}, (motorcycle) {
      state = AsyncData([...?state.valueOrNull, motorcycle]);
      ref.read(activeMotorcycleIdProvider.notifier).state = motorcycle.id;
    });
    return result;
  }

  Future<Either<Failure, Motorcycle>> editMotorcycle({
    required Motorcycle original,
    required String brand,
    required String model,
    required MotorcycleType type,
    required int year,
    required String plateNumber,
    required int odometerKm,
    String? color,
    String? correctionReason,
  }) async {
    final result = await _repository.updateMotorcycle(
      id: original.id,
      brand: brand,
      model: model,
      type: type,
      year: year,
      plateNumber: plateNumber,
      odometerKm: odometerKm,
      color: color,
      correctionReason: correctionReason,
    );
    result.match((_) {}, (updated) {
      final items = state.valueOrNull ?? const <Motorcycle>[];
      state = AsyncData([
        for (final item in items)
          if (item.id == updated.id) updated else item,
      ]);
    });
    return result;
  }

  Future<Either<Failure, Motorcycle>> updateOdometer({
    required String id,
    required int km,
  }) async {
    final result = await _repository.updateOdometer(id: id, km: km);
    result.match((_) {}, (updated) {
      final items = state.valueOrNull ?? const <Motorcycle>[];
      state = AsyncData([
        for (final item in items)
          if (item.id == updated.id) updated else item,
      ]);
    });
    return result;
  }

  Future<Either<Failure, Motorcycle>> updateMotorcyclePhoto({
    required Motorcycle motorcycle,
    Uint8List? imageBytes,
    required bool removePhoto,
  }) async {
    final result = await _repository.updateMotorcyclePhoto(
      motorcycle: motorcycle,
      imageBytes: imageBytes,
      removePhoto: removePhoto,
    );
    result.match((_) {}, (updated) {
      final items = state.valueOrNull ?? const <Motorcycle>[];
      state = AsyncData([
        for (final item in items)
          if (item.id == updated.id) updated else item,
      ]);
    });
    return result;
  }

  Future<Either<Failure, Unit>> deleteMotorcycle(String id) async {
    final result = await _repository.softDeleteMotorcycle(id);
    await result.match((_) async {}, (_) async {
      final items = state.valueOrNull ?? const <Motorcycle>[];
      final remaining = items.where((item) => item.id != id).toList();
      state = AsyncData(remaining);
      final currentId = ref.read(activeMotorcycleIdProvider);
      if (currentId == id) {
        final newId = remaining.isEmpty ? null : remaining.first.id;
        ref.read(activeMotorcycleIdProvider.notifier).state = newId;
        await _repository.setActiveMotorcycle(newId);
      }
    });
    return result;
  }

  Future<Either<Failure, Unit>> setActiveMotorcycle(String? id) async {
    final result = await _repository.setActiveMotorcycle(id);
    result.match(
      (_) {},
      (_) => ref.read(activeMotorcycleIdProvider.notifier).state = id,
    );
    return result;
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}
