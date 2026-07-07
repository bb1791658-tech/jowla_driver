import '../../../auth/domain/models/driver_session.dart';

class DriverVehicle {
  const DriverVehicle({
    required this.plateNumber,
    required this.model,
    this.year,
    this.color,
  });

  factory DriverVehicle.fromJson(Map<String, dynamic> json) => DriverVehicle(
        plateNumber: json['plateNumber']?.toString() ?? '',
        model: json['model']?.toString() ?? '',
        year: json['year'] is num
            ? (json['year'] as num).toInt()
            : int.tryParse('${json['year']}'),
        color: json['color']?.toString(),
      );

  final String plateNumber;
  final String model;
  final int? year;
  final String? color;

  String get summary => [
        model,
        if (year != null) '$year',
        if (color != null && color!.isNotEmpty) color!,
      ].join(' • ');
}

/// حساب السائق الكامل من GET /drivers/me
/// (drivers.service.ts: driver مع user وservices وvehicles النشطة).
class DriverAccount {
  const DriverAccount({
    required this.profile,
    this.vehicles = const [],
    this.serviceNames = const [],
  });

  factory DriverAccount.fromJson(Map<String, dynamic> json) {
    final vehiclesJson = json['vehicles'];
    final servicesJson = json['services'];
    return DriverAccount(
      profile: DriverProfile.fromJson(json),
      vehicles: vehiclesJson is List
          ? [
              for (final item in vehiclesJson)
                if (item is Map)
                  DriverVehicle.fromJson(Map<String, dynamic>.from(item)),
            ]
          : const [],
      serviceNames: servicesJson is List
          ? [
              for (final item in servicesJson)
                if (item is Map && item['serviceType'] is Map)
                  ((item['serviceType'] as Map)['nameAr']?.toString() ?? ''),
            ]
          : const [],
    );
  }

  final DriverProfile profile;
  final List<DriverVehicle> vehicles;
  final List<String> serviceNames;

  DriverVehicle? get activeVehicle => vehicles.isEmpty ? null : vehicles.first;
}
