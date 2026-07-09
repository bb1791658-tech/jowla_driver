import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

class PlaceNameService {
  PlaceNameService({Dio? client})
    : _dio =
          client ??
          Dio(
            BaseOptions(
              baseUrl: 'https://nominatim.openstreetmap.org',
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              headers: const {
                'Accept': 'application/json',
                'User-Agent': 'JowlaDriver/1.0 (com.jowla.driver)',
              },
            ),
          );

  static final instance = PlaceNameService();

  final Dio _dio;
  final _cache = <PlaceNameRequest, Future<String?>>{};

  Future<String?> nameFor(LatLng point) {
    final request = PlaceNameRequest.fromPoint(point);
    return _cache.putIfAbsent(request, () => _fetchName(request));
  }

  Future<String?> _fetchName(PlaceNameRequest request) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/reverse',
        queryParameters: {
          'format': 'jsonv2',
          'lat': request.lat.toStringAsFixed(6),
          'lon': request.lng.toStringAsFixed(6),
          'zoom': 18,
          'addressdetails': 1,
          'accept-language': 'ar',
        },
      );
      return _bestName(response.data ?? const {});
    } on DioException {
      return null;
    }
  }

  String? _bestName(Map<String, dynamic> data) {
    final address = data['address'];
    if (address is Map) {
      final parts = [
        address['road'],
        address['neighbourhood'],
        address['suburb'],
        address['city'] ?? address['town'] ?? address['village'],
      ].map(_clean).whereType<String>().toList();
      if (parts.isNotEmpty) return parts.take(3).join('، ');
    }
    return _clean(data['name']) ?? _clean(data['display_name']);
  }

  String? _clean(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

@immutable
class PlaceNameRequest {
  const PlaceNameRequest({required this.lat, required this.lng});

  factory PlaceNameRequest.fromPoint(LatLng point) {
    return PlaceNameRequest(
      lat: _round(point.latitude),
      lng: _round(point.longitude),
    );
  }

  final double lat;
  final double lng;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PlaceNameRequest && other.lat == lat && other.lng == lng;
  }

  @override
  int get hashCode => Object.hash(lat, lng);

  static double _round(double value) {
    const factor = 1000000.0;
    return (value * factor).roundToDouble() / factor;
  }
}
