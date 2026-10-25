import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '../../../../core/error/failure.dart';
import '../entities/service_record.dart';

abstract interface class ServiceRecordRepository {
  Future<Either<Failure, List<ServiceRecord>>> getRecords(String motorcycleId);

  Future<Either<Failure, ServiceRecord>> createRecord({
    required String motorcycleId,
    String? scheduleId,
    required String typeCode,
    required String title,
    required DateTime serviceDate,
    required int odometerKm,
    required int cost,
    String? workshop,
    String? notes,
    List<Uint8List> receiptImages = const [],
  });

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
  });

  Future<Either<Failure, Unit>> deleteRecord(String id);

  Future<String> createReceiptSignedUrl(String path);
}
