import 'package:flutter_test/flutter_test.dart';
import 'package:jowla_driver/core/storage/session_store.dart';
import 'package:jowla_driver/features/auth/domain/models/driver_session.dart';
import 'package:jowla_driver/features/rides/domain/models/ride.dart';

import 'support/fakes.dart';

void main() {
  test('حفظ الجلسة واستعادتها ومسحها', () async {
    final store = SessionStore(InMemorySecureStore());
    expect(await store.readSession(), isNull);

    const session = DriverSession(
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
      driver: DriverProfile(
        id: 'driver-1',
        name: 'سائق',
        phone: '+9647700000001',
        status: DriverAccountStatus.approved,
      ),
    );
    await store.saveSession(session);

    final restored = await store.readSession();
    expect(restored?.driver.id, 'driver-1');
    expect(await store.readAccessToken(), 'access-1');

    await store.updateTokens(
      accessToken: 'access-2',
      refreshToken: 'refresh-2',
    );
    expect(await store.readAccessToken(), 'access-2');
    expect(await store.readRefreshToken(), 'refresh-2');

    await store.clearSession();
    expect(await store.readSession(), isNull);
  });

  test(
    'deviceKey ثابت ولا يُمسح مع الجلسة (شرط uq userId+deviceKey)',
    () async {
      final store = SessionStore(InMemorySecureStore());
      final first = await store.getOrCreateInstallationId();
      expect(first.length, greaterThanOrEqualTo(8));
      await store.clearSession();
      final second = await store.getOrCreateInstallationId();
      expect(second, first);
    },
  );

  test('يحفظ الرحلة النشطة فقط ويمسحها مع الجلسة', () async {
    final store = SessionStore(InMemorySecureStore());
    final ride = sampleRide(status: RideStatus.tripStarted);

    await store.saveActiveRide(ride);
    expect((await store.readActiveRide())?.id, ride.id);

    await store.saveActiveRide(ride.copyWith(status: RideStatus.completed));
    expect(await store.readActiveRide(), isNull);

    await store.saveActiveRide(ride);
    await store.clearSession();
    expect(await store.readActiveRide(), isNull);
  });
}
