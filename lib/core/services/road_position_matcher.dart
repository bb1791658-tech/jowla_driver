import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'road_route_service.dart';

@immutable
class MatchedRoadPosition {
  const MatchedRoadPosition({
    required this.point,
    required this.headingDegrees,
    required this.isMatched,
    required this.confidence,
    required this.snapDistanceMeters,
  });

  final LatLng point;
  final double? headingDegrees;
  final bool isMatched;
  final double confidence;
  final double snapDistanceMeters;
}

/// يجمع نافذة GPS قصيرة ويرسلها إلى OSRM Match ثم يثبت العلامة على الطريق.
class RoadPositionMatcher {
  RoadPositionMatcher(this._service);

  final RoadRouteService _service;
  final List<RoadTracePoint> _trace = [];
  LatLng? _previousMatchedPoint;
  double? _previousHeading;

  Future<MatchedRoadPosition> match({
    required LatLng rawPoint,
    required DateTime recordedAt,
    required double accuracyMeters,
    double? rawHeadingDegrees,
  }) async {
    final accuracy = accuracyMeters.isFinite
        ? accuracyMeters.clamp(5, 100).toDouble()
        : 50.0;
    _appendTrace(
      RoadTracePoint(
        point: rawPoint,
        recordedAt: recordedAt,
        accuracyMeters: accuracy,
      ),
    );

    LatLng? matchedPoint;
    var confidence = 0.0;
    var snapDistance = 0.0;
    if (_trace.length == 1) {
      final nearest = await _service.nearest(
        rawPoint,
        maxDistanceMeters: math.max(35, accuracy * 2),
      );
      matchedPoint = nearest?.point;
      snapDistance = nearest?.distanceMeters ?? 0;
      confidence = nearest == null ? 0 : 0.5;
    } else {
      final result = await _service.matchTrace(
        _trace,
        maxSnapDistanceMeters: math.max(35, accuracy * 2),
      );
      matchedPoint = result?.point;
      snapDistance = result?.distanceMeters ?? 0;
      confidence = result?.confidence ?? 0;
    }

    if (matchedPoint == null) {
      return MatchedRoadPosition(
        point: rawPoint,
        headingDegrees: _normalizeHeading(rawHeadingDegrees),
        isMatched: false,
        confidence: 0,
        snapDistanceMeters: 0,
      );
    }

    final heading = _roadHeading(
      previous: _previousMatchedPoint,
      current: matchedPoint,
      fallback: rawHeadingDegrees,
    );
    _previousMatchedPoint = matchedPoint;
    _previousHeading = heading;
    return MatchedRoadPosition(
      point: matchedPoint,
      headingDegrees: heading,
      isMatched: true,
      confidence: confidence,
      snapDistanceMeters: snapDistance,
    );
  }

  void reset() {
    _trace.clear();
    _previousMatchedPoint = null;
    _previousHeading = null;
  }

  void _appendTrace(RoadTracePoint point) {
    if (_trace.isNotEmpty) {
      final last = _trace.last;
      final sameCoordinate =
          const Distance().as(LengthUnit.Meter, last.point, point.point) < 1;
      if (sameCoordinate &&
          point.recordedAt.difference(last.recordedAt).abs() <
              const Duration(seconds: 2)) {
        return;
      }
    }
    _trace.add(point);
    if (_trace.length > 8) _trace.removeAt(0);
  }

  double? _roadHeading({
    required LatLng? previous,
    required LatLng current,
    required double? fallback,
  }) {
    if (previous != null &&
        const Distance().as(LengthUnit.Meter, previous, current) >= 3) {
      return _normalizeHeading(const Distance().bearing(previous, current));
    }
    return _normalizeHeading(fallback) ?? _previousHeading;
  }

  static double? _normalizeHeading(double? value) {
    if (value == null || !value.isFinite || value < 0) return null;
    return (value % 360 + 360) % 360;
  }
}
