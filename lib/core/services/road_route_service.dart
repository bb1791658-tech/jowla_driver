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

final roadRouteDetailsProvider = FutureProvider.autoDispose
    .family<RoadRoute?, RoadRouteRequest>((ref, request) async {
      return ref.watch(roadRouteServiceProvider).routeDetails(request);
    });

@immutable
class RoadRoute {
  const RoadRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  Duration get duration => Duration(seconds: durationSeconds.round());
}

@immutable
class SnappedRoadPoint {
  const SnappedRoadPoint({
    required this.point,
    required this.distanceMeters,
    this.roadName,
  });

  final LatLng point;
  final double distanceMeters;
  final String? roadName;
}

@immutable
class RoadTracePoint {
  const RoadTracePoint({
    required this.point,
    required this.recordedAt,
    required this.accuracyMeters,
  });

  final LatLng point;
  final DateTime recordedAt;
  final double accuracyMeters;
}

@immutable
class RoadMatch {
  const RoadMatch({
    required this.point,
    required this.confidence,
    required this.distanceMeters,
    required this.matchedTrace,
  });

  final LatLng point;
  final double confidence;
  final double distanceMeters;
  final List<LatLng> matchedTrace;
}

@immutable
class SmartEta {
  const SmartEta({
    required this.expected,
    required this.minimum,
    required this.maximum,
  });

  final Duration expected;
  final Duration minimum;
  final Duration maximum;
}

