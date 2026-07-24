import 'package:flutter_test/flutter_test.dart';
import 'package:jowla_driver/features/auth/domain/models/driver_session.dart';
import 'package:jowla_driver/features/driver/domain/models/driver_account.dart';

void main() {
  test('حالات السائق تطابق prisma DriverStatus حصرًا', () {
    expect(
      driverStatusFromBackend('PENDING_APPROVAL'),
      DriverAccountStatus.pendingApproval,
    );
    expect(driverStatusFromBackend('APPROVED'), DriverAccountStatus.approved);
    expect(driverStatusFromBackend('REJECTED'), DriverAccountStatus.rejected);
    expect(driverStatusFromBackend('ONLINE'), DriverAccountStatus.online);
    expect(driverStatusFromBackend('OFFLINE'), DriverAccountStatus.offline);
    expect(driverStatusFromBackend('BUSY'), DriverAccountStatus.busy);
    expect(driverStatusFromBackend('ON_TRIP'), DriverAccountStatus.onTrip);
    expect(driverStatusFromBackend('SUSPENDED'), DriverAccountStatus.suspended);
    expect(driverStatusFromBackend('SOMETHING'), isNull);
  });

  test('canWork يطابق منع socket-auth.service للسائق غير المعتمد', () {
    expect(DriverAccountStatus.pendingApproval.canWork, isFalse);
    expect(DriverAccountStatus.rejected.canWork, isFalse);
    expect(DriverAccountStatus.suspended.canWork, isFalse);
    expect(DriverAccountStatus.approved.canWork, isTrue);
    expect(DriverAccountStatus.online.canWork, isTrue);
  });

  test('DriverAccount يفك استجابة GET /drivers/me', () {
    final account = DriverAccount.fromJson({
      'id': 'driver-1',
      'name': 'سائق تجريبي',
      'phone': '+9647700000001',
      'status': 'APPROVED',
      'photoUrl': 'https://example.com/driver.jpg',
      'vehicles': [
        {
          'plateNumber': 'بغداد 12345',
          'model': 'تويوتا كورولا',
          'year': 2022,
          'color': 'أبيض',
          'isActive': true,
        },
      ],
      'services': [
        {
          'isActive': true,
          'serviceType': {'code': 'taxi', 'nameAr': 'داخل المدينة'},
        },
        {
          'isActive': true,
          'serviceType': {'code': 'intercity', 'nameAr': 'بين المحافظات'},
        },
      ],
      'activeServiceType': {'code': 'intercity', 'nameAr': 'بين المحافظات'},
      'user': {'id': 'u1', 'phone': '+9647700000001'},
    });
    expect(account.profile.id, 'driver-1');
    expect(account.profile.status, DriverAccountStatus.approved);
    expect(account.profile.photoUrl, 'https://example.com/driver.jpg');
    expect(account.activeVehicle?.plateNumber, 'بغداد 12345');
    expect(account.activeVehicle?.summary, contains('تويوتا'));
    expect(account.serviceNames, ['داخل المدينة', 'بين المحافظات']);
    expect(account.activeService?.code, 'intercity');
  });

  test('ملف السائق يُخزن ويُستعاد دون فقدان الحالة', () {
    const profile = DriverProfile(
      id: 'driver-1',
      name: 'سائق',
      phone: '+9647700000001',
      status: DriverAccountStatus.online,
      photoUrl: 'https://example.com/driver.jpg',
    );
    final restored = DriverProfile.fromJson(profile.toJson());
    expect(restored.id, profile.id);
    expect(restored.status, DriverAccountStatus.online);
    expect(restored.photoUrl, profile.photoUrl);
  });
}
