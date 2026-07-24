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

  /// PATCH /drivers/{id}/active-service — اختيار خدمة العمل النشطة من
  /// الخدمات التي اعتمدها الأدمن للسائق.
  Future<DriverAccount> chooseActiveService({
    required String driverId,
    required String serviceTypeCode,
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
