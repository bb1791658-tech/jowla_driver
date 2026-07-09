import 'package:latlong2/latlong.dart';

/// حالات الرحلة كما في prisma RideStatus حصرًا — لا توجد حالات
/// Paused/Resumed أو Heading-To-Pickup مستقلة في Backend
/// (القبول DRIVER_ACCEPTED يعني أن السائق متجه إلى نقطة الانطلاق).
enum RideStatus {
  pending,
  searchingDriver,
  driverAccepted,
  driverArrived,
  tripStarted,
  completed,
  cancelled,
  noDriverFound,
}

RideStatus? rideStatusFromBackend(String? value) {
  return switch (value?.trim().toUpperCase()) {
    'PENDING' => RideStatus.pending,
    'SEARCHING_DRIVER' => RideStatus.searchingDriver,
    'DRIVER_ACCEPTED' => RideStatus.driverAccepted,
    'DRIVER_ARRIVED' => RideStatus.driverArrived,
    'TRIP_STARTED' => RideStatus.tripStarted,
    'COMPLETED' => RideStatus.completed,
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
      this == RideStatus.tripStarted;
}

double? asDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

class RiderInfo {
  const RiderInfo({required this.id, this.name, this.phone});

  factory RiderInfo.fromJson(Map<String, dynamic> json) => RiderInfo(
    id: json['id']?.toString() ?? '',
    name: _nonEmpty(json['name']),
    phone: _nonEmpty(json['phone']),
  );

  final String id;
  final String? name;
  final String? phone;

  String get displayName => name ?? 'راكب جولة';

  Map<String, dynamic> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    if (phone != null) 'phone': phone,
  };

  static String? _nonEmpty(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
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
    final userJson = json['user'];
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
      rider: userJson is Map
          ? RiderInfo.fromJson(Map<String, dynamic>.from(userJson))
          : null,
      payment: paymentJson is Map
          ? RidePayment.fromJson(Map<String, dynamic>.from(paymentJson))
          : null,
      requestedAt: DateTime.tryParse(json['requestedAt']?.toString() ?? ''),
      completedAt: DateTime.tryParse(json['completedAt']?.toString() ?? ''),
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
  };

  static String? _nonEmpty(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
