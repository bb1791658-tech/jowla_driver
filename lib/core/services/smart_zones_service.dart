import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../constants/api_paths.dart';
import '../providers.dart';

enum SmartZoneDemand { moderate, high, veryHigh }

enum SmartZoneKind {
  officialPickup,
  noPickup,
  danger,
  closure,
  demand,
  serviceArea,
  pricing,
}

@immutable
class SmartMapZone {
  const SmartMapZone({
    required this.id,
    required this.boundary,
    required this.kind,
    required this.demand,
    required this.validUntil,
  });

  final String id;
  final List<LatLng> boundary;
  final SmartZoneKind kind;
  final SmartZoneDemand demand;
  final DateTime validUntil;
}

final smartZonesServiceProvider = Provider<SmartZonesService>(
  (ref) => SmartZonesService(ref.watch(apiClientProvider).dio),
);

final smartMapZonesProvider = StreamProvider.autoDispose<List<SmartMapZone>>((
  ref,
) async* {
  final service = ref.watch(smartZonesServiceProvider);
  while (true) {
    yield await service.fetch();
    await Future<void>.delayed(const Duration(minutes: 3));
  }
});

class SmartZonesService {
  const SmartZonesService(this._dio);

  final Dio _dio;

  Future<List<SmartMapZone>> fetch() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        ApiPaths.smartMapZones,
      );
      final data = response.data ?? const {};
      final features = data['features'];
      if (features is! List) return const [];
      return features
          .map(_parseFeature)
          .whereType<SmartMapZone>()
          .where((zone) => zone.validUntil.isAfter(DateTime.now()))
          .toList(growable: false);
    } on DioException {
      // الخدمة اختيارية حتى يضيفها Backend؛ لا نعطل خريطة السائق عند غيابها.
      return const [];
    }
  }

  SmartMapZone? _parseFeature(Object? raw) {
    if (raw is! Map || raw['type'] != 'Feature') return null;
    final geometry = raw['geometry'];
    final properties = raw['properties'];
    if (geometry is! Map ||
        geometry['type'] != 'Polygon' ||
        properties is! Map) {
      return null;
    }
    final coordinates = geometry['coordinates'];
    if (coordinates is! List || coordinates.isEmpty) return null;
    final outerRing = coordinates.first;
    if (outerRing is! List) return null;
    final boundary = outerRing
        .map((coordinate) {
          if (coordinate is! List || coordinate.length < 2) return null;
          final lng = _double(coordinate[0]);
          final lat = _double(coordinate[1]);
          if (lat == null || lng == null) return null;
          return LatLng(lat, lng);
        })
        .whereType<LatLng>()
        .toList(growable: false);
    if (boundary.length < 4) return null;

    final id = properties['id']?.toString() ?? raw['id']?.toString();
    final validUntil = DateTime.tryParse(
      properties['validUntil']?.toString() ?? '',
    );
    if (id == null || id.isEmpty || validUntil == null) return null;
    final demand = switch (properties['demand']?.toString()) {
      'very_high' => SmartZoneDemand.veryHigh,
      'high' => SmartZoneDemand.high,
      _ => SmartZoneDemand.moderate,
    };
    final kind = switch (properties['kind']?.toString()) {
      'official_pickup' ||
      'airport_pickup' ||
      'university_gate' ||
      'hospital_gate' ||
      'complex_gate' => SmartZoneKind.officialPickup,
      'no_pickup' || 'no_stopping' => SmartZoneKind.noPickup,
      'danger' || 'unsafe' => SmartZoneKind.danger,
      'closure' || 'closed' => SmartZoneKind.closure,
      'service_area' || 'city_boundary' => SmartZoneKind.serviceArea,
      'pricing' || 'promotion' => SmartZoneKind.pricing,
      _ => SmartZoneKind.demand,
    };
    return SmartMapZone(
      id: id,
      boundary: boundary,
      kind: kind,
      demand: demand,
      validUntil: validUntil,
    );
  }

  double? _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
