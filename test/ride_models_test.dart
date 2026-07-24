import 'package:flutter_test/flutter_test.dart';
import 'package:jowla_driver/features/rides/domain/models/ride.dart';
import 'package:jowla_driver/features/rides/domain/models/ride_offer.dart';

void main() {
  group('RideStatus', () {
    test('يقبل حالات Backend العامة وأسماء الدورة الموحدة', () {
      expect(rideStatusFromBackend('PENDING'), RideStatus.pending);
      expect(
        rideStatusFromBackend('SEARCHING_DRIVER'),
        RideStatus.searchingDriver,
      );
      expect(
        rideStatusFromBackend('DRIVER_ACCEPTED'),
        RideStatus.driverAccepted,
      );
      expect(rideStatusFromBackend('DRIVER_ARRIVED'), RideStatus.driverArrived);
      expect(rideStatusFromBackend('TRIP_STARTED'), RideStatus.tripStarted);
      expect(rideStatusFromBackend('COMPLETED'), RideStatus.completed);
      expect(rideStatusFromBackend('CANCELLED'), RideStatus.cancelled);
      expect(
        rideStatusFromBackend('NO_DRIVER_FOUND'),
        RideStatus.noDriverFound,
      );
      expect(rideStatusFromBackend('TRIP_PAUSED'), RideStatus.tripPaused);
      expect(rideStatusFromBackend(''), isNull);
    });

    test('الرحلة النشطة للسائق تطابق فلتر /rides/driver/current', () {
      expect(RideStatus.driverAccepted.isActiveForDriver, isTrue);
      expect(RideStatus.driverArrived.isActiveForDriver, isTrue);
      expect(RideStatus.tripStarted.isActiveForDriver, isTrue);
      expect(RideStatus.tripPaused.isActiveForDriver, isTrue);
      expect(RideStatus.completed.isActiveForDriver, isFalse);
      expect(RideStatus.searchingDriver.isActiveForDriver, isFalse);
    });
  });

  group('Ride.fromJson', () {
    test('يفك أرقام Prisma Decimal المرسلة كنصوص', () {
      final ride = Ride.fromJson({
        'id': 'ride-1',
        'status': 'TRIP_STARTED',
        'pickupLat': '30.9601000',
        'pickupLng': '46.9769000',
        'dropoffLat': 30.97,
        'dropoffLng': 46.99,
        'estimatedFare': '5250.00',
        'finalFare': '5500.00',
        'distanceKm': '4.120',
        'durationMinutes': 12,
        'currency': 'IQD',
        'user': {'id': 'u1', 'name': 'راكب', 'phone': '+9647711111111'},
        'payment': {
          'amount': '5500.00',
          'commissionAmount': '500.00',
          'method': 'CASH',
          'status': 'PAID',
        },
      });
      expect(ride.status, RideStatus.tripStarted);
      expect(ride.pickup.latitude, closeTo(30.9601, 1e-6));
      expect(ride.estimatedFare, 5250);
      expect(ride.finalFare, 5500);
      expect(ride.distanceKm, closeTo(4.12, 1e-9));
      expect(ride.rider?.phone, '+9647711111111');
      expect(ride.payment?.commissionAmount, 500);
      expect(ride.payment?.netAmount, 5000);
    });

    test('يقرأ اسم الراكب الحقيقي من صيغ Backend البديلة', () {
      final ride = Ride.fromJson({
        'id': 'ride-1',
        'status': 'DRIVER_ACCEPTED',
        'pickupLat': 30.96,
        'pickupLng': 46.97,
        'dropoffLat': 30.97,
        'dropoffLng': 46.99,
        'user': {
          'id': 'u1',
          'firstName': 'أحمد',
          'lastName': 'علي',
          'phone': '+9647711111111',
        },
      });

      expect(ride.rider?.displayName, 'أحمد علي');
    });

    test('يقرأ بيانات الراكب من passenger وملف الراكب الداخلي', () {
      final ride = Ride.fromJson({
        'id': 'ride-1',
        'status': 'DRIVER_ACCEPTED',
        'pickupLat': 30.96,
        'pickupLng': 46.97,
        'dropoffLat': 30.97,
        'dropoffLng': 46.99,
        'passenger': {
          'passengerId': 'u1',
          'passengerProfile': {
            'fullName': 'محمد حسن',
            'phoneNumber': '+9647711111111',
          },
        },
      });

      expect(ride.rider?.displayName, 'محمد حسن');
      expect(ride.rider?.phone, '+9647711111111');
    });

    test('يرفض الاستجابة الناقصة', () {
      expect(
        () => Ride.fromJson({'id': 'x', 'status': 'TRIP_STARTED'}),
        throwsFormatException,
      );
      expect(
        () => Ride.fromJson({
          'id': 'x',
          'status': 'UNKNOWN_STATE',
          'pickupLat': 1,
          'pickupLng': 1,
          'dropoffLat': 2,
          'dropoffLng': 2,
        }),
        throwsFormatException,
      );
    });
  });

  group('RideOffer', () {
    test('يفك حمولة ride:offer:new كما يبثها rides.service.create', () {
      final expiresAt = DateTime.now()
          .add(const Duration(seconds: 30))
          .toIso8601String();
      final offer = RideOffer.fromSocketPayload({
        'rideId': 'ride-1',
        'offerId': 'offer-1',
        'expiresAt': expiresAt,
        'pickup': {'lat': 30.96, 'lng': 46.97},
        'estimatedFare': 4750,
        'currency': 'IQD',
      });
      expect(offer.rideId, 'ride-1');
      expect(offer.offerId, 'offer-1');
      expect(offer.pickup?.longitude, 46.97);
      expect(offer.estimatedFare, 4750);
      expect(offer.isExpired, isFalse);
      expect(offer.remaining.inSeconds, inInclusiveRange(28, 30));
    });

    test('العرض المنتهي زمنياً يُكتشف محلياً (مهلة الخادم 30 ثانية)', () {
      final offer = RideOffer.fromSocketPayload({
        'rideId': 'ride-1',
        'offerId': 'offer-1',
        'expiresAt': DateTime.now()
            .subtract(const Duration(seconds: 1))
            .toIso8601String(),
      });
      expect(offer.isExpired, isTrue);
      expect(offer.remaining, Duration.zero);
    });

    test('يفك عنصر GET /rides/driver/offers مع الرحلة المرفقة', () {
      final offer = RideOffer.fromRestOffer({
        'id': 'offer-9',
        'rideId': 'ride-9',
        'status': 'PENDING',
        'expiresAt': DateTime.now()
            .add(const Duration(seconds: 20))
            .toIso8601String(),
        'ride': {
          'id': 'ride-9',
          'status': 'SEARCHING_DRIVER',
          'pickupLat': '30.1',
          'pickupLng': '46.1',
          'dropoffLat': '30.2',
          'dropoffLng': '46.2',
          'estimatedFare': '6000.00',
          'distanceKm': '2.000',
        },
      });
      expect(offer.offerId, 'offer-9');
      expect(offer.ride?.status, RideStatus.searchingDriver);
      expect(offer.estimatedFare, 6000);
      expect(offer.pickup?.latitude, closeTo(30.1, 1e-9));
    });

    test('يرفض الحمولة الناقصة', () {
      expect(
        () => RideOffer.fromSocketPayload({'rideId': 'r'}),
        throwsFormatException,
      );
    });
  });
}
