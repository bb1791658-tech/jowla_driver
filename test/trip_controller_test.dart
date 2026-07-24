import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jowla_driver/core/providers.dart';
import 'package:jowla_driver/core/services/realtime_service.dart';
import 'package:jowla_driver/core/storage/session_store.dart';
import 'package:jowla_driver/features/rides/data/backend_ride_repository.dart';
import 'package:jowla_driver/features/rides/domain/models/ride.dart';
import 'package:jowla_driver/features/trip/application/trip_controller.dart';

import 'support/fakes.dart';

void main() {
  late FakeRealtimeService realtime;
  late FakeRideRepository rides;
  late SessionStore store;
  late ProviderContainer container;

  setUp(() {
    realtime = FakeRealtimeService();
    rides = FakeRideRepository();
    store = SessionStore(InMemorySecureStore());
    container = ProviderContainer(
      overrides: [
        realtimeServiceProvider.overrideWithValue(realtime),
        rideRepositoryProvider.overrideWithValue(rides),
        sessionStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(realtime.dispose);
  });

  test('يستعيد الرحلة النشطة من GET /rides/driver/current', () async {
    rides.current = sampleRide(status: RideStatus.tripStarted);
    final ride = await container.read(tripControllerProvider.future);
    expect(ride?.status, RideStatus.tripStarted);
    expect(ride?.rider?.name, 'راكب');
    expect((await store.readActiveRide())?.id, 'ride-1');
  });

  test('يستعيد الرحلة النشطة من التخزين المحلي ثم يزامن الخادم', () async {
    await store.saveActiveRide(sampleRide(status: RideStatus.tripStarted));
    rides.current = sampleRide(status: RideStatus.driverArrived);

    final ride = await container.read(tripControllerProvider.future);
    expect(ride?.status, RideStatus.tripStarted);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(tripControllerProvider).value?.status,
      RideStatus.driverArrived,
    );
  });

  test('التسلسل الكامل: وصول → بدء → إيقاف → استئناف → إنهاء', () async {
    rides.current = sampleRide(status: RideStatus.driverAccepted);
    rides.transitionBuilder = (rideId, status) {
      final base = sampleRide(id: rideId, status: status);
      if (status != RideStatus.completed) return base;
      return Ride.fromJson({
        'id': rideId,
        'status': 'COMPLETED',
        'pickupLat': 30.96,
        'pickupLng': 46.97,
        'dropoffLat': 30.97,
        'dropoffLng': 46.99,
        'finalFare': '5500.00',
        'distanceKm': '3.250',
        'payment': {'amount': '5500.00', 'commissionAmount': '250.00'},
      });
    };
    await container.read(tripControllerProvider.future);
    final controller = container.read(tripControllerProvider.notifier);

    expect(await controller.markArrived(), isTrue);
    expect(
      container.read(tripControllerProvider).value?.status,
      RideStatus.driverArrived,
    );
    expect(await controller.startTrip(), isTrue);
    expect(await controller.pauseTrip(), isTrue);
    expect(
      container.read(tripControllerProvider).value?.status,
      RideStatus.tripPaused,
    );
    expect(rides.pauseCalls, 1);
    expect(await controller.resumeTrip(), isTrue);
    expect(
      container.read(tripControllerProvider).value?.status,
      RideStatus.tripStarted,
    );
    expect(rides.resumeCalls, 1);
    expect(await controller.completeTrip(), isTrue);
    final completed = container.read(tripControllerProvider).value;
    expect(completed?.status, RideStatus.completed);
    expect(completed?.payment?.netAmount, 5250);
    // بيانات الراكب من الرحلة السابقة تبقى بعد التحديث الخالي منها.
    expect(completed?.rider?.name, 'راكب');
  });

  test(
    'حدث Socket بحمولة كاملة يحدّث الحالة، وبحمولة مختصرة يطبقها فقط',
    () async {
      rides.current = sampleRide(status: RideStatus.driverAccepted);
      await container.read(tripControllerProvider.future);

      realtime.rideEventsController.add(
        RealtimeEvent('ride:status:changed', {
          'rideId': 'ride-1',
          'status': 'CANCELLED',
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(tripControllerProvider).value?.status,
        RideStatus.cancelled,
      );
    },
  );

  test('يتجاهل أحداث رحلة أخرى', () async {
    rides.current = sampleRide(status: RideStatus.tripStarted);
    await container.read(tripControllerProvider.future);
    realtime.rideEventsController.add(
      RealtimeEvent('ride:cancelled', {
        'rideId': 'ride-999',
        'status': 'CANCELLED',
      }),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(tripControllerProvider).value?.status,
      RideStatus.tripStarted,
    );
  });

  test('إعادة الاتصال تعيد المزامنة من الخادم', () async {
    rides.current = sampleRide(status: RideStatus.driverAccepted);
    await container.read(tripControllerProvider.future);
    rides.current = sampleRide(status: RideStatus.driverArrived);
    realtime.connectionsController.add(null);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(tripControllerProvider).value?.status,
      RideStatus.driverArrived,
    );
  });

  test('بدء الرحلة يزامن الخادم ولا يكرر الطلب إذا كانت بدأت فعلاً', () async {
    rides.current = sampleRide(status: RideStatus.driverArrived);
    await container.read(tripControllerProvider.future);
    rides.current = sampleRide(status: RideStatus.tripStarted);

    final controller = container.read(tripControllerProvider.notifier);
    expect(await controller.startTrip(), isTrue);

    expect(rides.startCalls, 0);
    expect(
      container.read(tripControllerProvider).value?.status,
      RideStatus.tripStarted,
    );
  });

  test('إتمام الرحلة يزامن الحالة القديمة قبل إرسال طلب الإنهاء', () async {
    rides.current = sampleRide(status: RideStatus.driverArrived);
    await container.read(tripControllerProvider.future);
    rides.current = sampleRide(status: RideStatus.tripStarted);

    final controller = container.read(tripControllerProvider.notifier);
    expect(await controller.completeTrip(), isTrue);

    expect(rides.completeCalls, 1);
    expect(
      container.read(tripControllerProvider).value?.status,
      RideStatus.completed,
    );
  });

  test('فشل الانتقال يعرض الخطأ ويبقي حالة الرحلة السابقة', () async {
    rides.current = sampleRide(status: RideStatus.driverAccepted);
    await container.read(tripControllerProvider.future);
    rides.transitionBuilder = (_, _) => throw StateError('boom');
    final controller = container.read(tripControllerProvider.notifier);
    expect(await controller.markArrived(), isFalse);
    final state = container.read(tripControllerProvider);
    expect(state.hasError, isTrue);
    expect(state.value?.status, RideStatus.driverAccepted);
  });

  test('لا يبدأ التوجه في رحلة مجدولة قبل سماح Backend', () async {
    rides.current = Ride.fromJson({
      'id': 'ride-1',
      'status': 'DRIVER_ASSIGNED',
      'pickupLat': 30.96,
      'pickupLng': 46.97,
      'dropoffLat': 33.31,
      'dropoffLng': 44.36,
      'serviceTypeCode': 'intercity_full_vehicle',
      'scheduledAt': '2030-01-02T08:00:00Z',
      'canStart': false,
    });
    await container.read(tripControllerProvider.future);
    final result = await container
        .read(tripControllerProvider.notifier)
        .markArrived();
    expect(result, isFalse);
    expect(rides.arrivedCalls, 0);
  });
}
