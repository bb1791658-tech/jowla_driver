import 'package:latlong2/latlong.dart';

import 'iraqi_governorate.dart';

enum IntercityOfferStatus { open, full, departed, cancelled, completed }

IntercityOfferStatus intercityOfferStatusFromBackend(Object? value) =>
    switch (value?.toString().trim().toLowerCase()) {
      'full' => IntercityOfferStatus.full,
      'departed' => IntercityOfferStatus.departed,
      'cancelled' || 'canceled' => IntercityOfferStatus.cancelled,
      'completed' => IntercityOfferStatus.completed,
      _ => IntercityOfferStatus.open,
    };

extension IntercityOfferStatusView on IntercityOfferStatus {
  String get backendValue => name;

  String get arabicLabel => switch (this) {
    IntercityOfferStatus.open => 'مفتوح للحجز',
    IntercityOfferStatus.full => 'ممتلئ',
    IntercityOfferStatus.departed => 'انطلقت الرحلة',
    IntercityOfferStatus.cancelled => 'ملغى',
    IntercityOfferStatus.completed => 'مكتمل',
  };

  bool get isPast =>
      this == IntercityOfferStatus.cancelled ||
      this == IntercityOfferStatus.completed;
}

class IntercityPassengerSummary {
  const IntercityPassengerSummary({
    required this.id,
    required this.displayName,
  });

  factory IntercityPassengerSummary.fromJson(Map<String, dynamic> json) =>
      IntercityPassengerSummary(
        id: _text(json['id'] ?? json['passengerId'] ?? json['userId']),
        displayName: _text(
          json['displayName'] ?? json['name'] ?? json['nameAr'],
          fallback: 'راكب جولة',
        ),
      );

  final String id;
  final String displayName;
}

class IntercitySeatBooking {
  const IntercitySeatBooking({
    required this.id,
    required this.seatCount,
    required this.totalPriceDinars,
    required this.paymentMethod,
    required this.status,
    this.passenger,
    this.cancelUntil,
  });

  factory IntercitySeatBooking.fromJson(Map<String, dynamic> json) {
    final passenger = _map(
      json['passenger'] ?? json['rider'] ?? json['passengerSummary'],
    );
    return IntercitySeatBooking(
      id: _text(json['id'] ?? json['bookingId']),
      seatCount: _integer(json['seatCount'] ?? json['seats']),
      totalPriceDinars: _integer(
        json['totalPriceDinars'] ?? json['totalPrice'] ?? json['amount'],
      ),
      paymentMethod: _text(json['paymentMethod'], fallback: 'cash'),
      status: _text(json['status'], fallback: 'confirmed'),
      passenger: passenger == null
          ? null
          : IntercityPassengerSummary.fromJson(passenger),
      cancelUntil: _date(json['cancelUntil'])?.toLocal(),
    );
  }

  final String id;
  final int seatCount;
  final int totalPriceDinars;
  final String paymentMethod;
  final String status;
  final IntercityPassengerSummary? passenger;
  final DateTime? cancelUntil;

  bool get isConfirmed => status.toLowerCase() == 'confirmed';
}

class IntercityTripOffer {
  const IntercityTripOffer({
    required this.id,
    required this.originGovernorate,
    required this.destinationGovernorate,
    required this.pickup,
    required this.dropoff,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.departureAt,
    required this.totalSeats,
    required this.availableSeats,
    required this.pricePerSeatDinars,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.status,
    required this.version,
    this.bookings = const [],
    this.routePoints = const [],
    this.cancelUntil,
    this.expectedGrossDinars,
    this.dueAmountDinars,
    this.cancellationPolicy,
    this.canEdit = false,
    this.canCancel = false,
    this.canDepart = false,
    this.canComplete = false,
  });

