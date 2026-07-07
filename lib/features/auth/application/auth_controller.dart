import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/backend_auth_repository.dart';
import '../domain/models/driver_session.dart';

/// حالة الجلسة: ملف السائق المسجل أو null.
final authSessionProvider =
    AsyncNotifierProvider<AuthSessionController, DriverProfile?>(
  AuthSessionController.new,
);

class AuthSessionController extends AsyncNotifier<DriverProfile?> {
  @override
  Future<DriverProfile?> build() async {
    final subscription = ref.read(sessionEventsProvider).expired.listen((_) {
      ref.read(realtimeServiceProvider).disconnect();
      state = const AsyncData(null);
    });
    ref.onDispose(subscription.cancel);
    return ref.read(authRepositoryProvider).restoreSession();
  }

  void sessionStarted(DriverProfile driver) {
    state = AsyncData(driver);
  }

  Future<void> logout() async {
    ref.read(realtimeServiceProvider).disconnect();
    await ref.read(authRepositoryProvider).logout();
    state = const AsyncData(null);
  }
}

enum AuthStep { phone, otp }

class LoginState {
  const LoginState({
    this.step = AuthStep.phone,
    this.phone = '',
    this.isLoading = false,
    this.error,
    this.mockCode,
    this.otpExpiresAt,
  });

  final AuthStep step;
  final String phone;
  final bool isLoading;
  final String? error;

  /// يرجعه Backend في التطوير فقط عند OTP_EXPOSE_MOCK_CODE=true.
  final String? mockCode;
  final DateTime? otpExpiresAt;

  LoginState copyWith({
    AuthStep? step,
    String? phone,
    bool? isLoading,
    String? error,
    String? mockCode,
    DateTime? otpExpiresAt,
    bool clearError = false,
  }) =>
      LoginState(
        step: step ?? this.step,
        phone: phone ?? this.phone,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : error ?? this.error,
        mockCode: mockCode ?? this.mockCode,
        otpExpiresAt: otpExpiresAt ?? this.otpExpiresAt,
      );
}

final loginControllerProvider =
    NotifierProvider.autoDispose<LoginController, LoginState>(
  LoginController.new,
);

class LoginController extends AutoDisposeNotifier<LoginState> {
  @override
  LoginState build() => const LoginState();

  Future<bool> requestOtp(String phone) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final result =
          await ref.read(authRepositoryProvider).requestOtp(phone);
      state = LoginState(
        step: AuthStep.otp,
        phone: phone,
        mockCode: kDebugMode ? result.mockCode : null,
        otpExpiresAt: result.expiresAt,
      );
      return true;
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
      return false;
    }
  }

  Future<bool> verifyOtp(String code) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final driver = await ref.read(authRepositoryProvider).verifyOtp(
            phone: state.phone,
            code: code,
            platform: _platform,
          );
      ref.read(authSessionProvider.notifier).sessionStarted(driver);
      state = state.copyWith(isLoading: false);
      return true;
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
      return false;
    }
  }

  void changePhone() => state = const LoginState();

  String get _platform => switch (defaultTargetPlatform) {
        TargetPlatform.iOS || TargetPlatform.macOS => 'ios',
        TargetPlatform.android => 'android',
        _ => 'web',
      };
}
