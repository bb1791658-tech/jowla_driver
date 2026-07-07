class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class LocationException extends AppException {
  const LocationException(super.message);
}
