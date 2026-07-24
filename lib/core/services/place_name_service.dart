import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';

class PlaceNameService {
  PlaceNameService({Dio? client})
    : _dio =
          client ??
          Dio(
            BaseOptions(
              baseUrl: AppConfig.geocodingBaseUrl,
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
  final _searchCache = <PlaceSearchRequest, _CachedPlaceSearch>{};

  Future<String?> nameFor(LatLng point) {
    final request = PlaceNameRequest.fromPoint(point);
    return _cache.putIfAbsent(request, () => _fetchName(request));
  }

  Future<List<PlaceSearchResult>> search(String query, {LatLng? near}) async {
    final normalized = query.trim();
    if (normalized.length < 2) return const [];
    final request = PlaceSearchRequest.from(normalized, near: near);
    final cached = _searchCache[request];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.results;
    }
    try {
      final response = await _dio.get<List<dynamic>>(
        '/search',
        queryParameters: {
          'format': 'jsonv2',
          'q': normalized,
          'countrycodes': 'iq',
          'viewbox': request.viewbox,
          'bounded': near == null ? 1 : 0,
          'limit': 8,
          'addressdetails': 1,
          'accept-language': 'ar',
        },
      );
      final results = (response.data ?? const [])
          .whereType<Map>()
          .map((item) => _searchResult(Map<String, dynamic>.from(item)))
          .whereType<PlaceSearchResult>()
          .toList();
      if (near != null) {
        results.sort((a, b) {
          final aScore = _nearbyScore(a, near);
          final bScore = _nearbyScore(b, near);
          return bScore.compareTo(aScore);
        });
      }
      final immutable = List<PlaceSearchResult>.unmodifiable(results);
      if (_searchCache.length >= 40) {
        _searchCache.remove(_searchCache.keys.first);
      }
      _searchCache[request] = _CachedPlaceSearch(
        results: immutable,
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      );
      return immutable;
    } on DioException {
      return const [];
    }
  }

  double _nearbyScore(PlaceSearchResult result, LatLng near) {
    final distanceKm = const Distance().as(
      LengthUnit.Kilometer,
      near,
      result.point,
    );
    return result.importance - (distanceKm / 300).clamp(0, 1) * 0.25;
  }

  PlaceSearchResult? _searchResult(Map<String, dynamic> json) {
    final lat = double.tryParse(json['lat']?.toString() ?? '');
    final lng = double.tryParse(json['lon']?.toString() ?? '');
    final name = _clean(json['display_name']);
    if (lat == null || lng == null || name == null) return null;
    final address = json['address'];
    final governorate = address is Map
        ? _clean(
            address['state'] ??
                address['province'] ??
                address['state_district'] ??
                address['county'],
          )
        : null;
    return PlaceSearchResult(
      point: LatLng(lat, lng),
      displayName: name,
      governorate: governorate,
      importance: double.tryParse(json['importance']?.toString() ?? '') ?? 0,
    );
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
class PlaceSearchResult {
  const PlaceSearchResult({
    required this.point,
    required this.displayName,
    this.governorate,
    this.importance = 0,
  });

  final LatLng point;
  final String displayName;
  final String? governorate;
  final double importance;
}

@immutable
class PlaceSearchRequest {
  const PlaceSearchRequest({
    required this.query,
    required this.nearLat,
    required this.nearLng,
  });

  factory PlaceSearchRequest.from(String query, {LatLng? near}) {
    double? rounded(double? value) =>
        value == null ? null : (value * 100).roundToDouble() / 100;
    return PlaceSearchRequest(
      query: query.trim().toLowerCase(),
      nearLat: rounded(near?.latitude),
      nearLng: rounded(near?.longitude),
    );
  }

  final String query;
  final double? nearLat;
  final double? nearLng;

  String get viewbox {
    final lat = nearLat;
    final lng = nearLng;
    if (lat == null || lng == null) {
      return '38.7936,37.3809,48.5759,29.0612';
    }
    return '${lng - 0.35},${lat + 0.25},${lng + 0.35},${lat - 0.25}';
  }

  @override
  bool operator ==(Object other) =>
      other is PlaceSearchRequest &&
      other.query == query &&
      other.nearLat == nearLat &&
      other.nearLng == nearLng;

  @override
  int get hashCode => Object.hash(query, nearLat, nearLng);
}

class _CachedPlaceSearch {
  const _CachedPlaceSearch({required this.results, required this.expiresAt});

  final List<PlaceSearchResult> results;
  final DateTime expiresAt;
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
