import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/cache/offline_cache.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/service_record.dart';
import '../../domain/repositories/service_record_repository.dart';

class SupabaseServiceRecordRepository implements ServiceRecordRepository {
  const SupabaseServiceRecordRepository(this._client);

  static const _receiptBucket = 'service-receipts';
  final SupabaseClient _client;

  @override
  Future<Either<Failure, List<ServiceRecord>>> getRecords(
    String motorcycleId,
  ) async {
    final userId = _client.auth.currentUser?.id;
    final cacheKey = 'records:$motorcycleId';
    try {
      final rows = await _client
          .from('service_records')
          .select('*, maintenance_types(code)')
          .eq('motorcycle_id', motorcycleId)
          .order('service_date', ascending: false)
          .order('created_at', ascending: false);
      if (userId != null) {
        await OfflineCache.saveRows(
          userId,
          cacheKey,
          rows.map((row) => Map<String, dynamic>.from(row)).toList(),
        );
      }
      return right(rows.map(_fromRow).toList());
    } on PostgrestException {
      return left(const ServerFailure('Riwayat servis belum dapat dimuat.'));
    } catch (_) {
      if (userId != null) {
        final cached = await OfflineCache.readRows(userId, cacheKey);
        if (cached != null) return right(cached.map(_fromRow).toList());
      }
      return left(const NetworkFailure());
    }
  }

  @override
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
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return left(const AuthFailure('Masuk kembali untuk melanjutkan.'));
    }

    final paths = <String>[];
    try {
      if (receiptImages.length > 5) {
        return left(const ValidationFailure('Maksimal 5 foto nota.'));
      }
      if (receiptImages.any((image) => image.lengthInBytes > 1048576)) {
        return left(
          const ValidationFailure(
            'Ukuran foto masih lebih dari 1 MB. Pilih foto lain.',
          ),
        );
      }
      for (final image in receiptImages) {
        final path = '$userId/$motorcycleId/${const Uuid().v4()}.jpg';
        await _client.storage
            .from(_receiptBucket)
            .uploadBinary(
              path,
              image,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: false,
              ),
            );
        paths.add(path);
      }

      final row = await _client.rpc(
        'rpc_create_service_record',
        params: {
          'p_motorcycle_id': motorcycleId,
          'p_schedule_id': scheduleId,
          'p_type_code': typeCode,
          'p_title': title,
          'p_service_date': _dateString(serviceDate),
          'p_odometer_km': odometerKm,
          'p_workshop': workshop,
          'p_cost': cost,
          'p_notes': notes,
          'p_receipt_paths': paths,
        },
      );
      return right(_fromRow(Map<String, dynamic>.from(row as Map)));
    } on PostgrestException catch (error) {
      await _removeUploaded(paths);
      return left(
        ValidationFailure(switch (error.message) {
          _ when error.message.contains('SERVICE_DATE_IN_FUTURE') =>
            'Tanggal servis tidak boleh di masa depan.',
          _ when error.message.contains('SERVICE_ODOMETER_BELOW_INITIAL') =>
            'Odometer servis tidak boleh lebih kecil dari odometer awal motor.',
          _ => 'Catatan servis belum dapat disimpan. Periksa kembali datanya.',
        }),
      );
    } catch (_) {
      await _removeUploaded(paths);
      return left(const NetworkFailure());
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteRecord(String id) async {
    try {
      final paths = await _client.rpc(
        'rpc_delete_service_record',
        params: {'p_record_id': id},
      ) as List<dynamic>;
      if (paths.isNotEmpty) await _removeUploaded(paths.cast<String>());
      return right(unit);
    } on PostgrestException {
      return left(const ServerFailure('Catatan servis belum dapat dihapus.'));
    } catch (_) {
      return left(const NetworkFailure());
    }
  }

  @override
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
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return left(const AuthFailure('Masuk kembali untuk melanjutkan.'));
    }
    final uploaded = <String>[];
    try {
      if (existingReceiptPaths.length + receiptImages.length > 5) {
        return left(const ValidationFailure('Maksimal 5 foto nota.'));
      }
      for (final path in existingReceiptPaths) {
        if (!path.startsWith('$userId/')) {
          return left(const AuthFailure('Lampiran tidak valid.'));
        }
      }
      for (final image in receiptImages) {
        if (image.lengthInBytes > 1048576) {
          return left(const ValidationFailure('Ukuran foto maksimal 1 MB.'));
        }
        final path = '$userId/${record.motorcycleId}/${const Uuid().v4()}.jpg';
        await _client.storage
            .from(_receiptBucket)
            .uploadBinary(
              path,
              image,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: false,
              ),
            );
        uploaded.add(path);
      }
      await _client.rpc(
        'rpc_update_service_record',
        params: {
          'p_record_id': record.id,
          'p_type_code': typeCode,
          'p_title': title,
          'p_service_date': _dateString(serviceDate),
          'p_odometer_km': odometerKm,
          'p_workshop': workshop,
          'p_cost': cost,
          'p_notes': notes,
          'p_receipt_paths': [...existingReceiptPaths, ...uploaded],
        },
      );
      return right(unit);
    } on PostgrestException catch (error) {
      await _removeUploaded(uploaded);
      return left(
        ValidationFailure(switch (error.message) {
          _ when error.message.contains('SERVICE_DATE_IN_FUTURE') =>
            'Tanggal servis tidak boleh di masa depan.',
          _ when error.message.contains('SERVICE_ODOMETER_BELOW_INITIAL') =>
            'Odometer servis tidak boleh lebih kecil dari odometer awal motor.',
          _ =>
            'Catatan servis belum dapat diperbarui. Periksa kembali datanya.',
        }),
      );
    } catch (_) {
      await _removeUploaded(uploaded);
      return left(const NetworkFailure());
    }
  }

  @override
  Future<String> createReceiptSignedUrl(String path) =>
      _client.storage.from(_receiptBucket).createSignedUrl(path, 3600);

  Future<void> _removeUploaded(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await _client.storage.from(_receiptBucket).remove(paths);
    } catch (_) {
      // An orphaned private object is inaccessible to other users and can be
      // cleaned up by the scheduled storage cleanup job.
    }
  }

  ServiceRecord _fromRow(Map<String, dynamic> row) {
    final type = row['maintenance_types'];
    final typeCode = type is Map ? type['code'] as String? : null;
    return ServiceRecord(
      id: row['id'] as String,
      motorcycleId: row['motorcycle_id'] as String,
      title: row['title'] as String,
      typeCode: typeCode ?? row['type_id'].toString(),
      serviceDate: DateTime.parse(row['service_date'] as String),
      odometerKm: (row['odometer_km'] as num).toInt(),
      cost: (row['cost'] as num).toInt(),
      receiptPaths: (row['receipt_paths'] as List<dynamic>? ?? const [])
          .cast<String>(),
      workshop: row['workshop'] as String?,
      notes: row['notes'] as String?,
    );
  }

  String _dateString(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
