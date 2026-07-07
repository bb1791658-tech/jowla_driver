import 'models/driver_session.dart';

abstract interface class AuthRepository {
  Future<OtpRequestResult> requestOtp(String phone);

  Future<DriverProfile> verifyOtp({
    required String phone,
    required String code,
    required String platform,
  });

  Future<DriverProfile?> restoreSession();

  Future<void> logout();
}
