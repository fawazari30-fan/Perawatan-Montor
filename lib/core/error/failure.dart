sealed class Failure {
  const Failure(this.message);

  final String message;
}

final class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

final class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

final class NetworkFailure extends Failure {
  const NetworkFailure([
    super.message = 'Periksa koneksi internet lalu coba lagi.',
  ]);
}

final class ServerFailure extends Failure {
  const ServerFailure([
    super.message = 'Terjadi kendala. Coba lagi beberapa saat.',
  ]);
}
