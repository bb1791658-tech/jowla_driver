import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../errors/app_exception.dart';

/// يتحقق من GET /api/health — يرجع {status: 'ok', service: 'jowla-api'}
/// وفق monitoring.controller.ts.
class BackendHealthService {
  BackendHealthService({Dio? client})
      : _dio = client ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
                headers: const {'Accept': 'application/json'},
              ),
            );

  final Dio _dio;

  Future<void> checkHealth() async {
    try {
      final response =
          await _dio.get<Map<String, dynamic>>(AppConfig.healthUrl);
      if (response.data?['status'] != 'ok') {
        throw const AppException('استجابة الخادم غير صالحة.');
      }
    } catch (_) {
      throw AppException(
        'تعذر الاتصال بخادم جولة. تأكد من تشغيل الخادم ثم أعد المحاولة. '
        '${AppConfig.backendConnectionHint}',
      );
    }
  }
}
