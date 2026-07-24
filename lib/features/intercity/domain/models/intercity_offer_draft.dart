import 'package:latlong2/latlong.dart';

import 'iraqi_governorate.dart';

class IntercityOfferDraft {
  const IntercityOfferDraft({
    required this.originGovernorate,
    required this.destinationGovernorate,
    required this.pickup,
    required this.dropoff,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.departureAt,
    required this.totalSeats,
    required this.pricePerSeatDinars,
  });

  final IraqiGovernorate originGovernorate;
  final IraqiGovernorate destinationGovernorate;
  final LatLng pickup;
  final LatLng dropoff;
  final String pickupAddress;
  final String dropoffAddress;
  final DateTime departureAt;
  final int totalSeats;
  final int pricePerSeatDinars;

  String? validate({
    int? vehicleCapacity,
    int? minimumPriceDinars,
    int? maximumPriceDinars,
    DateTime? now,
  }) {
    if (originGovernorate == destinationGovernorate) {
      return 'يجب أن تختلف محافظة الانطلاق عن محافظة الوصول.';
    }
    if (!departureAt.isAfter(now ?? DateTime.now())) {
      return 'يجب اختيار موعد مغادرة في المستقبل.';
    }
    if (totalSeats < 1) {
      return 'يجب أن يكون عدد المقاعد واحدًا على الأقل.';
    }
    return null;
  }

  Map<String, dynamic> toJson({String? previewId}) {
    final json = <String, dynamic>{
      'originGovernorate': originGovernorate.code,
      'destinationGovernorate': destinationGovernorate.code,
      'pickup': {
        'lat': pickup.latitude,
        'lng': pickup.longitude,
        'address': pickupAddress,
      },
      'pickupLat': pickup.latitude,
      'pickupLng': pickup.longitude,
      'dropoff': {
        'lat': dropoff.latitude,
        'lng': dropoff.longitude,
        'address': dropoffAddress,
      },
      'dropoffLat': dropoff.latitude,
      'dropoffLng': dropoff.longitude,
      'departureAt': departureAt.toUtc().toIso8601String(),
      'totalSeats': totalSeats,
      'pricePerSeatDinars': pricePerSeatDinars,
    };
    if (previewId != null) json['previewId'] = previewId;
    return json;
  }
}

class IntercityOfferPreview {
  const IntercityOfferPreview({
    required this.id,
    required this.expiresAt,
    required this.minimumPriceDinars,
    required this.maximumPriceDinars,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.cancellationPolicy,
    this.expectedGrossDinars,
  });

  factory IntercityOfferPreview.fromJson(Map<String, dynamic> source) {
    final value = source['data'] ?? source['preview'];
    final json = value is Map ? Map<String, dynamic>.from(value) : source;
    final id = (json['id'] ?? json['previewId'])?.toString() ?? '';
    final expiresAt = DateTime.tryParse(json['expiresAt']?.toString() ?? '');
    if (id.isEmpty || expiresAt == null) {
      throw const FormatException('استجابة معاينة العرض غير مكتملة');
    }
    return IntercityOfferPreview(
      id: id,
      expiresAt: expiresAt.toLocal(),
      minimumPriceDinars: _int(json['minimumPriceDinars'] ?? json['minPrice']),
      maximumPriceDinars: _int(json['maximumPriceDinars'] ?? json['maxPrice']),
      distanceMeters: _double(json['distanceMeters']),
      durationSeconds: _double(json['durationSeconds']),
      cancellationPolicy:
          json['cancellationPolicy']?.toString() ?? 'تطبق سياسة الخادم.',
      expectedGrossDinars: _nullableInt(json['expectedGrossDinars']),
    );
  }

  final String id;
  final DateTime expiresAt;
  final int minimumPriceDinars;
  final int maximumPriceDinars;
  final double distanceMeters;
  final double durationSeconds;
  final String cancellationPolicy;
  final int? expectedGrossDinars;

  bool get isExpired => !expiresAt.isAfter(DateTime.now());
}

int _int(Object? value) => _nullableInt(value) ?? 0;
int? _nullableInt(Object? value) =>
    value is num ? value.round() : int.tryParse('$value');
double _double(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
