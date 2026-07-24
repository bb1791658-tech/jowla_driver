import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'road_route_service.dart';

enum RouteRefreshReason { initial, destinationChanged, deviated }

/// يحتفظ بالمسار الحالي ولا يطلب مسارًا جديدًا عند كل تحديث GPS.
///
/// إعادة الحساب تحصل فقط بعد ثلاث قراءات متحركة ومتتالية خارج ممر المسار،
/// مع حد يتكيف مع دقة GPS وفاصل زمني يمنع التكرار المفرط.
class SmartRouteController extends ChangeNotifier {
  SmartRouteController(
    this._service, {
    this.minimumDeviationMeters = 45,
    this.requiredDeviationSamples = 3,
    this.rerouteCooldown = const Duration(seconds: 20),
    this.minimumEvaluationMovementMeters = 8,
  });

  final RoadRouteService _service;
  final double minimumDeviationMeters;
  final int requiredDeviationSamples;
  final Duration rerouteCooldown;
  final double minimumEvaluationMovementMeters;

  RoadRoute? _route;
  LatLng? _target;
  LatLng? _lastEvaluated;
  LatLng? _latestCurrent;
  DateTime? _lastRerouteAt;
  RouteRefreshReason? _lastRefreshReason;
  int _deviationSamples = 0;
  int _generation = 0;
  bool _loading = false;
  bool _fetchAgain = false;
  bool _disposed = false;

  RoadRoute? get route => _route;
  LatLng? get target => _target;
  bool get isLoading => _loading;
  int get deviationSamples => _deviationSamples;
  RouteRefreshReason? get lastRefreshReason => _lastRefreshReason;

  SmartEta? eta({
    double? currentSpeedMetersPerSecond,
    DateTime? localDeparture,
    double historicalFactor = 1,
  }) {
    final currentRoute = _route;
    if (currentRoute == null) return null;
    return TravelTimeEstimator.estimate(
      route: currentRoute,
      localDeparture: localDeparture ?? DateTime.now(),
      currentSpeedMetersPerSecond: currentSpeedMetersPerSecond,
      historicalFactor: historicalFactor,
    );
  }

  Future<void> update({
    required LatLng current,
    required LatLng target,
    double accuracyMeters = 0,
    DateTime? now,
  }) async {
    _latestCurrent = current;
    final targetChanged =
        _target == null ||
        const Distance().as(LengthUnit.Meter, _target!, target) > 5;
    if (targetChanged) {
      _generation += 1;
      _target = target;
      _route = null;
      _lastEvaluated = null;
      _deviationSamples = 0;
      await _fetch(current, RouteRefreshReason.destinationChanged);
      return;
    }

    if (_route == null) {
      await _fetch(current, RouteRefreshReason.initial);
      return;
    }

    final previous = _lastEvaluated;
    if (previous != null &&
        const Distance().as(LengthUnit.Meter, previous, current) <
            minimumEvaluationMovementMeters) {
      return;
    }
    _lastEvaluated = current;

    final adaptiveThreshold = math.max(
      minimumDeviationMeters,
      accuracyMeters.isFinite ? accuracyMeters.clamp(0, 100) * 1.75 : 0,
    );
    final deviation = distanceFromPathMeters(current, _route!.points);
    if (deviation <= adaptiveThreshold) {
      if (_deviationSamples != 0) {
        _deviationSamples = 0;
        notifyListeners();
      }
      return;
    }

    _deviationSamples += 1;
    notifyListeners();
    if (_deviationSamples < requiredDeviationSamples) return;

    final clock = now ?? DateTime.now();
    final last = _lastRerouteAt;
    if (last != null && clock.difference(last) < rerouteCooldown) return;
    await _fetch(current, RouteRefreshReason.deviated, now: clock);
  }

  void reset() {
    _generation += 1;
    final changed =
        _route != null || _target != null || _deviationSamples != 0 || _loading;
    _route = null;
    _target = null;
    _lastEvaluated = null;
    _latestCurrent = null;
    _deviationSamples = 0;
    _loading = false;
    _fetchAgain = false;
    if (changed && !_disposed) notifyListeners();
  }

  Future<void> _fetch(
    LatLng current,
    RouteRefreshReason reason, {
    DateTime? now,
  }) async {
    final destination = _target;
    if (destination == null) return;
    if (_loading) {
      _fetchAgain = true;
      return;
    }

    final requestGeneration = _generation;
    _loading = true;
    notifyListeners();
    try {
      final result = await _service.routeDetails(
        RoadRouteRequest.fromPoints(current, destination),
      );
      if (_disposed ||
          requestGeneration != _generation ||
          result == null ||
          result.points.length < 2) {
        return;
      }
      _route = result;
      _lastEvaluated = current;
      _deviationSamples = 0;
      _lastRefreshReason = reason;
      if (reason == RouteRefreshReason.deviated) {
        _lastRerouteAt = now ?? DateTime.now();
      }
    } finally {
      if (!_disposed && requestGeneration == _generation) {
        _loading = false;
        notifyListeners();
      } else {
        _loading = false;
      }
      if (_fetchAgain && !_disposed) {
        _fetchAgain = false;
        final latest = _latestCurrent;
        if (latest != null && _target != null) {
          unawaited(_fetch(latest, RouteRefreshReason.destinationChanged));
        }
      }
    }
  }

  @visibleForTesting
  static double distanceFromPathMeters(LatLng point, List<LatLng> path) {
    if (path.isEmpty) return double.infinity;
    if (path.length == 1) {
      return const Distance().as(LengthUnit.Meter, point, path.single);
    }

    var shortest = double.infinity;
    for (var index = 0; index < path.length - 1; index += 1) {
      shortest = math.min(
        shortest,
        _distanceToSegmentMeters(point, path[index], path[index + 1]),
      );
    }
    return shortest;
  }

  static double _distanceToSegmentMeters(
    LatLng point,
    LatLng start,
    LatLng end,
  ) {
    const earthRadiusMeters = 6371008.8;
    final referenceLatitude =
        (point.latitude + start.latitude + end.latitude) / 3 * math.pi / 180;

    ({double x, double y}) project(LatLng value) {
      return (
        x:
            value.longitude *
            math.pi /
            180 *
            earthRadiusMeters *
            math.cos(referenceLatitude),
        y: value.latitude * math.pi / 180 * earthRadiusMeters,
      );
    }

    final projectedPoint = project(point);
    final projectedStart = project(start);
    final projectedEnd = project(end);
    final dx = projectedEnd.x - projectedStart.x;
    final dy = projectedEnd.y - projectedStart.y;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared == 0) {
      return math.sqrt(
        math.pow(projectedPoint.x - projectedStart.x, 2) +
            math.pow(projectedPoint.y - projectedStart.y, 2),
      );
    }
    final projection =
        ((projectedPoint.x - projectedStart.x) * dx +
            (projectedPoint.y - projectedStart.y) * dy) /
        lengthSquared;
    final t = projection.clamp(0.0, 1.0);
    final nearestX = projectedStart.x + t * dx;
    final nearestY = projectedStart.y + t * dy;
    return math.sqrt(
      math.pow(projectedPoint.x - nearestX, 2) +
          math.pow(projectedPoint.y - nearestY, 2),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    super.dispose();
  }
}
