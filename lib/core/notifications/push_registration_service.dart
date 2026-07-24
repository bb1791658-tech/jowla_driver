import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../constants/api_paths.dart';
import '../network/api_client.dart';
import '../providers.dart';
import 'push_token_source.dart';

final pushTokenSourceProvider = Provider<PushTokenSource>((ref) {
  final source = AppConfig.pushNotificationsEnabled
      ? FirebasePushTokenSource()
      : const DisabledPushTokenSource();
  ref.onDispose(() => unawaited(source.dispose()));
  return source;
});

final pushRegistrationServiceProvider = Provider<PushRegistrationService>((
  ref,
) {
  final service = PushRegistrationService(
    ref.watch(apiClientProvider),
    ref.watch(pushTokenSourceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

class PushRegistrationService {
  PushRegistrationService(this._api, this._tokens);

  final ApiClient _api;
  final PushTokenSource _tokens;
  StreamSubscription<String>? _refreshSubscription;
  Future<void>? _activation;
  var _active = false;

  Future<void> activate() async {
    if (!AppConfig.pushNotificationsEnabled) return;
    final pending = _activation;
    if (pending != null) return pending;
    final activation = _activate();
    _activation = activation;
    try {
      await activation;
    } finally {
      if (identical(_activation, activation)) _activation = null;
    }
  }

  Future<void> _activate() async {
    _active = true;
    final token = await _tokens.requestToken();
    if (!_active) return;
    if (token != null && token.isNotEmpty) await _register(token);
    await _refreshSubscription?.cancel();
    _refreshSubscription = _tokens.tokenRefreshes.listen((token) {
      if (_active && token.isNotEmpty) unawaited(_register(token));
    });
  }

  Future<void> deactivate() async {
    _active = false;
    await _refreshSubscription?.cancel();
    _refreshSubscription = null;
  }

  Future<void> _register(String token) async {
    try {
      await _api.dio.put<void>(
        ApiPaths.currentPushToken,
        data: {'pushToken': token},
      );
    } on DioException {
      // فشل مزود الإشعارات لا يعطل تسجيل الدخول أو الرحلة النشطة.
    }
  }

  void dispose() {
    _active = false;
    unawaited(_refreshSubscription?.cancel());
  }
}
