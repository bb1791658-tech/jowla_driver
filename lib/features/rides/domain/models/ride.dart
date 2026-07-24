import 'package:latlong2/latlong.dart';

/// حالات الرحلة كما في prisma RideStatus حصرًا. تدعم الرحلة الإيقاف المؤقت
/// والاستئناف، بينما لا توجد حالة Heading-To-Pickup مستقلة؛ فالقبول
/// DRIVER_ACCEPTED يعني أن السائق متجه إلى نقطة الانطلاق.
enum RideStatus {
  pending,
  searchingDriver,
  driverAccepted,
  driverArrived,
  tripStarted,
  tripPaused,
  completed,
  cancelled,
  noDriverFound,
}

RideStatus? rideStatusFromBackend(String? value) {
  return switch (value?.trim().toUpperCase()) {
    'PENDING' || 'SEARCHING' => RideStatus.pending,
    'SEARCHING_DRIVER' => RideStatus.searchingDriver,
    'DRIVER_ACCEPTED' ||
    'DRIVER_ASSIGNED' ||
    'DRIVER_EN_ROUTE' => RideStatus.driverAccepted,
    'DRIVER_ARRIVED' => RideStatus.driverArrived,
    'TRIP_STARTED' => RideStatus.tripStarted,
    'TRIP_PAUSED' => RideStatus.tripPaused,
    'TRIP_COMPLETED' || 'COMPLETED' => RideStatus.completed,
    'CANCELLED' => RideStatus.cancelled,
    'NO_DRIVER_FOUND' => RideStatus.noDriverFound,
    _ => null,
  };
}

extension RideStatusLabel on RideStatus {
  String get backendValue => switch (this) {
    RideStatus.pending => 'PENDING',
    RideStatus.searchingDriver => 'SEARCHING_DRIVER',
    RideStatus.driverAccepted => 'DRIVER_ACCEPTED',
    RideStatus.driverArrived => 'DRIVER_ARRIVED',
    RideStatus.tripStarted => 'TRIP_STARTED',
    RideStatus.tripPaused => 'TRIP_PAUSED',
    RideStatus.completed => 'COMPLETED',
    RideStatus.cancelled => 'CANCELLED',
    RideStatus.noDriverFound => 'NO_DRIVER_FOUND',
  };

  String get arabicLabel => switch (this) {
    RideStatus.pending => 'بانتظار المعالجة',
    RideStatus.searchingDriver => 'جاري البحث عن سائق',
    RideStatus.driverAccepted => 'متجه إلى نقطة الانطلاق',
    RideStatus.driverArrived => 'وصلت إلى نقطة الانطلاق',
    RideStatus.tripStarted => 'الرحلة جارية',
    RideStatus.tripPaused => 'الرحلة متوقفة مؤقتًا',
    RideStatus.completed => 'اكتملت الرحلة',
    RideStatus.cancelled => 'أُلغيت الرحلة',
    RideStatus.noDriverFound => 'لم يتم العثور على سائق',
  };

  bool get isFinished =>
      this == RideStatus.completed ||
      this == RideStatus.cancelled ||
      this == RideStatus.noDriverFound;

  /// حالات تعتبر فيها الرحلة نشطة لدى السائق
  /// (نفس فلتر GET /rides/driver/current في rides.service.ts).
  bool get isActiveForDriver =>
      this == RideStatus.driverAccepted ||
      this == RideStatus.driverArrived ||
      this == RideStatus.tripStarted ||
      this == RideStatus.tripPaused;
}

double? asDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

class RiderInfo {
  const RiderInfo({required this.id, this.name, this.phone});

