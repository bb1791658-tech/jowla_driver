import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jowla_driver/core/errors/app_exception.dart';
import 'package:jowla_driver/core/network/api_client.dart';
import 'package:jowla_driver/core/services/session_events.dart';
import 'package:jowla_driver/core/storage/session_store.dart';
import 'package:jowla_driver/features/rides/data/backend_ride_repository.dart';
import 'package:jowla_driver/features/rides/domain/models/ride.dart';

import 'support/fakes.dart';

class _RouteAdapter implements HttpClientAdapter {
  _RouteAdapter(this.routes);

  final Map<String, (int, Object)> routes;
  final log = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = '${options.method} ${options.path}';
    log.add(key);
    final route = routes[key];
    if (route == null) {
      return ResponseBody.fromString(
        jsonEncode({'message': 'Not found'}),
        404,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(route.$2),
      route.$1,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

BackendRideRepository _repo(_RouteAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://backend/api/v1'))
    ..httpClientAdapter = adapter;
  final client = ApiClient(
    SessionStore(InMemorySecureStore()),
    SessionEvents(),
    client: dio,
    refreshClient: dio,
  );
  return BackendRideRepository(client);
}

Map<String, Object> _rideJson(String status) => {
  'id': 'ride-1',
  'status': status,
  'pickupLat': '30.9601000',
  'pickupLng': '46.9769000',
  'dropoffLat': '30.9700000',
  'dropoffLng': '46.9900000',
  'estimatedFare': '5000.00',
  'distanceKm': '3.250',
  'currency': 'IQD',
};

void main() {
  test('currentRide يفسر null عندما لا توجد رحلة نشطة', () async {
    final adapter = _RouteAdapter({
      'GET /rides/driver/current': (200, <String, Object>{}),
    });
    expect(await _repo(adapter).currentRide(), isNull);
  });

  test('قبول العرض يستدعي POST accept ويرجع الرحلة المسندة', () async {
    final adapter = _RouteAdapter({
      'POST /rides/ride-1/offers/offer-1/accept': (
        200,
        _rideJson('DRIVER_ACCEPTED'),
      ),
    });
    final ride = await _repo(
      adapter,
    ).acceptOffer(rideId: 'ride-1', offerId: 'offer-1');
    expect(ride.status, RideStatus.driverAccepted);
    expect(adapter.log, ['POST /rides/ride-1/offers/offer-1/accept']);
  });

  test('تعارض القبول (سائق آخر) يتحول لرسالة عربية', () async {
    final adapter = _RouteAdapter({
      'POST /rides/ride-1/offers/offer-1/accept': (
        409,
        {'message': 'Another driver already accepted'},
      ),
    });
    await expectLater(
      _repo(adapter).acceptOffer(rideId: 'ride-1', offerId: 'offer-1'),
      throwsA(
        isA<AppException>().having(
          (e) => e.message,
          'message',
          contains('سائق آخر'),
        ),
      ),
    );
  });

  test('تسلسل الانتقالات يستخدم مسارات Backend الصحيحة', () async {
    final adapter = _RouteAdapter({
      'POST /rides/ride-1/driver-arrived': (200, _rideJson('DRIVER_ARRIVED')),
      'POST /rides/ride-1/start': (200, _rideJson('TRIP_STARTED')),
      'POST /rides/ride-1/pause': (200, _rideJson('TRIP_PAUSED')),
      'POST /rides/ride-1/resume': (200, _rideJson('TRIP_STARTED')),
      'POST /rides/ride-1/complete': (
        200,
        {
          ..._rideJson('COMPLETED'),
          'finalFare': '5250.00',
          'payment': {'amount': '5250.00', 'commissionAmount': '250.00'},
        },
      ),
    });
    final repo = _repo(adapter);
    expect(
      (await repo.driverArrived('ride-1')).status,
      RideStatus.driverArrived,
    );
    expect((await repo.startTrip('ride-1')).status, RideStatus.tripStarted);
    expect((await repo.pauseTrip('ride-1')).status, RideStatus.tripPaused);
    expect((await repo.resumeTrip('ride-1')).status, RideStatus.tripStarted);
    final completed = await repo.completeTrip('ride-1');
    expect(completed.status, RideStatus.completed);
    expect(completed.payment?.netAmount, 5000);
  });

  test('انقطاع الشبكة يتحول إلى AppException عربية', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://backend/api/v1'));
    dio.httpClientAdapter = _FailingAdapter();
    final client = ApiClient(
      SessionStore(InMemorySecureStore()),
      SessionEvents(),
      client: dio,
      refreshClient: dio,
    );
    await expectLater(
      BackendRideRepository(client).currentRide(),
      throwsA(
        isA<AppException>().having(
          (e) => e.message,
          'message',
          contains('تعذر الاتصال'),
        ),
      ),
    );
  });
}

class _FailingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
    );
  }

  @override
  void close({bool force = false}) {}
}
