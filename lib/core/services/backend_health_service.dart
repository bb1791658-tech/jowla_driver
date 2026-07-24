import 'dart:async';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../errors/app_exception.dart';

/// يتحقق من GET /api/health — يرجع {status: 'ok', service: 'jowla-api'}
/// وفق monitoring.controller.ts.
class BackendHealthService {
  BackendHealthService({Dio? client, this.originCandidates})
    : _dio =
          client ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 2),
              receiveTimeout: const Duration(seconds: 2),
              headers: const {'Accept': 'application/json'},
            ),
          );

  final Dio _dio;
  final List<String>? originCandidates;

  Future<void> checkHealth() async {
    final healthyOrigin = await _firstHealthyOrigin(
      originCandidates ?? AppConfig.backendOriginCandidates,
    );
    if (healthyOrigin != null) {
      AppConfig.useBackendOrigin(healthyOrigin);
      return;
    }

    throw AppException(
      'تعذر الاتصال بخادم جولة. تأكد من تشغيل الخادم ثم أعد المحاولة. '
      '${AppConfig.backendConnectionHint}',
    );
  }

  Future<String?> _firstHealthyOrigin(List<String> origins) async {
    if (origins.isEmpty) return null;

    final completer = Completer<String?>();
    var remaining = origins.length;

    for (final origin in origins) {
      _isHealthy(origin).then((isHealthy) {
        if (completer.isCompleted) return;
        if (isHealthy) {
          completer.complete(origin);
          return;
        }
        remaining -= 1;
        if (remaining == 0) completer.complete(null);
      });
    }

    return completer.future;
  }

  Future<bool> _isHealthy(String origin) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        AppConfig.healthUrlForOrigin(origin),
      );
      return response.data?['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }
}
