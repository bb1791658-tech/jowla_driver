import '../../../auth/domain/models/driver_session.dart';

class DriverService {
  const DriverService({
    required this.code,
    required this.name,
    required this.isActive,
  });

  factory DriverService.fromJson(Map<String, dynamic> json) {
    final serviceType = json['serviceType'];
    final source = serviceType is Map ? serviceType : json;
    return DriverService(
      code: source['code']?.toString() ?? '',
      name:
          source['nameAr']?.toString() ??
          source['nameEn']?.toString() ??
          source['code']?.toString() ??
          '',
      isActive: json['isActive'] != false && source['isActive'] != false,
    );
  }

  final String code;
  final String name;
  final bool isActive;
}

class DriverVehicle {
  const DriverVehicle({
    required this.plateNumber,
    required this.model,
    this.year,
    this.color,
    this.seatCapacity,
    this.isActive = true,
  });

  factory DriverVehicle.fromJson(Map<String, dynamic> json) => DriverVehicle(
    plateNumber: json['plateNumber']?.toString() ?? '',
    model:
        json['model']?.toString() ??
        json['name']?.toString() ??
        json['vehicleName']?.toString() ??
        json['carName']?.toString() ??
        '',
    year: json['year'] is num
        ? (json['year'] as num).toInt()
        : int.tryParse('${json['year']}'),
    color: json['color']?.toString(),
    seatCapacity: _positiveInt(
      json['seatCapacity'] ?? json['passengerCapacity'] ?? json['seats'],
    ),
    isActive: json['isActive'] != false && json['status'] != 'inactive',
  );

  final String plateNumber;
  final String model;
  final int? year;
  final String? color;
  final int? seatCapacity;
  final bool isActive;

  String get summary => [
    model,
    if (year != null) '$year',
    if (color != null && color!.isNotEmpty) color!,
  ].join(' • ');

  static int? _positiveInt(Object? value) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    return parsed != null && parsed > 0 ? parsed : null;
  }
}

/// حساب السائق الكامل من GET /drivers/me
/// (drivers.service.ts: driver مع user وservices وvehicles النشطة).
class DriverAccount {
  const DriverAccount({
    required this.profile,
    this.vehicles = const [],
    this.services = const [],
    this.activeService,
  });

  factory DriverAccount.fromJson(Map<String, dynamic> json) {
    final vehiclesJson = json['vehicles'];
    final servicesJson = json['services'];
    final activeServiceJson = json['activeServiceType'];
    return DriverAccount(
      profile: DriverProfile.fromJson(json),
      vehicles: vehiclesJson is List
          ? [
              for (final item in vehiclesJson)
                if (item is Map)
                  DriverVehicle.fromJson(Map<String, dynamic>.from(item)),
            ]
          : const [],
      services: servicesJson is List
          ? [
              for (final item in servicesJson)
                if (item is Map)
                  DriverService.fromJson(Map<String, dynamic>.from(item)),
            ]
          : const [],
      activeService: activeServiceJson is Map
          ? DriverService.fromJson(Map<String, dynamic>.from(activeServiceJson))
          : null,
    );
  }

  final DriverProfile profile;
  final List<DriverVehicle> vehicles;
  final List<DriverService> services;
  final DriverService? activeService;

  DriverVehicle? get activeVehicle {
    for (final vehicle in vehicles) {
      if (vehicle.isActive) return vehicle;
    }
    return null;
  }

  List<String> get serviceNames =>
      services.map((service) => service.name).toList();
}
