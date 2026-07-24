import 'package:flutter_test/flutter_test.dart';
import 'package:jowla_driver/features/intercity/domain/models/intercity_offer.dart';
import 'package:jowla_driver/features/intercity/domain/models/intercity_offer_draft.dart';
import 'package:jowla_driver/features/intercity/domain/models/iraqi_governorate.dart';
import 'package:jowla_driver/features/rides/domain/models/ride.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('IntercityOfferDraft', () {
    final future = DateTime(2030, 1, 2, 10);

    IntercityOfferDraft draft({
      IraqiGovernorate origin = IraqiGovernorate.dhiQar,
      IraqiGovernorate destination = IraqiGovernorate.baghdad,
      DateTime? departureAt,
      int seats = 3,
      int price = 25000,
    }) => IntercityOfferDraft(
      originGovernorate: origin,
      destinationGovernorate: destination,
      pickup: const LatLng(31.04, 46.26),
      dropoff: const LatLng(33.31, 44.36),
      pickupAddress: 'كراج الناصرية',
      dropoffAddress: 'كراج بغداد',
      departureAt: departureAt ?? future,
      totalSeats: seats,
      pricePerSeatDinars: price,
    );

    test('يقبل عرضًا صحيحًا ضمن سعة المركبة وحدود الخادم', () {
      expect(
        draft().validate(
          vehicleCapacity: 4,
          minimumPriceDinars: 20000,
          maximumPriceDinars: 30000,
          now: DateTime(2030, 1, 1),
        ),
        isNull,
      );
    });

    test('يرفض المحافظة نفسها والموعد القديم ويسمح بحرية المقاعد والسعر', () {
      expect(
        draft(
          destination: IraqiGovernorate.dhiQar,
        ).validate(vehicleCapacity: 4, now: DateTime(2030, 1, 1)),
        contains('تختلف'),
      );
      expect(
        draft(
          departureAt: DateTime(2029),
        ).validate(vehicleCapacity: 4, now: DateTime(2030, 1, 1)),
        contains('المستقبل'),
      );
      expect(
        draft(seats: 5).validate(vehicleCapacity: 4, now: DateTime(2030, 1, 1)),
        isNull,
      );
    });

    test('لا يفرض حدودًا محلية على السعر', () {
      expect(
        draft(price: 19000).validate(
          vehicleCapacity: 4,
          minimumPriceDinars: 20000,
          maximumPriceDinars: 30000,
          now: DateTime(2030, 1, 1),
        ),
        isNull,
      );
      expect(
        draft(price: 31000).validate(
          vehicleCapacity: 4,
          minimumPriceDinars: 20000,
          maximumPriceDinars: 30000,
          now: DateTime(2030, 1, 1),
        ),
        isNull,
      );
    });

    test('يرسل الوقت إلى API بصيغة UTC', () {
      final value = draft().toJson();
      expect(value['departureAt'], endsWith('Z'));
    });
  });

  test('يفك العرض والحجوزات والمقاعد كما أكدها الخادم', () {
    final offer = IntercityTripOffer.fromJson(intercityOfferJson());
    expect(offer.status, IntercityOfferStatus.open);
    expect(offer.availableSeats, 2);
    expect(offer.bookedSeats, 2);
    expect(offer.confirmedBookingCount, 1);
    expect(offer.bookings.single.passenger?.displayName, 'محمد');
    expect(offer.bookings.single.paymentMethod, 'cash');
    expect(offer.expectedGrossDinars, 100000);
  });

  test('يدعم حالات دورة السيارة الكاملة الموحدة', () {
    expect(rideStatusFromBackend('SEARCHING'), RideStatus.pending);
    expect(rideStatusFromBackend('DRIVER_ASSIGNED'), RideStatus.driverAccepted);
    expect(rideStatusFromBackend('DRIVER_EN_ROUTE'), RideStatus.driverAccepted);
    expect(rideStatusFromBackend('TRIP_PAUSED'), RideStatus.tripPaused);
    expect(rideStatusFromBackend('TRIP_COMPLETED'), RideStatus.completed);
    final ride = Ride.fromJson({
      'id': 'ride-1',
      'status': 'DRIVER_ASSIGNED',
      'pickupLat': 31.04,
      'pickupLng': 46.26,
      'dropoffLat': 33.31,
      'dropoffLng': 44.36,
      'serviceTypeCode': 'intercity_full_vehicle',
      'quoteId': 'quote-1',
      'scheduledAt': '2030-01-02T08:00:00Z',
      'canStart': false,
    });
    expect(ride.isIntercityFullVehicle, isTrue);
    expect(ride.isScheduled, isTrue);
    expect(ride.canStart, isFalse);
  });
}

Map<String, dynamic> intercityOfferJson({
  String status = 'open',
  int availableSeats = 2,
}) => {
  'id': 'offer-1',
  'originGovernorate': 'dhi_qar',
  'destinationGovernorate': 'baghdad',
  'pickup': {'lat': 31.04, 'lng': 46.26, 'address': 'كراج الناصرية'},
  'dropoff': {'lat': 33.31, 'lng': 44.36, 'address': 'كراج بغداد'},
  'departureAt': '2030-01-02T08:00:00Z',
  'totalSeats': 4,
  'availableSeats': availableSeats,
  'pricePerSeatDinars': 25000,
  'distanceMeters': 360000,
  'durationSeconds': 14400,
  'status': status,
  'version': 4,
  'expectedGrossDinars': 100000,
  'dueAmountDinars': 50000,
  'canEdit': true,
  'canCancel': true,
  'bookings': [
    {
      'id': 'booking-1',
      'seatCount': 2,
      'totalPriceDinars': 50000,
      'paymentMethod': 'cash',
      'status': 'confirmed',
      'cancelUntil': '2030-01-02T06:00:00Z',
      'passenger': {'id': 'user-1', 'displayName': 'محمد'},
    },
  ],
};
