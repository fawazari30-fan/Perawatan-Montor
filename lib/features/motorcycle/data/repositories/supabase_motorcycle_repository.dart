import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/cache/offline_cache.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/motorcycle.dart';
import '../../domain/repositories/motorcycle_repository.dart';

class SupabaseMotorcycleRepository implements MotorcycleRepository {
  const SupabaseMotorcycleRepository(this._client);

  final SupabaseClient _client;
  static const _photoBucket = 'motorcycle-photos';

  @override
  Future<Either<Failure, List<Motorcycle>>> getMotorcycles() async {
    final userId = _client.auth.currentUser?.id;
    try {
      final rows = await _client
          .from('motorcycles')
          .select()
          .isFilter('deleted_at', null)
          .order('updated_at', ascending: false);
      if (userId != null) {
        await OfflineCache.saveRows(
          userId,
          'motorcycles',
          rows.map((row) => Map<String, dynamic>.from(row)).toList(),
        );
      }
      return right(rows.map(_fromRow).toList());
    } on PostgrestException {
      return left(
        const ServerFailure(
          'Daftar motor belum dapat dimuat. Periksa konfigurasi database.',
        ),
      );
    } catch (_) {
      if (userId != null) {
        final cached = await OfflineCache.readRows(userId, 'motorcycles');
        if (cached != null) return right(cached.map(_fromRow).toList());
      }
      return left(const NetworkFailure());
    }
  }

