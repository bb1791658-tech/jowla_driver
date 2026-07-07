import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/api_paths.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/storage/session_store.dart';
import '../domain/auth_repository.dart';
import '../domain/models/driver_session.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => BackendAuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(sessionStoreProvider),
  ),
);

/// المصادقة الحقيقية عبر WhatsApp OTP وفق auth.controller.ts:
/// - POST /auth/otp/request {phone} → {requestId, expiresAt, mockCode?}.
/// - POST /auth/otp/verify {phone, code, deviceKey, platform,
///   accountType: 'DRIVER'} → {accessToken, refreshToken, driver, user, device}.
/// - DELETE /auth/sessions/current لتسجيل الخروج من هذا الجهاز.
class BackendAuthRepository implements AuthRepository {
  const BackendAuthRepository(this._client, this._store);

  final ApiClient _client;
  final SessionStore _store;
  static const _devAccessToken = 'jowla-debug-access-token';
  static const _devRefreshToken = 'jowla-debug-refresh-token';

  @override
  Future<OtpRequestResult> requestOtp(String phone) async {
    if (kDebugMode &&
        AppConfig.enableLocalDevAuth &&
        phone == AppConfig.devWhatsappPhone) {
      return OtpRequestResult(
        requestId: 'debug-request',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        mockCode: AppConfig.devOtpCode,
      );
    }
    try {
      final response = await _client.dio.post<Map<String, dynamic>>(
        ApiPaths.requestOtp,
        data: {'phone': phone},
      );
      return OtpRequestResult.fromJson(response.data ?? const {});
    } catch (error) {
      throw ApiClient.mapError(error);
    }
  }

  @override
  Future<DriverProfile> verifyOtp({
    required String phone,
    required String code,
    required String platform,
  }) async {
    if (kDebugMode &&
        AppConfig.enableLocalDevAuth &&
        phone == AppConfig.devWhatsappPhone &&
        code == AppConfig.devOtpCode) {
      const driver = DriverProfile(
        id: AppConfig.devDriverId,
        name: 'سائق التطوير',
        phone: AppConfig.devWhatsappPhone,
        status: DriverAccountStatus.approved,
      );
      await _store.saveSession(
        const DriverSession(
          accessToken: _devAccessToken,
          refreshToken: _devRefreshToken,
          driver: driver,
        ),
      );
      return driver;
    }
    try {
      final deviceKey = await _store.getOrCreateInstallationId();
      final response = await _client.dio.post<Map<String, dynamic>>(
        ApiPaths.verifyOtp,
        data: {
          'phone': phone,
          'code': code,
          'deviceKey': deviceKey,
          'platform': platform,
          'accountType': 'DRIVER',
        },
      );
      final data = response.data ?? const {};
      final accessToken = data['accessToken']?.toString() ?? '';
      final refreshToken = data['refreshToken']?.toString() ?? '';
      final driverJson = data['driver'];
      if (accessToken.isEmpty || refreshToken.isEmpty || driverJson is! Map) {
        throw const AppException('استجابة تسجيل الدخول غير مكتملة.');
      }
      final driver = DriverProfile.fromJson(
        Map<String, dynamic>.from(driverJson),
      );
      if (driver.id.isEmpty) {
        throw const AppException('استجابة تسجيل الدخول غير مكتملة.');
      }
      await _store.saveSession(
        DriverSession(
          accessToken: accessToken,
          refreshToken: refreshToken,
          driver: driver,
        ),
      );
      return driver;
    } catch (error) {
      throw ApiClient.mapError(error);
    }
  }

  @override
  Future<DriverProfile?> restoreSession() async {
    final session = await _store.readSession();
    if (session?.accessToken == _devAccessToken && !kDebugMode) {
      await _store.clearSession();
      return null;
    }
    return session?.driver;
  }

  @override
  Future<void> logout() async {
    try {
      await _client.dio.delete<void>(ApiPaths.currentSession);
    } catch (_) {
      // تسجيل الخروج المحلي يكتمل حتى لو تعذر الوصول إلى الخادم.
    } finally {
      await _store.clearSession();
    }
  }
}
