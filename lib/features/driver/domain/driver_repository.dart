import 'models/driver_account.dart';

abstract interface class DriverRepository {
  /// GET /drivers/me.
  Future<DriverAccount> me();

  /// PATCH /drivers/{id}/availability بالقيم online | offline | busy
  /// (UpdateDriverAvailabilityDto بأحرف صغيرة).
  Future<DriverAccount> setAvailability({
    required String driverId,
    required bool online,
  });

  /// PUT /drivers/{id}/location — مسار REST البديل لإرسال الموقع
  /// (القناة الأساسية هي حدث Socket driver:location:update).
  Future<void> updateLocation({
    required String driverId,
    required double lat,
    required double lng,
    double? heading,
    double? speed,
  });
}
