import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jowla_driver/core/providers.dart';
import 'package:jowla_driver/core/services/realtime_service.dart';
import 'package:jowla_driver/features/rides/data/backend_ride_repository.dart';
import 'package:jowla_driver/features/rides/domain/models/ride.dart';
import 'package:jowla_driver/features/trip/application/trip_controller.dart';

import 'support/fakes.dart';

void main() {
  late FakeRealtimeService realtime;
  late FakeRideRepository rides;
  late ProviderContainer container;

  setUp(() {
    realtime = FakeRealtimeService();
    rides = FakeRideRepository();
    container = ProviderContainer(
      overrides: [
        realtimeServiceProvider.overrideWithValue(realtime),
        rideRepositoryProvider.overrideWithValue(rides),
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
  });

  test('التسلسل الكامل: وصول → بدء → إنهاء مع العمولة والصافي', () async {
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

  test('فشل الانتقال يعرض الخطأ ويبقي حالة الرحلة السابقة', () async {
    rides.current = sampleRide(status: RideStatus.driverAccepted);
    await container.read(tripControllerProvider.future);
    rides.transitionBuilder = (_, _) => throw StateError('boom');
    final controller = container.read(tripControllerProvider.notifier);
    expect(await controller.markArrived(), isFalse);
    final state = container.read(tripControllerProvider);
    expect(state.hasError, isTrue);
    expect(state.valueOrNull?.status, RideStatus.driverAccepted);
  });
}
