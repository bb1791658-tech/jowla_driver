import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:jowla_driver/core/providers.dart';
import 'package:jowla_driver/core/services/location_service.dart';
import 'package:jowla_driver/features/auth/application/auth_controller.dart';
import 'package:jowla_driver/features/auth/data/backend_auth_repository.dart';
import 'package:jowla_driver/features/auth/domain/models/driver_session.dart';
import 'package:jowla_driver/features/driver/data/backend_driver_repository.dart';
import 'package:jowla_driver/features/driver/domain/models/driver_account.dart';
import 'package:jowla_driver/features/home/application/driver_home_controller.dart';
import 'package:jowla_driver/features/rides/data/backend_ride_repository.dart';
import 'package:jowla_driver/features/rides/domain/models/ride.dart';
import 'package:jowla_driver/features/rides/domain/models/ride_offer.dart';
import 'package:jowla_driver/features/trip/application/trip_controller.dart';

import 'support/fakes.dart';

class _FakeLocationService extends LocationService {
  _FakeLocationService(this._positions);

  final Stream<Position> _positions;
  var permissionChecks = 0;

  @override
  Future<void> ensurePermission() async {
    permissionChecks++;
  }

  @override
  Stream<Position> positions() => _positions;
}

Position _position(double lat, double lng) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime.now(),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 90,
  headingAccuracy: 1,
  speed: 8,
  speedAccuracy: 1,
);