  @override
  Future<Either<Failure, String?>> getActiveMotorcycleId() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return left(const AuthFailure('Sesi telah berakhir.'));
    }
    try {
      final row = await _client
          .from('user_settings')
          .select('active_motorcycle_id')
          .eq('user_id', userId)
          .maybeSingle();
      final activeId = row?['active_motorcycle_id'] as String?;
      await OfflineCache.saveValue(
        userId,
        'active_motorcycle_id',
        activeId ?? '',
      );
      return right(activeId);
    } on PostgrestException {
      return left(const ServerFailure('Pengaturan motor aktif gagal dimuat.'));
    } catch (_) {
      final cached = await OfflineCache.readValue(
        userId,
        'active_motorcycle_id',
      );
      if (cached != null) return right(cached.isEmpty ? null : cached);
      return left(const NetworkFailure());
    }
  }

  @override
  Future<Either<Failure, Motorcycle>> createMotorcycle({
    required String brand,
    required String model,
    required MotorcycleType type,
    required int year,
    required String plateNumber,
    required int odometerKm,
    String? color,
  }) async {
    try {
      final row = await _client.rpc(
        'rpc_create_motorcycle',
        params: {
          'p_brand': brand,
          'p_model': model,
          'p_type': type.value,
          'p_year': year,
          'p_plate_number': plateNumber,
          'p_color': color,
          'p_odometer_km': odometerKm,
        },
      );
      return right(_fromRow(Map<String, dynamic>.from(row as Map)));
    } on PostgrestException catch (error) {
      return left(_writeFailure(error));
    } catch (_) {
      return left(const NetworkFailure());
    }
  }

  @override
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
  }) async {
    try {
      final row = await _client.rpc(
        'rpc_update_motorcycle',
        params: {
          'p_motorcycle_id': id,
          'p_brand': brand,
          'p_model': model,
          'p_type': type.value,
          'p_year': year,
          'p_plate_number': plateNumber,
          'p_color': color,
          'p_odometer_km': odometerKm,
          'p_correction_reason': correctionReason,
        },
      );
      return right(_fromRow(Map<String, dynamic>.from(row as Map)));
    } on PostgrestException catch (error) {
      return left(_writeFailure(error));
    } catch (_) {
      return left(const NetworkFailure());
    }
  }

  @override
  Future<Either<Failure, Motorcycle>> updateOdometer({
    required String id,
    required int km,
  }) async {
    try {
      final row = await _client.rpc(
        'rpc_update_odometer',
        params: {'p_motorcycle_id': id, 'p_km': km},
      );
      return right(_fromRow(Map<String, dynamic>.from(row as Map)));
    } on PostgrestException catch (error) {
      return left(_writeFailure(error));
    } catch (_) {
      return left(const NetworkFailure());
    }
  }

  @override
  Future<Either<Failure, Unit>> softDeleteMotorcycle(String id) async {
    try {
      final result = await _client.rpc(
        'rpc_soft_delete_motorcycle',
        params: {'p_motorcycle_id': id},
      );
      if (result != true) {
        return left(const ValidationFailure('Motor sudah tidak tersedia.'));
      }
      return right(unit);
    } on PostgrestException {
      return left(const ServerFailure('Motor belum dapat dihapus.'));
    } catch (_) {
      return left(const NetworkFailure());
    }
  }

  @override
  Future<Either<Failure, Motorcycle>> updateMotorcyclePhoto({
    required Motorcycle motorcycle,
    Uint8List? imageBytes,
    required bool removePhoto,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return left(const AuthFailure('Masuk kembali untuk melanjutkan.'));
    }
    if (imageBytes == null && !removePhoto) return right(motorcycle);
    if (imageBytes != null && imageBytes.lengthInBytes > 1048576) {
      return left(const ValidationFailure('Ukuran foto maksimal 1 MB.'));
    }

    String? uploadedPath;
    try {
      if (imageBytes != null) {
        uploadedPath = '$userId/${motorcycle.id}/${const Uuid().v4()}.jpg';
        await _client.storage
            .from(_photoBucket)
            .uploadBinary(
              uploadedPath,
              imageBytes,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: false,
              ),
            );
      }
      final nextPath = imageBytes == null ? null : uploadedPath;
      final row = await _client
          .from('motorcycles')
          .update({'photo_path': nextPath})
          .eq('id', motorcycle.id)
          .select()
          .single();
      final updated = _fromRow(row);
      if (motorcycle.photoPath != null) {
        await _removeMotorcyclePhoto(motorcycle.photoPath!);
      }
      return right(updated);
    } on PostgrestException {
      if (uploadedPath != null) await _removeMotorcyclePhoto(uploadedPath);
      return left(const ServerFailure('Foto motor belum dapat disimpan.'));
    } catch (_) {
      if (uploadedPath != null) await _removeMotorcyclePhoto(uploadedPath);
      return left(const NetworkFailure());
    }
  }

  Future<void> _removeMotorcyclePhoto(String path) async {
    try {
      await _client.storage.from(_photoBucket).remove([path]);
    } catch (_) {
      // Private orphaned files can only be accessed by their owner.
    }
  }

  @override
  Future<Either<Failure, Unit>> setActiveMotorcycle(
    String? motorcycleId,
  ) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        return left(const AuthFailure('Sesi telah berakhir.'));
      }
      await _client
          .from('user_settings')
          .update({'active_motorcycle_id': motorcycleId})
          .eq('user_id', userId);
      return right(unit);
    } on PostgrestException {
      return left(const ServerFailure('Motor aktif belum dapat diperbarui.'));
    } catch (_) {
      return left(const NetworkFailure());
    }
  }

  Failure _writeFailure(PostgrestException error) {
    if (error.code == '23505') {
      return const ValidationFailure(
        'Nomor polisi ini sudah terdaftar di akun Anda.',
      );
    }
    if (error.message.contains('ODOMETER_DECREASE')) {
      return const ValidationFailure(
        'Odometer tidak boleh lebih rendah tanpa alasan koreksi.',
      );
    }
    if (error.message.contains('MOTORCYCLE_NOT_FOUND')) {
      return const ValidationFailure('Motor sudah tidak tersedia.');
    }
    return const ServerFailure(
      'Motor belum dapat disimpan. Periksa data lalu coba lagi.',
    );
  }

  Motorcycle _fromRow(Map<String, dynamic> row) => Motorcycle(
    id: row['id'] as String,
    brand: row['brand'] as String,
    model: row['model'] as String,
    type: MotorcycleType.fromValue(row['type'] as String),
    year: (row['year'] as num).toInt(),
    plateNumber: row['plate_number'] as String,
    odometerKm: (row['odometer_km'] as num).toInt(),
    color: row['color'] as String?,
    photoPath: row['photo_path'] as String?,
  );
}
