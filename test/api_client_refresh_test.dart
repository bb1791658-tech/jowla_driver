import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jowla_driver/core/network/api_client.dart';
import 'package:jowla_driver/core/services/session_events.dart';
import 'package:jowla_driver/core/storage/session_store.dart';
import 'package:jowla_driver/features/auth/domain/models/driver_session.dart';

import 'support/fakes.dart';

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object data, int status) => ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

Future<SessionStore> _storeWithSession() async {
  final store = SessionStore(InMemorySecureStore());
  await store.saveSession(
    const DriverSession(
      accessToken: 'old-access',
      refreshToken: 'old-refresh',
      driver: DriverProfile(
        id: 'driver-1',
        name: 'سائق',
        phone: '+9647700000001',
      ),
    ),
  );
  return store;
}

void main() {
  test('401 يجدد التوكن بتدوير كامل ثم يعيد الطلب مرة واحدة', () async {
    final store = await _storeWithSession();
    final events = SessionEvents();
    final requestLog = <String>[];

    final mainDio = Dio(BaseOptions(baseUrl: 'http://backend/api/v1'));
    final refreshDio = Dio(BaseOptions(baseUrl: 'http://backend/api/v1'));

    mainDio.httpClientAdapter = _ScriptedAdapter((options) async {
      requestLog.add('${options.method} ${options.path} '
          '${options.headers['Authorization']}');
      final isRetry = options.headers['Authorization'] == 'Bearer new-access';
      if (options.path == '/drivers/me' && !isRetry) {
        return _json({'message': 'Unauthorized'}, 401);
      }
      return _json({'id': 'driver-1', 'name': 'س', 'phone': 'p'}, 200);
    });
    refreshDio.httpClientAdapter = _ScriptedAdapter((options) async {
      expect(options.path, '/auth/refresh');
      expect(options.data, {'refreshToken': 'old-refresh'});
      return _json(
        {'accessToken': 'new-access', 'refreshToken': 'new-refresh'},
        200,
      );
    });

    final client = ApiClient(
      store,
      events,
      client: mainDio,
      refreshClient: refreshDio,
    );

    final response = await client.dio.get<Map<String, dynamic>>('/drivers/me');
    expect(response.statusCode, 200);
    // تم تدوير التوكنين معًا كما يفرض auth.service.refresh.
    expect(await store.readAccessToken(), 'new-access');
    expect(await store.readRefreshToken(), 'new-refresh');
    expect(
      requestLog.where((line) => line.contains('/drivers/me')).length,
      2,
    );
    events.dispose();
  });

  test('فشل التجديد يمسح الجلسة ويبث انتهاءها', () async {
    final store = await _storeWithSession();
    final events = SessionEvents();
    var expired = false;
    final subscription = events.expired.listen((_) => expired = true);

    final mainDio = Dio(BaseOptions(baseUrl: 'http://backend/api/v1'));
    final refreshDio = Dio(BaseOptions(baseUrl: 'http://backend/api/v1'));
    mainDio.httpClientAdapter = _ScriptedAdapter(
      (options) async => _json({'message': 'Unauthorized'}, 401),
    );
    refreshDio.httpClientAdapter = _ScriptedAdapter(
      (options) async =>
          _json({'message': 'Refresh token reuse detected'}, 401),
    );

    final client = ApiClient(
      store,
      events,
      client: mainDio,
      refreshClient: refreshDio,
    );

    await expectLater(
      client.dio.get<Map<String, dynamic>>('/drivers/me'),
      throwsA(isA<DioException>()),
    );
    expect(await store.readSession(), isNull);
    expect(expired, isTrue);
    await subscription.cancel();
    events.dispose();
  });

  test('mapError يترجم رسائل Backend المعروفة إلى العربية', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/auth/otp/verify'),
      response: Response(
        requestOptions: RequestOptions(path: '/auth/otp/verify'),
        statusCode: 403,
        data: {'message': 'Approved driver account is required'},
      ),
      type: DioExceptionType.badResponse,
    );
    expect(
      ApiClient.mapError(error).message,
      contains('لا يوجد حساب سائق معتمد'),
    );

    final timeout = DioException(
      requestOptions: RequestOptions(path: '/rides/driver/current'),
      type: DioExceptionType.connectionTimeout,
    );
    expect(ApiClient.mapError(timeout).message, contains('تعذر الاتصال'));
    expect(ApiClient.mapError(timeout).message, contains('العنوان المستخدم'));
  });
}
