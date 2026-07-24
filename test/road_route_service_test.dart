import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jowla_driver/core/services/road_route_service.dart';
import 'package:latlong2/latlong.dart';

class _RouteAdapter implements HttpClientAdapter {
  String? path;
  Map<String, dynamic>? query;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    path = options.path;
    query = options.queryParameters;
    return ResponseBody.fromString(
      jsonEncode({
        'code': 'Ok',
        'routes': [
          {'geometry': '_p~iF~ps|U_ulLnnqC_mqNvxq`@'},
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _MapMatchingAdapter implements HttpClientAdapter {
  String? path;
  Map<String, dynamic>? query;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    path = options.path;
    query = options.queryParameters;
    final payload = options.path.startsWith('/nearest/')
        ? {
            'code': 'Ok',
            'waypoints': [
              {
                'location': [44.3662, 33.3153],
                'distance': 12.5,
                'name': 'شارع الرشيد',
              },
            ],
          }
        : {
            'code': 'Ok',
            'matchings': [
              {'confidence': 0.91},
            ],
            'tracepoints': [
              {
                'location': [44.3662, 33.3153],
                'distance': 9.0,
              },
              {
                'location': [44.3670, 33.3160],
                'distance': 7.0,
              },
            ],
          };
    return ResponseBody.fromString(
      jsonEncode(payload),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('يفك ترميز polyline القادم من OSRM إلى نقاط خريطة', () {
    final points = RoadRouteService.decodePolyline(
      '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
    );

    expect(points, hasLength(3));
    expect(points.first.latitude, closeTo(38.5, 0.00001));
    expect(points.first.longitude, closeTo(-120.2, 0.00001));
    expect(points.last.latitude, closeTo(43.252, 0.00001));
    expect(points.last.longitude, closeTo(-126.453, 0.00001));
  });

  test('يطلب مسار قيادة من OSRM بالصيغة الصحيحة', () async {
    final adapter = _RouteAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://osrm.test'))
      ..httpClientAdapter = adapter;
    final service = RoadRouteService(client: dio);

    final points = await service.route(
      const RoadRouteRequest(
        startLat: 30.9652,
        startLng: 46.9938,
        endLat: 30.9601,
        endLng: 46.9769,
      ),
    );

    expect(points, hasLength(3));
    expect(adapter.path, '/route/v1/driving/46.9938,30.9652;46.9769,30.9601');
    expect(adapter.query, {'overview': 'full', 'geometries': 'polyline'});
  });

  test('يثبت نقطة الالتقاط على أقرب طريق عبر OSRM Nearest', () async {
    final adapter = _MapMatchingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://osrm.test'))
      ..httpClientAdapter = adapter;

    final result = await RoadRouteService(
      client: dio,
    ).nearest(const LatLng(33.3152, 44.3661));

    expect(result, isNotNull);
    expect(result!.distanceMeters, 12.5);
    expect(result.roadName, 'شارع الرشيد');
    expect(adapter.path, '/nearest/v1/driving/44.3661,33.3152');
    expect(adapter.query, {'number': 1});
  });

  test('يرسل نافذة GPS إلى OSRM Match مع الدقة والتوقيت', () async {
    final adapter = _MapMatchingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://osrm.test'))
      ..httpClientAdapter = adapter;
    final service = RoadRouteService(client: dio);

    final result = await service.matchTrace([
      RoadTracePoint(
        point: const LatLng(33.3152, 44.3661),
        recordedAt: DateTime.utc(2026, 7, 23, 12),
        accuracyMeters: 8,
      ),
      RoadTracePoint(
        point: const LatLng(33.3161, 44.3671),
        recordedAt: DateTime.utc(2026, 7, 23, 12, 0, 5),
        accuracyMeters: 10,
      ),
    ]);

    expect(result, isNotNull);
    expect(result!.confidence, 0.91);
    expect(result.matchedTrace, hasLength(2));
    expect(adapter.path, contains('/match/v1/driving/'));
    expect(adapter.query?['radiuses'], '8;10');
    expect(adapter.query?['timestamps'], '1784808000;1784808005');
  });
}
