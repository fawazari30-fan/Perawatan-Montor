import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/providers/supabase_client_provider.dart';
import '../../../motorcycle/presentation/controllers/motorcycle_controller.dart';
import '../../../schedule/presentation/controllers/schedule_controller.dart';
import '../../data/repositories/supabase_service_record_repository.dart';
import '../../domain/entities/service_record.dart';
import '../../domain/repositories/service_record_repository.dart';

final serviceRecordRepositoryProvider = Provider<ServiceRecordRepository>(
  (ref) => SupabaseServiceRecordRepository(ref.watch(supabaseClientProvider)),
);

final serviceRecordListControllerProvider =
    AsyncNotifierProvider<ServiceRecordListController, List<ServiceRecord>>(
      ServiceRecordListController.new,
    );

class ServiceRecordListController extends AsyncNotifier<List<ServiceRecord>> {
  late ServiceRecordRepository _repository;

  @override
  Future<List<ServiceRecord>> build() async {
    _repository = ref.watch(serviceRecordRepositoryProvider);
    ref.watch(motorcycleListControllerProvider);
    final motorcycleId = ref.watch(activeMotorcycleIdProvider);
    if (motorcycleId == null) return const [];
    final result = await _repository.getRecords(motorcycleId);
    return result.match((failure) => throw failure, (records) => records);
  }

  Future<Either<Failure, ServiceRecord>> createRecord({
    String? scheduleId,
    required String typeCode,
    required String title,
    required DateTime serviceDate,
    required int odometerKm,
    required int cost,
    String? workshop,
    String? notes,
    List<Uint8List> receiptImages = const [],
  }) async {
    final motorcycleId = ref.read(activeMotorcycleIdProvider);
    if (motorcycleId == null) {
      return left(const ValidationFailure('Pilih motor terlebih dahulu.'));
    }
    final result = await _repository.createRecord(
      motorcycleId: motorcycleId,
      scheduleId: scheduleId,
      typeCode: typeCode,
      title: title,
      serviceDate: serviceDate,
      odometerKm: odometerKm,
      cost: cost,
      workshop: workshop,
      notes: notes,
      receiptImages: receiptImages,
    );
    await result.match((_) async {}, (_) async {
      final refreshed = await _repository.getRecords(motorcycleId);
      refreshed.match(
        (failure) => state = AsyncError(failure, StackTrace.current),
        (records) => state = AsyncData(records),
      );
      ref.invalidate(scheduleListControllerProvider);
      ref.invalidate(motorcycleListControllerProvider);
    });
    return result;
  }

  Future<Either<Failure, Unit>> deleteRecord(String id) async {
    final result = await _repository.deleteRecord(id);
    await result.match((_) async {}, (_) async {
      final motorcycleId = ref.read(activeMotorcycleIdProvider);
      if (motorcycleId == null) return;
      final refreshed = await _repository.getRecords(motorcycleId);
      refreshed.match(
        (failure) => state = AsyncError(failure, StackTrace.current),
        (records) => state = AsyncData(records),
      );
      ref.invalidate(scheduleListControllerProvider);
    });
    return result;
  }

  Future<Either<Failure, Unit>> updateRecord({
    required ServiceRecord record,
    required String typeCode,
    required String title,
    required DateTime serviceDate,
    required int odometerKm,
    required int cost,
    required List<String> existingReceiptPaths,
    String? workshop,
    String? notes,
    List<Uint8List> receiptImages = const [],
  }) async {
    final result = await _repository.updateRecord(
      record: record,
      typeCode: typeCode,
      title: title,
      serviceDate: serviceDate,
      odometerKm: odometerKm,
      cost: cost,
      existingReceiptPaths: existingReceiptPaths,
      workshop: workshop,
      notes: notes,
      receiptImages: receiptImages,
    );
    await result.match((_) async {}, (_) async {
      final motorcycleId = ref.read(activeMotorcycleIdProvider);
      if (motorcycleId == null) return;
      final refreshed = await _repository.getRecords(motorcycleId);
      refreshed.match(
        (failure) => state = AsyncError(failure, StackTrace.current),
        (records) => state = AsyncData(records),
      );
      ref.invalidate(scheduleListControllerProvider);
      ref.invalidate(motorcycleListControllerProvider);
    });
    return result;
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}
