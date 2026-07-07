import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../constants/api_paths.dart';
import '../errors/app_exception.dart';
import '../services/session_events.dart';
import '../storage/session_store.dart';

/// عميل HTTP موحد:
/// - يضيف Authorization: Bearer تلقائيًا.
/// - عند 401 يجدد التوكن عبر POST /auth/refresh (تدوير إلزامي:
///   الاستجابة تتضمن accessToken وrefreshToken جديدين وفق auth.service.ts)
///   ثم يعيد الطلب الأصلي مرة واحدة.
/// - تجديد واحد نشط في اللحظة الواحدة تتشاركه الطلبات المتزامنة.
/// - فشل التجديد = جلسة منتهية: مسح الجلسة وبث SessionEvents.
class ApiClient {
  ApiClient(
    this._sessionStore,
    this._sessionEvents, {
    Dio? client,
    Dio? refreshClient,
  })  : dio = client ?? _buildDio(),
        _refreshDio = refreshClient ?? _buildDio() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _sessionStore.readAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: _handleError,
      ),
    );
  }

  static const _retriedKey = 'session_refresh_retried';
  static const _publicPaths = {
    ApiPaths.requestOtp,
    ApiPaths.verifyOtp,
    ApiPaths.refreshToken,
  };

  final SessionStore _sessionStore;
  final SessionEvents _sessionEvents;
  final Dio _refreshDio;
  final Dio dio;
  Future<String?>? _activeRefresh;

  static Dio _buildDio() => Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          headers: const {'Accept': 'application/json'},
        ),
      );

  Future<void> _handleError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final request = error.requestOptions;
    final canRefresh = error.response?.statusCode == 401 &&
        request.extra[_retriedKey] != true &&
        !_publicPaths.contains(request.path);
    if (!canRefresh) {
      handler.next(error);
      return;
    }

    final accessToken = await _refreshAccessToken();
    if (accessToken == null) {
      handler.next(error);
      return;
    }

    try {
      request.extra[_retriedKey] = true;
      request.headers['Authorization'] = 'Bearer $accessToken';
      final response = await dio.fetch<dynamic>(request);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  Future<String?> _refreshAccessToken() async {
    final existing = _activeRefresh;
    if (existing != null) return existing;
    final refresh = _performRefresh();
    _activeRefresh = refresh;
    try {
      return await refresh;
    } finally {
      if (identical(_activeRefresh, refresh)) _activeRefresh = null;
    }
  }

  Future<String?> _performRefresh() async {
    final refreshToken = await _sessionStore.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await _expireSession();
      return null;
    }
    try {
      final response = await _refreshDio.post<Map<String, dynamic>>(
        ApiPaths.refreshToken,
        data: {'refreshToken': refreshToken},
      );
      final data = response.data ?? const {};
      final accessToken = data['accessToken']?.toString() ?? '';
      final rotatedRefreshToken = data['refreshToken']?.toString() ?? '';
      if (accessToken.isEmpty || rotatedRefreshToken.isEmpty) {
        await _expireSession();
        return null;
      }
      await _sessionStore.updateTokens(
        accessToken: accessToken,
        refreshToken: rotatedRefreshToken,
      );
      return accessToken;
    } on DioException {
      await _expireSession();
      return null;
    }
  }

  Future<void> _expireSession() async {
    await _sessionStore.clearSession();
    _sessionEvents.notifyExpired();
  }

  /// يحول أخطاء Dio إلى رسائل عربية. يستخرج رسالة الخادم من الشكل
  /// {message} أو {error: {message}} كما يرسلها AllExceptionsFilter.
  static AppException mapError(Object error) {
    if (error is AppException) return error;
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final nestedError = data['error'];
        final message = nestedError is Map<String, dynamic>
            ? nestedError['message']
            : data['message'];
        if (message is String && message.isNotEmpty) {
          return AppException(_translate(message));
        }
        if (message is List && message.isNotEmpty) {
          return AppException(message.join('\n'));
        }
      }
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return const AppException(
          'تعذر الاتصال بالخادم. تحقق من اتصالك بالإنترنت.',
        );
      }
      if (error.response?.statusCode == 401) {
        return const AppException('انتهت صلاحية الجلسة. سجّل الدخول مرة أخرى.');
      }
    }
    return const AppException('حدث خطأ غير متوقع. حاول مرة أخرى.');
  }

  /// ترجمة رسائل Backend الإنجليزية المعروفة (كما وردت حرفيًا في الكود).
  static String _translate(String message) => switch (message) {
        'Approved driver account is required' =>
          'لا يوجد حساب سائق معتمد بهذا الرقم. راجع إدارة جولة لاعتماد حسابك.',
        'OTP is invalid or expired' => 'رمز التحقق غير صحيح أو منتهي الصلاحية.',
        'OTP is invalid or already used' =>
          'رمز التحقق غير صالح أو استُخدم سابقًا.',
        'User account is blocked' => 'هذا الحساب محظور. راجع إدارة جولة.',
        'Driver is not approved for availability changes' =>
          'حسابك غير معتمد لتغيير حالة التوفر.',
        'Offer is no longer available' => 'انتهى هذا العرض ولم يعد متاحًا.',
        'Offer is no longer pending' => 'تم الرد على هذا العرض سابقًا.',
        'Offer has expired' => 'انتهت مهلة هذا العرض.',
        'Another driver already accepted' => 'قبل سائق آخر هذه الرحلة.',
        'Ride is not in trip_started state' =>
          'لا يمكن إنهاء الرحلة قبل بدئها.',
        'Ride cannot be cancelled in its current state' =>
          'لا يمكن إلغاء الرحلة في حالتها الحالية.',
        'Driver is not assigned' => 'هذه الرحلة غير مسندة إليك.',
        'Ride not found' => 'الرحلة غير موجودة.',
        'Offer not found' => 'العرض غير موجود.',
        'Driver not found' => 'حساب السائق غير موجود.',
        'WhatsApp OTP provider is not configured' =>
          'خدمة إرسال رمز واتساب غير مهيأة في الخادم حاليًا.',
        _ => message,
      };
}
