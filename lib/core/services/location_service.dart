import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../config/app_config.dart';
import '../errors/app_exception.dart';

class LocationService {
  const LocationService();

  Future<void> ensurePermission() async {
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
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: AppConfig.locationDistanceFilterMeters,
      ),
    );
  }

  Stream<ServiceStatus> serviceStatus() {
    return Geolocator.getServiceStatusStream();
  }
}
