import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failure.dart';
import '../../data/repositories/supabase_auth_repository.dart';
import '../../domain/repositories/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(Supabase.instance.client),
);

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) => AuthController(ref.watch(authRepositoryProvider)),
);

class AuthState {
  const AuthState({
    this.isLoading = false,
    this.message,
    this.hasError = false,
  });

  final bool isLoading;
  final String? message;
  final bool hasError;
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository) : super(const AuthState());

  final AuthRepository _repository;

  Future<bool> signIn({required String email, required String password}) =>
      _perform(_repository.signIn(email: email, password: password));

  Future<bool> register({
    required String name,
    required String phone,
    required String email,
    required String password,
  }) async {
    final result = await _perform(
      _repository.register(
        name: name,
        phone: phone,
        email: email,
        password: password,
      ),
    );
    if (result) {
      state = const AuthState(
        message: 'Pendaftaran berhasil. Periksa email untuk verifikasi akun.',
      );
    }
    return result;
  }

  Future<bool> sendPasswordReset(String email) async {
    final result = await _perform(_repository.sendPasswordReset(email));
    if (result) {
      state = const AuthState(
        message: 'Jika email terdaftar, tautan reset akan dikirim ke kotak masuk Anda.',
      );
    }
    return result;
  }

  Future<void> signOut() async {
    state = const AuthState(isLoading: true);
    final result = await _repository.signOut();
    state = result.match(
      (failure) => AuthState(message: failure.message, hasError: true),
      (_) => const AuthState(),
    );
  }

  Future<bool> _perform(Future<Either<Failure, Unit>> request) async {
    state = const AuthState(isLoading: true);
    final result = await request;
    return result.match(
      (failure) {
        state = AuthState(message: failure.message, hasError: true);
        return false;
      },
      (_) {
        state = const AuthState();
        return true;
      },
    );
  }
}
