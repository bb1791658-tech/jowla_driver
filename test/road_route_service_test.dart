import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jowla_driver/core/services/road_route_service.dart';

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
}