  factory RiderInfo.fromJson(Map<String, dynamic> json) {
    final profile = _asMap(json['profile']);
    final passengerProfile = _asMap(json['passengerProfile']);
    return RiderInfo(
      id:
          _firstNonEmpty([
            json['id'],
            json['userId'],
            json['riderId'],
            json['passengerId'],
          ]) ??
          '',
      name: _firstNonEmpty([
        json['name'],
        json['fullName'],
        json['displayName'],
        json['username'],
        json['nameAr'],
        json['full_name'],
        _joinedName(json['firstName'], json['lastName']),
        _joinedName(json['first_name'], json['last_name']),
        profile?['name'],
        profile?['fullName'],
        profile?['displayName'],
        _joinedName(profile?['firstName'], profile?['lastName']),
        passengerProfile?['name'],
        passengerProfile?['fullName'],
        passengerProfile?['displayName'],
        _joinedName(
          passengerProfile?['firstName'],
          passengerProfile?['lastName'],
        ),
      ]),
      phone: _firstNonEmpty([
        json['phone'],
        json['phoneNumber'],
        json['mobile'],
        json['phone_number'],
        profile?['phone'],
        profile?['phoneNumber'],
        passengerProfile?['phone'],
        passengerProfile?['phoneNumber'],
      ]),
    );
  }

  final String id;
  final String? name;
  final String? phone;

  String get displayName => name ?? 'راكب جولة';

  RiderInfo mergeMissing(RiderInfo? fallback) => RiderInfo(
    id: id.isNotEmpty ? id : fallback?.id ?? '',
    name: name ?? fallback?.name,
    phone: phone ?? fallback?.phone,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    if (phone != null) 'phone': phone,
  };

  static String? _nonEmpty(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String? _firstNonEmpty(List<Object?> values) {
    for (final value in values) {
      final text = _nonEmpty(value);
      if (text != null) return text;
    }
    return null;
  }

  static String? _joinedName(Object? firstName, Object? lastName) {
    final parts = [
      _nonEmpty(firstName),
      _nonEmpty(lastName),
    ].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(' ');
  }

  static Map<String, dynamic>? _asMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;
}

class RidePayment {
  const RidePayment({
    required this.amount,
    required this.commissionAmount,
    this.method,
    this.status,
  });

  factory RidePayment.fromJson(Map<String, dynamic> json) => RidePayment(
    amount: asDouble(json['amount']) ?? 0,
    commissionAmount: asDouble(json['commissionAmount']) ?? 0,
    method: json['method']?.toString(),
    status: json['status']?.toString(),
  );

  final double amount;
  final double commissionAmount;
  final String? method;
  final String? status;

  double get netAmount => amount - commissionAmount;

  Map<String, dynamic> toJson() => {
    'amount': amount,
    'commissionAmount': commissionAmount,
    if (method != null) 'method': method,
    if (status != null) 'status': status,
  };
}

class Ride {
  const Ride({
    required this.id,
    required this.status,
    required this.pickup,
    required this.dropoff,
    this.pickupAddress,
    this.dropoffAddress,
    this.estimatedFare,
    this.finalFare,
    this.distanceKm,
    this.durationMinutes,
    this.currency = 'IQD',
    this.rider,
    this.payment,
    this.requestedAt,
    this.completedAt,
    this.serviceTypeCode,
    this.quoteId,
    this.scheduledAt,
    this.canStart = true,
  });

  factory Ride.fromJson(Map<String, dynamic> json) {
    final status = rideStatusFromBackend(json['status']?.toString());
    final pickupLat = asDouble(json['pickupLat']);
    final pickupLng = asDouble(json['pickupLng']);
    final dropoffLat = asDouble(json['dropoffLat']);
    final dropoffLng = asDouble(json['dropoffLng']);
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty ||
        status == null ||
        pickupLat == null ||
        pickupLng == null ||
        dropoffLat == null ||
        dropoffLng == null) {
      throw const FormatException('استجابة الرحلة غير مكتملة');
    }
    final riderJson = _firstMap([
      json['user'],
      json['rider'],
      json['passenger'],
      json['customer'],
      json['client'],
    ]);
    final paymentJson = json['payment'];
    return Ride(
      id: id,
      status: status,
      pickup: LatLng(pickupLat, pickupLng),
      dropoff: LatLng(dropoffLat, dropoffLng),
      pickupAddress: _nonEmpty(json['pickupAddress']),
      dropoffAddress: _nonEmpty(json['dropoffAddress']),
      estimatedFare: asDouble(json['estimatedFare']),
      finalFare: asDouble(json['finalFare']),
      distanceKm: asDouble(json['distanceKm']),
      durationMinutes: json['durationMinutes'] is num
          ? (json['durationMinutes'] as num).toInt()
          : int.tryParse('${json['durationMinutes']}'),
      currency: json['currency']?.toString() ?? 'IQD',
      rider: riderJson == null ? null : RiderInfo.fromJson(riderJson),
      payment: paymentJson is Map
          ? RidePayment.fromJson(Map<String, dynamic>.from(paymentJson))
          : null,
      requestedAt: DateTime.tryParse(json['requestedAt']?.toString() ?? ''),
      completedAt: DateTime.tryParse(json['completedAt']?.toString() ?? ''),
      serviceTypeCode:
          json['serviceTypeCode']?.toString() ??
          (json['serviceType'] is Map
              ? json['serviceType']['code']?.toString()
              : json['serviceType']?.toString()),
      quoteId: json['quoteId']?.toString(),
      scheduledAt: DateTime.tryParse(
        json['scheduledAt']?.toString() ?? '',
      )?.toLocal(),
      canStart: json['canStart'] != false,
    );
  }

