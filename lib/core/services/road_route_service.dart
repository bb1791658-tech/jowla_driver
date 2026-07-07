import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';

final roadRouteServiceProvider = Provider<RoadRouteService>(
  (ref) => RoadRouteService(),
);

final roadRoutePathProvider = FutureProvider.autoDispose
    .family<List<LatLng>, RoadRouteRequest>((ref, request) async {
      return ref.watch(roadRouteServiceProvider).route(request);
    });

@immutable
class RoadRouteRequest {
  const RoadRouteRequest({
    required this.startLat,
    required this.startLng,
    required this.endLat,
    required this.endLng,
  });

  factory RoadRouteRequest.fromPoints(LatLng start, LatLng end) {
    return RoadRouteRequest(
      startLat: _roundCoordinate(start.latitude),
      startLng: _roundCoordinate(start.longitude),
      endLat: _roundCoordinate(end.latitude),
      endLng: _roundCoordinate(end.longitude),
    );
  }

  final double startLat;
  final double startLng;
  final double endLat;
  final double endLng;

  LatLng get start => LatLng(startLat, startLng);
  LatLng get end => LatLng(endLat, endLng);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RoadRouteRequest &&
            other.startLat == startLat &&
            other.startLng == startLng &&
            other.endLat == endLat &&
            other.endLng == endLng;
  }

  @override
  int get hashCode => Object.hash(startLat, startLng, endLat, endLng);

  static double _roundCoordinate(double value) {
    const factor = 100000.0;
    return (value * factor).roundToDouble() / factor;
  }
}

class RoadRouteService {
  RoadRouteService({Dio? client})
    : _dio =
          client ??
          Dio(
            BaseOptions(
              baseUrl: AppConfig.roadRouteBaseUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              headers: const {'Accept': 'application/json'},
            ),
          );

  final Dio _dio;

  Future<List<LatLng>> route(RoadRouteRequest request) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/route/v1/driving/'
      '${request.startLng},${request.startLat};'
      '${request.endLng},${request.endLat}',
      queryParameters: const {'overview': 'full', 'geometries': 'polyline'},
    );
    final data = response.data ?? const {};
    if (data['code'] != 'Ok') return const [];
    final routes = data['routes'];
    if (routes is! List || routes.isEmpty) return const [];
    final first = routes.first;
    if (first is! Map) return const [];
    final geometry = first['geometry'];
    if (geometry is! String || geometry.isEmpty) return const [];
    final points = decodePolyline(geometry);
    return points.length >= 2 ? points : const [];
  }

  @visibleForTesting
  static List<LatLng> decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      final latResult = _decodeValue(encoded, index);
      index = latResult.nextIndex;
      lat += latResult.value;

      final lngResult = _decodeValue(encoded, index);
      index = lngResult.nextIndex;
      lng += lngResult.value;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return points;
  }

  static _DecodedValue _decodeValue(String encoded, int startIndex) {
    var result = 0;
    var shift = 0;
    var index = startIndex;

    while (index < encoded.length) {
      final byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
      if (byte < 0x20) {
        final value = (result & 1) == 1 ? ~(result >> 1) : result >> 1;
        return _DecodedValue(value, index);
      }
    }

    throw const FormatException('Invalid polyline');
  }
}

class _DecodedValue {
  const _DecodedValue(this.value, this.nextIndex);

  final int value;
  final int nextIndex;
}