  factory IntercityTripOffer.fromJson(Map<String, dynamic> source) {
    final json = _unwrap(source);
    final pickup = _point(
      _map(json['pickup'] ?? json['originPoint']) ?? json,
      prefix: 'pickup',
    );
    final dropoff = _point(
      _map(json['dropoff'] ?? json['destinationPoint']) ?? json,
      prefix: 'dropoff',
    );
    final origin = IraqiGovernorate.fromCodeOrName(
      json['originGovernorate'] ?? json['originGovernorateCode'],
    );
    final destination = IraqiGovernorate.fromCodeOrName(
      json['destinationGovernorate'] ?? json['destinationGovernorateCode'],
    );
    final departureAt = _date(json['departureAt'] ?? json['scheduledAt']);
    final id = _text(json['id'] ?? json['offerId']);
    if (id.isEmpty ||
        pickup == null ||
        dropoff == null ||
        origin == null ||
        destination == null ||
        departureAt == null) {
      throw const FormatException('استجابة عرض بين المحافظات غير مكتملة');
    }
    final bookingValues = json['bookings'];
    return IntercityTripOffer(
      id: id,
      originGovernorate: origin,
      destinationGovernorate: destination,
      pickup: pickup,
      dropoff: dropoff,
      pickupAddress: _text(
        json['pickupAddress'] ?? _map(json['pickup'])?['address'],
        fallback: origin.arabicName,
      ),
      dropoffAddress: _text(
        json['dropoffAddress'] ?? _map(json['dropoff'])?['address'],
        fallback: destination.arabicName,
      ),
      departureAt: departureAt.toLocal(),
      totalSeats: _integer(json['totalSeats'] ?? json['seatCapacity']),
      availableSeats: _integer(
        json['availableSeats'] ?? json['remainingSeats'],
      ),
      pricePerSeatDinars: _integer(
        json['pricePerSeatDinars'] ?? json['pricePerSeat'],
      ),
      distanceMeters: _number(
        json['distanceMeters'] ?? json['routeDistanceMeters'],
      ),
      durationSeconds: _number(
        json['durationSeconds'] ?? json['routeDurationSeconds'],
      ),
      status: intercityOfferStatusFromBackend(json['status']),
      version: _integer(json['version'] ?? json['revision']),
      bookings: bookingValues is List
          ? [
              for (final item in bookingValues.whereType<Map>())
                IntercitySeatBooking.fromJson(Map<String, dynamic>.from(item)),
            ]
          : const [],
      routePoints: _routePoints(json['routePoints']),
      cancelUntil: _date(json['cancelUntil'])?.toLocal(),
      expectedGrossDinars: _nullableInteger(json['expectedGrossDinars']),
      dueAmountDinars: _nullableInteger(json['dueAmountDinars']),
      cancellationPolicy: _nullableText(json['cancellationPolicy']),
      canEdit: json['canEdit'] == true,
      canCancel: json['canCancel'] == true,
      canDepart: json['canDepart'] == true,
      canComplete: json['canComplete'] == true,
    );
  }

  final String id;
  final IraqiGovernorate originGovernorate;
  final IraqiGovernorate destinationGovernorate;
  final LatLng pickup;
  final LatLng dropoff;
  final String pickupAddress;
  final String dropoffAddress;
  final DateTime departureAt;
  final int totalSeats;
  final int availableSeats;
  final int pricePerSeatDinars;
  final double distanceMeters;
  final double durationSeconds;
  final IntercityOfferStatus status;
  final int version;
  final List<IntercitySeatBooking> bookings;
  final List<LatLng> routePoints;
  final DateTime? cancelUntil;
  final int? expectedGrossDinars;
  final int? dueAmountDinars;
  final String? cancellationPolicy;
  final bool canEdit;
  final bool canCancel;
  final bool canDepart;
  final bool canComplete;

  int get bookedSeats => totalSeats - availableSeats;
  int get confirmedBookingCount =>
      bookings.where((item) => item.isConfirmed).length;
}

Map<String, dynamic> _unwrap(Map<String, dynamic> json) {
  final value = json['data'] ?? json['offer'];
  return value is Map ? Map<String, dynamic>.from(value) : json;
}

Map<String, dynamic>? _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

String _text(Object? value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

String? _nullableText(Object? value) {
  final valueText = _text(value);
  return valueText.isEmpty ? null : valueText;
}

int _integer(Object? value) => _nullableInteger(value) ?? 0;
int? _nullableInteger(Object? value) =>
    value is num ? value.round() : int.tryParse('$value');
double _number(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
DateTime? _date(Object? value) =>
    value is DateTime ? value : DateTime.tryParse(value?.toString() ?? '');

LatLng? _point(Map<String, dynamic> json, {required String prefix}) {
  final coordinates = json['coordinates'];
  if (coordinates is List && coordinates.length >= 2) {
    final lng = _number(coordinates[0]);
    final lat = _number(coordinates[1]);
    return LatLng(lat, lng);
  }
  final lat = _number(json['lat'] ?? json['latitude'] ?? json['${prefix}Lat']);
  final lng = _number(json['lng'] ?? json['longitude'] ?? json['${prefix}Lng']);
  return lat == 0 && lng == 0 ? null : LatLng(lat, lng);
}

List<LatLng> _routePoints(Object? value) {
  if (value is! List) return const [];
  final points = <LatLng>[];
  for (final item in value) {
    if (item is List && item.length >= 2) {
      points.add(LatLng(_number(item[1]), _number(item[0])));
    } else if (item is Map) {
      final point = _point(Map<String, dynamic>.from(item), prefix: '');
      if (point != null) points.add(point);
    }
  }
  return points;
}