abstract final class TravelTimeEstimator {
  static SmartEta estimate({
    required RoadRoute route,
    required DateTime localDeparture,
    double? currentSpeedMetersPerSecond,
    double historicalFactor = 1,
  }) {
    final hour = localDeparture.hour;
    final weekday = localDeparture.weekday;
    final isWeekend = weekday == DateTime.friday;
    final isPeak =
        !isWeekend && ((hour >= 7 && hour < 10) || (hour >= 14 && hour < 19));
    final timeFactor = isPeak ? 1.22 : (hour >= 22 || hour < 6 ? 0.93 : 1.0);
    final history = historicalFactor.clamp(0.75, 1.8);
    var seconds = route.durationSeconds * timeFactor * history;

    if (currentSpeedMetersPerSecond != null &&
        currentSpeedMetersPerSecond.isFinite &&
        currentSpeedMetersPerSecond >= 2) {
      final speedBasedSeconds =
          route.distanceMeters / currentSpeedMetersPerSecond;
      final bounded = speedBasedSeconds.clamp(
        route.durationSeconds * 0.75,
        route.durationSeconds * 2.2,
      );
      seconds = seconds * 0.8 + bounded * 0.2;
    }

    final expectedSeconds = seconds.round().clamp(60, 86400);
    return SmartEta(
      expected: Duration(seconds: expectedSeconds),
      minimum: Duration(seconds: (expectedSeconds * 0.88).round()),
      maximum: Duration(seconds: (expectedSeconds * 1.18).round()),
    );
  }
}

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
    final details = await routeDetails(request);
    return details?.points ?? const [];
  }

  Future<RoadRoute?> routeDetails(RoadRouteRequest request) async {
    final alternatives = await routeAlternatives(request, count: 1);
    return alternatives.isEmpty ? null : alternatives.first;
  }

  Future<List<RoadRoute>> routeAlternatives(
    RoadRouteRequest request, {
    int count = 2,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/route/v1/driving/'
      '${request.startLng},${request.startLat};'
      '${request.endLng},${request.endLat}',
      queryParameters: {
        'overview': 'full',
        'geometries': 'polyline',
        if (count > 1) 'alternatives': count,
      },
    );
    final data = response.data ?? const {};
    if (data['code'] != 'Ok') return const <RoadRoute>[];
    final routes = data['routes'];
    if (routes is! List || routes.isEmpty) return const <RoadRoute>[];

    final parsed = <RoadRoute>[];
    for (final candidate in routes.take(count)) {
      if (candidate is! Map) continue;
      final geometry = candidate['geometry'];
      if (geometry is! String || geometry.isEmpty) continue;
      final points = decodePolyline(geometry);
      if (points.length < 2) continue;
      parsed.add(
        RoadRoute(
          points: points,
          distanceMeters: _asDouble(candidate['distance']),
          durationSeconds: _asDouble(candidate['duration']),
        ),
      );
    }
    return parsed;
  }

  Future<SnappedRoadPoint?> nearest(
    LatLng point, {
    double maxDistanceMeters = 100,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/nearest/v1/driving/${point.longitude},${point.latitude}',
      queryParameters: const {'number': 1},
    );
    final data = response.data ?? const {};
    if (data['code'] != 'Ok') return null;
    final waypoints = data['waypoints'];
    if (waypoints is! List || waypoints.isEmpty) return null;
    final waypoint = waypoints.first;
    if (waypoint is! Map) return null;
    final snapped = _coordinate(waypoint['location']);
    if (snapped == null) return null;
    final distance = _asDouble(waypoint['distance']);
    if (!distance.isFinite || distance > maxDistanceMeters) return null;
    final name = waypoint['name']?.toString().trim();
    return SnappedRoadPoint(
      point: snapped,
      distanceMeters: distance,
      roadName: name == null || name.isEmpty ? null : name,
    );
  }

  Future<RoadMatch?> matchTrace(
    List<RoadTracePoint> trace, {
    double minimumConfidence = 0.15,
    double maxSnapDistanceMeters = 100,
  }) async {
    if (trace.length < 2) return null;
    final sample = trace.length > 8
        ? trace.sublist(trace.length - 8)
        : List<RoadTracePoint>.of(trace);
    final coordinates = sample
        .map((item) => '${item.point.longitude},${item.point.latitude}')
        .join(';');

    var previousTimestamp = 0;
    final timestamps = <int>[];
    for (final item in sample) {
      final current = item.recordedAt.toUtc().millisecondsSinceEpoch ~/ 1000;
      final normalized = current <= previousTimestamp
          ? previousTimestamp + 1
          : current;
      timestamps.add(normalized);
      previousTimestamp = normalized;
    }
    final radiuses = sample
        .map((item) => item.accuracyMeters.clamp(5, 100).round())
        .join(';');

    final response = await _dio.get<Map<String, dynamic>>(
      '/match/v1/driving/$coordinates',
      queryParameters: {
        'timestamps': timestamps.join(';'),
        'radiuses': radiuses,
        'gaps': 'split',
        'tidy': true,
        'overview': false,
      },
    );
    final data = response.data ?? const {};
    if (data['code'] != 'Ok') return null;

    final matchings = data['matchings'];
    var confidence = 0.0;
    if (matchings is List && matchings.isNotEmpty) {
      final first = matchings.first;
      if (first is Map) confidence = _asDouble(first['confidence']);
    }
    if (!confidence.isFinite || confidence < minimumConfidence) return null;

    final tracepoints = data['tracepoints'];
    if (tracepoints is! List || tracepoints.isEmpty) return null;
    final matchedTrace = <LatLng>[];
    var latestDistance = double.infinity;
    for (final item in tracepoints) {
      if (item is! Map) continue;
      final location = _coordinate(item['location']);
      if (location == null) continue;
      matchedTrace.add(location);
      latestDistance = _asDouble(item['distance']);
    }
    if (matchedTrace.isEmpty ||
        !latestDistance.isFinite ||
        latestDistance > maxSnapDistanceMeters) {
      return null;
    }
    return RoadMatch(
      point: matchedTrace.last,
      confidence: confidence,
      distanceMeters: latestDistance,
      matchedTrace: matchedTrace,
    );
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

  static LatLng? _coordinate(Object? raw) {
    if (raw is! List || raw.length < 2) return null;
    final longitude = _nullableDouble(raw[0]);
    final latitude = _nullableDouble(raw[1]);
    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite) {
      return null;
    }
    return LatLng(latitude, longitude);
  }

  static double _asDouble(Object? value) => _nullableDouble(value) ?? 0;

  static double? _nullableDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class _DecodedValue {
  const _DecodedValue(this.value, this.nextIndex);

  final int value;
  final int nextIndex;
}
