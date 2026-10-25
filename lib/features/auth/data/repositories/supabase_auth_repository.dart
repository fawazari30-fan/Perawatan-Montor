import 'package:fpdart/fpdart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failure.dart';
import '../../domain/repositories/auth_repository.dart';

class SupabaseAuthRepository implements AuthRepository {
  const SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Either<Failure, Unit>> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
      return right(unit);
    } on AuthException {
      return left(const AuthFailure('Email atau kata sandi salah.'));
    } catch (_) {
      return left(const NetworkFailure());
    }
  }

  @override
  Future<Either<Failure, Unit>> register({
    required String name,
    required String phone,
    required String email,
    required String password,
  }) async {
    try {
      await _client.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': name, 'phone': phone},
      );
      return right(unit);
    } on AuthException catch (error) {
      if (error.code == 'user_already_exists') {
        return left(
          const ValidationFailure(
            'Email sudah terdaftar. Coba masuk atau gunakan email lain.',
          ),
        );
      }
      return left(
        const AuthFailure(
          'Pendaftaran belum berhasil. Periksa data Anda lalu coba lagi.',
        ),
      );
    } catch (_) {
      return left(const NetworkFailure());
    }
  }

  @override
  Future<Either<Failure, Unit>> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
      return right(unit);
    } on AuthException {
      return left(
        const AuthFailure(
          'Permintaan reset belum berhasil. Coba lagi beberapa saat.',
        ),
      );
    } catch (_) {
      return left(const NetworkFailure());
    }
  }

  @override
  Future<Either<Failure, Unit>> signOut() async {
    try {
      await _client.auth.signOut();
      return right(unit);
    } catch (_) {
      return left(const ServerFailure());
    }
  }
}
