import 'package:latlong2/latlong.dart';

import 'ride.dart';

/// عرض رحلة موجه للسائق.
///
/// المصدران الحقيقيان في Backend:
/// 1. حدث Socket ride:offer:new بالحمولة
///    {rideId, offerId, expiresAt, pickup: {lat, lng}, estimatedFare, currency}
///    (rides.service.ts → gateway.emitRideOffer).
/// 2. GET /rides/driver/offers ويرجع RideDriverOffer مع الرحلة كاملة.
class RideOffer {
  const RideOffer({
    required this.rideId,
    required this.offerId,
    required this.expiresAt,
    this.pickup,
    this.estimatedFare,
    this.currency = 'IQD',
    this.ride,
  });

  factory RideOffer.fromSocketPayload(Map<String, dynamic> json) {
    final rideId = json['rideId']?.toString() ?? '';
    final offerId = json['offerId']?.toString() ?? '';
    final expiresAt = DateTime.tryParse(json['expiresAt']?.toString() ?? '');
    if (rideId.isEmpty || offerId.isEmpty || expiresAt == null) {
      throw const FormatException('حمولة عرض الرحلة غير مكتملة');
    }
    final pickupJson = json['pickup'];
    LatLng? pickup;
    if (pickupJson is Map) {
      final lat = asDouble(pickupJson['lat']);
      final lng = asDouble(pickupJson['lng']);
      if (lat != null && lng != null) pickup = LatLng(lat, lng);
    }
    return RideOffer(
      rideId: rideId,
      offerId: offerId,
      expiresAt: expiresAt,
      pickup: pickup,
      estimatedFare: asDouble(json['estimatedFare']),
      currency: json['currency']?.toString() ?? 'IQD',
    );
  }

  /// من عنصر GET /rides/driver/offers:
  /// {id, rideId, driverId, status, expiresAt, ..., ride: {...}}.
  factory RideOffer.fromRestOffer(Map<String, dynamic> json) {
    final offerId = json['id']?.toString() ?? '';
    final rideId = json['rideId']?.toString() ?? '';
    final expiresAt = DateTime.tryParse(json['expiresAt']?.toString() ?? '');
    if (rideId.isEmpty || offerId.isEmpty || expiresAt == null) {
      throw const FormatException('استجابة عرض الرحلة غير مكتملة');
    }
    final rideJson = json['ride'];
    final ride = rideJson is Map
        ? Ride.fromJson(Map<String, dynamic>.from(rideJson))
        : null;
    return RideOffer(
      rideId: rideId,
      offerId: offerId,
      expiresAt: expiresAt,
      pickup: ride?.pickup,
      estimatedFare: ride?.estimatedFare,
      currency: ride?.currency ?? 'IQD',
      ride: ride,
    );
  }

  final String rideId;
  final String offerId;
  final DateTime expiresAt;
  final LatLng? pickup;
  final double? estimatedFare;
  final String currency;
  final Ride? ride;

  bool get isExpired => !expiresAt.isAfter(DateTime.now());

  Duration get remaining {
    final left = expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  RideOffer withRide(Ride ride) => RideOffer(
        rideId: rideId,
        offerId: offerId,
        expiresAt: expiresAt,
        pickup: pickup ?? ride.pickup,
        estimatedFare: estimatedFare ?? ride.estimatedFare,
        currency: currency,
        ride: ride,
      );
}