void main() {
  late FakeRealtimeService realtime;
  late FakeRideRepository rides;
  late FakeDriverRepository drivers;
  late FakeAuthRepository auth;
  late StreamController<Position> positions;
  late ProviderContainer container;

  const profile = DriverProfile(
    id: 'driver-1',
    name: 'سائق',
    phone: '+9647700000001',
    status: DriverAccountStatus.offline,
  );

  setUp(() {
    realtime = FakeRealtimeService();
    rides = FakeRideRepository();
    auth = FakeAuthRepository(driver: profile);
    drivers = FakeDriverRepository(
      account: const DriverAccount(profile: profile),
    );
    positions = StreamController<Position>.broadcast();
    container = ProviderContainer(
      overrides: [
        realtimeServiceProvider.overrideWithValue(realtime),
        rideRepositoryProvider.overrideWithValue(rides),
        driverRepositoryProvider.overrideWithValue(drivers),
        authRepositoryProvider.overrideWithValue(auth),
        locationServiceProvider.overrideWithValue(
          _FakeLocationService(positions.stream),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(realtime.dispose);
    addTearDown(positions.close);
  });

  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  Future<DriverHomeController> ready() async {
    await container.read(authSessionProvider.future);
    final controller = container.read(driverHomeControllerProvider.notifier);
    await settle();
    return controller;
  }

  test('Online: توفر ثم Socket ثم بث الموقع ثم استعادة العروض', () async {
    final controller = await ready();
    await controller.goOnline();
    await settle();

    expect(drivers.availabilityChanges, [true]);
    expect(realtime.connectCalls, 1);
    expect(container.read(driverHomeControllerProvider).isOnline, isTrue);
    expect(
      container.read(driverHomeControllerProvider).accountStatus,
      DriverAccountStatus.online,
    );

    positions.add(_position(30.96, 46.97));
    await settle();
    expect(realtime.sentLocations, hasLength(1));
    expect(realtime.sentLocations.single['lat'], 30.96);
    expect(realtime.sentLocations.single['heading'], 90);
  });

  test('Offline: لا يُرسل أي موقع بعد الفصل', () async {
    final controller = await ready();
    await controller.goOnline();
    await settle();
    positions.add(_position(30.96, 46.97));
    await settle();
    expect(realtime.sentLocations, hasLength(1));

    await controller.goOffline();
    await settle();
    expect(drivers.availabilityChanges, [true, false]);
    expect(container.read(driverHomeControllerProvider).isOnline, isFalse);

    positions.add(_position(31, 47));
    await settle();
    expect(realtime.sentLocations, hasLength(1));
  });

  test('عرض وارد عبر Socket يُعرض ويُقبل عبر REST ويُسند الرحلة', () async {
    final controller = await ready();
    await controller.goOnline();
    await settle();

    realtime.offersController.add({
      'rideId': 'ride-1',
      'offerId': 'offer-1',
      'expiresAt': DateTime.now()
          .add(const Duration(seconds: 30))
          .toIso8601String(),
      'pickup': {'lat': 30.96, 'lng': 46.97},
      'estimatedFare': 5000,
      'currency': 'IQD',
    });
    await settle();
    expect(
      container.read(driverHomeControllerProvider).activeOffer?.offerId,
      'offer-1',
    );

    final accepted = await controller.acceptOffer();
    expect(accepted, isTrue);
    expect(rides.accepted, ['offer-1']);
    expect(container.read(driverHomeControllerProvider).activeOffer, isNull);
    expect(
      container.read(tripControllerProvider).valueOrNull?.status,
      RideStatus.driverAccepted,
    );
  });

  test('ride:offer:expired بسبب قبول سائق آخر يزيل العرض برسالة', () async {
    final controller = await ready();
    await controller.goOnline();
    await settle();
    realtime.offersController.add({
      'rideId': 'ride-1',
      'offerId': 'offer-1',
      'expiresAt': DateTime.now()
          .add(const Duration(seconds: 30))
          .toIso8601String(),
    });
    await settle();
    realtime.expirationsController.add({
      'rideId': 'ride-1',
      'offerId': 'offer-1',
      'reason': 'accepted_by_other_driver',
    });
    await settle();
    final state = container.read(driverHomeControllerProvider);
    expect(state.activeOffer, isNull);
    expect(state.offerError, contains('سائق آخر'));
  });

  test('عدة عروض واردة يمكن التنقل بينها ورفض الحالي يعرض التالي', () async {
    final controller = await ready();
    await controller.goOnline();
    await settle();

    realtime.offersController.add({
      'rideId': 'ride-1',
      'offerId': 'offer-1',
      'expiresAt': DateTime.now()
          .add(const Duration(seconds: 30))
          .toIso8601String(),
      'pickup': {'lat': 30.96, 'lng': 46.97},
      'estimatedFare': 5000,
      'currency': 'IQD',
    });
    realtime.offersController.add({
      'rideId': 'ride-2',
      'offerId': 'offer-2',
      'expiresAt': DateTime.now()
          .add(const Duration(seconds: 30))
          .toIso8601String(),
      'pickup': {'lat': 30.97, 'lng': 46.98},
      'estimatedFare': 6000,
      'currency': 'IQD',
    });
    await settle();

    var state = container.read(driverHomeControllerProvider);
    expect(state.offerCount, 2);
    expect(state.offerPosition, 1);
    expect(state.activeOffer?.offerId, 'offer-1');

    controller.showNextOffer();
    state = container.read(driverHomeControllerProvider);
    expect(state.offerPosition, 2);
    expect(state.activeOffer?.offerId, 'offer-2');

    controller.showPreviousOffer();
    state = container.read(driverHomeControllerProvider);
    expect(state.offerPosition, 1);
    expect(state.activeOffer?.offerId, 'offer-1');

    await controller.rejectOffer();
    state = container.read(driverHomeControllerProvider);
    expect(rides.rejected, ['offer-1']);
    expect(state.offerCount, 1);
    expect(state.activeOffer?.offerId, 'offer-2');
  });

  test('انتهاء مهلة الـ30 ثانية محليًا يزيل العرض', () async {
    final controller = await ready();
    await controller.goOnline();
    await settle();
    realtime.offersController.add({
      'rideId': 'ride-1',
      'offerId': 'offer-1',
      'expiresAt': DateTime.now()
          .add(const Duration(seconds: 30))
          .toIso8601String(),
    });
    await settle();
    controller.offerTimedOut('offer-1');
    final state = container.read(driverHomeControllerProvider);
    expect(state.activeOffer, isNull);
    expect(state.offerError, contains('انتهت مهلة'));
  });

  test('إعادة الاتصال تعيد جلب العروض المعلقة من REST', () async {
    final controller = await ready();
    await controller.goOnline();
    await settle();
    rides.offers = [RideOfferFactory.pending('offer-7', 'ride-7')];
    realtime.connectionsController.add(null);
    await settle();
    await settle();
    expect(
      container.read(driverHomeControllerProvider).activeOffer?.offerId,
      'offer-7',
    );
  });

  test('الاستعادة عند الإقلاع: الخادم يقول ONLINE فيستأنف البث', () async {
    drivers.account = DriverAccount(
      profile: profile.copyWith(status: DriverAccountStatus.online),
    );
    final controller = await ready();
    expect(controller, isNotNull);
    await settle();
    expect(container.read(driverHomeControllerProvider).isOnline, isTrue);
    // استئناف دون PATCH availability إضافي — الخادم مصدر الحقيقة.
    expect(drivers.availabilityChanges, isEmpty);
    expect(realtime.connectCalls, 1);
  });
}

abstract final class RideOfferFactory {
  /// عنصر مطابق لاستجابة GET /rides/driver/offers.
  static RideOffer pending(String offerId, String rideId) =>
      RideOffer.fromRestOffer({
        'id': offerId,
        'rideId': rideId,
        'status': 'PENDING',
        'expiresAt': DateTime.now()
            .add(const Duration(seconds: 25))
            .toIso8601String(),
        'ride': {
          'id': rideId,
          'status': 'SEARCHING_DRIVER',
          'pickupLat': '30.1',
          'pickupLng': '46.1',
          'dropoffLat': '30.2',
          'dropoffLng': '46.2',
          'estimatedFare': '4000.00',
          'distanceKm': '2.000',
        },
      });
}