  final String id;
  final RideStatus status;
  final LatLng pickup;
  final LatLng dropoff;
  final String? pickupAddress;
  final String? dropoffAddress;
  final double? estimatedFare;
  final double? finalFare;
  final double? distanceKm;
  final int? durationMinutes;
  final String currency;
  final RiderInfo? rider;
  final RidePayment? payment;
  final DateTime? requestedAt;
  final DateTime? completedAt;
  final String? serviceTypeCode;
  final String? quoteId;
  final DateTime? scheduledAt;
  final bool canStart;

  bool get isIntercityFullVehicle =>
      serviceTypeCode == 'intercity_full_vehicle' ||
      serviceTypeCode == 'intercity';

  bool get isScheduled => scheduledAt != null;

  Ride withMergedRider(RiderInfo? fallback) {
    final merged = rider?.mergeMissing(fallback) ?? fallback;
    return copyWith(rider: merged);
  }

  Ride copyWith({RideStatus? status, RidePayment? payment, RiderInfo? rider}) =>
      Ride(
        id: id,
        status: status ?? this.status,
        pickup: pickup,
        dropoff: dropoff,
        pickupAddress: pickupAddress,
        dropoffAddress: dropoffAddress,
        estimatedFare: estimatedFare,
        finalFare: finalFare,
        distanceKm: distanceKm,
        durationMinutes: durationMinutes,
        currency: currency,
        rider: rider ?? this.rider,
        payment: payment ?? this.payment,
        requestedAt: requestedAt,
        completedAt: completedAt,
        serviceTypeCode: serviceTypeCode,
        quoteId: quoteId,
        scheduledAt: scheduledAt,
        canStart: canStart,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status.backendValue,
    'pickupLat': pickup.latitude,
    'pickupLng': pickup.longitude,
    'dropoffLat': dropoff.latitude,
    'dropoffLng': dropoff.longitude,
    if (pickupAddress != null) 'pickupAddress': pickupAddress,
    if (dropoffAddress != null) 'dropoffAddress': dropoffAddress,
    if (estimatedFare != null) 'estimatedFare': estimatedFare,
    if (finalFare != null) 'finalFare': finalFare,
    if (distanceKm != null) 'distanceKm': distanceKm,
    if (durationMinutes != null) 'durationMinutes': durationMinutes,
    'currency': currency,
    if (rider != null) 'user': rider!.toJson(),
    if (payment != null) 'payment': payment!.toJson(),
    if (requestedAt != null) 'requestedAt': requestedAt!.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    if (serviceTypeCode != null) 'serviceTypeCode': serviceTypeCode,
    if (quoteId != null) 'quoteId': quoteId,
    if (scheduledAt != null)
      'scheduledAt': scheduledAt!.toUtc().toIso8601String(),
    'canStart': canStart,
  };

  static String? _nonEmpty(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static Map<String, dynamic>? _firstMap(List<Object?> values) {
    for (final value in values) {
      if (value is Map) return Map<String, dynamic>.from(value);
    }
    return null;
  }
}
