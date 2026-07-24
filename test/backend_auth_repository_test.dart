import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jowla_driver/core/constants/api_paths.dart';
import 'package:jowla_driver/core/errors/app_exception.dart';
import 'package:jowla_driver/core/network/api_client.dart';
import 'package:jowla_driver/core/services/session_events.dart';
import 'package:jowla_driver/core/storage/session_store.dart';
import 'package:jowla_driver/features/auth/data/backend_auth_repository.dart';

import 'support/fakes.dart';

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);

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

void main() {
  test('طلب OTP يرسل نوع حساب السائق كما يتطلب Backend', () async {
    final store = SessionStore(InMemorySecureStore());
    final events = SessionEvents();
    final dio = Dio(BaseOptions(baseUrl: 'http://backend/api/v1'));
    final requests = <Map<String, dynamic>>[];
    dio.httpClientAdapter = _ScriptedAdapter((options) async {
      expect(options.path, ApiPaths.requestOtp);
      requests.add(Map<String, dynamic>.from(options.data as Map));
      return _json({'requestId': 'req-1'}, 200);
    });

    final client = ApiClient(store, events, client: dio);
    final repo = BackendAuthRepository(client, store);

    final result = await repo.requestOtp('+9647701234567');

    expect(result.requestId, 'req-1');
    expect(requests, [
      {'phone': '+9647701234567', 'accountType': 'DRIVER'},
    ]);
    events.dispose();
  });

  test('التحقق يربط الرمز بطلب OTP والجهاز نفسه', () async {
    final store = SessionStore(InMemorySecureStore());
    final events = SessionEvents();
    final dio = Dio(BaseOptions(baseUrl: 'http://backend/api/v1'));
    late Map<String, dynamic> payload;
    dio.httpClientAdapter = _ScriptedAdapter((options) async {
      expect(options.path, ApiPaths.verifyOtp);
      payload = Map<String, dynamic>.from(options.data as Map);
      return _json({
        'accessToken': 'access',
        'refreshToken': 'refresh',
        'driver': {
          'id': '11111111-1111-4111-8111-111111111111',
          'name': 'سائق',
          'phone': '+9647701234567',
          'status': 'APPROVED',
        },
      }, 200);
    });

    final repo = BackendAuthRepository(
      ApiClient(store, events, client: dio),
      store,
    );
    await repo.verifyOtp(
      phone: '+9647701234567',
      code: '123456',
      requestId: '21111111-1111-4111-8111-111111111111',
      platform: 'android',
    );

    expect(
      payload,
      containsPair('requestId', '21111111-1111-4111-8111-111111111111'),
    );
    expect(payload, containsPair('accountType', 'DRIVER'));
    expect(payload['deviceKey'], isNotEmpty);
    expect(await store.readSession(), isNotNull);
    events.dispose();
  });

  test('فشل الاتصال لا ينشئ جلسة محلية بديلة', () async {
    final store = SessionStore(InMemorySecureStore());
    final events = SessionEvents();
    final dio = Dio(BaseOptions(baseUrl: 'http://backend/api/v1'));
    dio.httpClientAdapter = _ScriptedAdapter((options) async {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'backend offline',
      );
    });

    final client = ApiClient(store, events, client: dio);
    final repo = BackendAuthRepository(client, store);

    await expectLater(
      repo.requestOtp('+9647700000001'),
      throwsA(isA<AppException>()),
    );
    final session = await store.readSession();

    expect(session, isNull);
    events.dispose();
  });
}
