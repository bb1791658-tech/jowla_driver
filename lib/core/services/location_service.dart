import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../config/app_config.dart';
import '../errors/app_exception.dart';

class LocationService {
  const LocationService();

  Future<void> ensurePermission() async {
    if (AppConfig.enableDevFixedLocation) return;

    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException('فعّل خدمة الموقع (GPS) للمتابعة.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException('صلاحية الموقع مطلوبة لاستقبال الرحلات.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        'إذن الموقع مرفوض دائمًا. فعّله من إعدادات الجهاز.',
      );
    }
  }

  Future<Position> getCurrentPosition() async {
    if (AppConfig.enableDevFixedLocation) return _devFixedPosition();

    await ensurePermission();
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } on TimeoutException {
      throw const LocationException(
        'استغرق تحديد الموقع وقتًا طويلًا. حاول مجددًا.',
      );
    }
  }

  Stream<Position> positions() {
    if (AppConfig.enableDevFixedLocation) {
      return _devFixedPositions();
    }

    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: AppConfig.locationDistanceFilterMeters,
      ),
    );
  }

  Stream<ServiceStatus> serviceStatus() {
    if (AppConfig.enableDevFixedLocation) {
      return const Stream<ServiceStatus>.empty();
    }

    return Geolocator.getServiceStatusStream();
  }

  Stream<Position> _devFixedPositions() async* {
    yield _devFixedPosition();
    await for (final _ in Stream<void>.periodic(AppConfig.locationHeartbeat)) {
      yield _devFixedPosition();
    }
  }

  Position _devFixedPosition() => Position(
    latitude: AppConfig.devFixedLatitude,
    longitude: AppConfig.devFixedLongitude,
    timestamp: DateTime.now().toUtc(),
    altitude: 0,
    altitudeAccuracy: 0,
    accuracy: 5,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}
