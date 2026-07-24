import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jowla_driver/core/providers.dart';
import 'package:jowla_driver/core/services/realtime_service.dart';
import 'package:jowla_driver/features/auth/domain/models/driver_session.dart';
import 'package:jowla_driver/features/driver/data/backend_driver_repository.dart';
import 'package:jowla_driver/features/driver/domain/models/driver_account.dart';
import 'package:jowla_driver/features/intercity/application/intercity_driver_controller.dart';
import 'package:jowla_driver/features/intercity/data/backend_intercity_driver_repository.dart';
import 'package:jowla_driver/features/intercity/domain/intercity_driver_repository.dart';
import 'package:jowla_driver/features/intercity/domain/models/intercity_offer.dart';
import 'package:jowla_driver/features/intercity/domain/models/intercity_offer_draft.dart';
import 'package:jowla_driver/features/intercity/domain/models/iraqi_governorate.dart';
import 'package:jowla_driver/features/rides/domain/models/ride.dart';
import 'package:latlong2/latlong.dart';

import 'intercity_models_test.dart';
import 'support/fakes.dart';

void main() {
  late FakeRealtimeService realtime;
  late _FakeIntercityRepository intercity;
  late ProviderContainer container;

  setUp(() {
    realtime = FakeRealtimeService();
    intercity = _FakeIntercityRepository();
    final drivers = FakeDriverRepository(
      account: const DriverAccount(
        profile: DriverProfile(
          id: 'driver-1',
          name: 'سائق',
          phone: '+9647700000000',
          status: DriverAccountStatus.approved,
        ),
        vehicles: [
          DriverVehicle(
            plateNumber: 'بغداد 1',
            model: 'سيارة',
            seatCapacity: 4,
          ),
        ],
      ),
    );
    container = ProviderContainer(
      overrides: [
        realtimeServiceProvider.overrideWithValue(realtime),
        intercityDriverRepositoryProvider.overrideWithValue(intercity),
        driverRepositoryProvider.overrideWithValue(drivers),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(realtime.dispose);
  });

  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 220));
  }

  test('يستعيد عروض السائق والرحلات المجدولة من REST', () async {
    intercity.serverOffers = [
      IntercityTripOffer.fromJson(intercityOfferJson()),
    ];
    intercity.scheduled = [_scheduledRide()];
    container.read(intercityDriverControllerProvider);
    await settle();
    final state = container.read(intercityDriverControllerProvider);
    expect(state.offers.single.id, 'offer-1');
    expect(state.scheduledRides.single.isScheduled, isTrue);
    expect(state.vehicleCapacity, 4);
  });

  test('الإنشاء لا يضاف محليًا قبل رد الخادم المؤكد', () async {
    container.read(intercityDriverControllerProvider);
    await settle();
    final controller = container.read(
      intercityDriverControllerProvider.notifier,
    );
    final draft = _draft();
    final created = await controller.create(draft);
    expect(created?.id, 'offer-1');
    expect(intercity.createCalls, 1);
    expect(
      container.read(intercityDriverControllerProvider).offers,
      hasLength(1),
    );
  });

  test('التعديل والإلغاء يعتمدان رد Backend فقط', () async {
    intercity.serverOffers = [
      IntercityTripOffer.fromJson(intercityOfferJson()),
    ];
    container.read(intercityDriverControllerProvider);
    await settle();
    final controller = container.read(
      intercityDriverControllerProvider.notifier,
    );
    final current = intercity.serverOffers.single;
    expect(await controller.preview(_draft()), isNotNull);
    expect(await controller.update(_draft(), current), isNotNull);
    expect(intercity.updateCalls, 1);
    expect(await controller.cancel(current.id), isTrue);
    expect(intercity.cancelCalls, 1);
    expect(
      container.read(intercityDriverControllerProvider).offers.single.status,
      IntercityOfferStatus.cancelled,
    );
  });

  test('حدث المقاعد لا يعدل محليًا ويستبدلها بنتيجة REST', () async {
    intercity.serverOffers = [
      IntercityTripOffer.fromJson(intercityOfferJson(availableSeats: 3)),
    ];
    container.read(intercityDriverControllerProvider);
    await settle();
    expect(
      container
          .read(intercityDriverControllerProvider)
          .offers
          .single
          .availableSeats,
      3,
    );
    intercity.serverOffers = [
      IntercityTripOffer.fromJson(intercityOfferJson(availableSeats: 1)),
    ];
    realtime.intercityEventsController.add(
      const RealtimeEvent('intercity:booking:updated', {'offerId': 'offer-1'}),
    );
    expect(
      container
          .read(intercityDriverControllerProvider)
          .offers
          .single
          .availableSeats,
      3,
    );
    await settle();
    expect(
      container
          .read(intercityDriverControllerProvider)
          .offers
          .single
          .availableSeats,
      1,
    );
  });

  test('إعادة الاتصال تعيد مزامنة الامتلاء والإلغاء من REST', () async {
    intercity.serverOffers = [
      IntercityTripOffer.fromJson(intercityOfferJson()),
    ];
    container.read(intercityDriverControllerProvider);
    await settle();
    intercity.serverOffers = [
      IntercityTripOffer.fromJson(
        intercityOfferJson(status: 'full', availableSeats: 0),
      ),
    ];
    realtime.connectionsController.add(null);
    await settle();
    var offer = container.read(intercityDriverControllerProvider).offers.single;
    expect(offer.status, IntercityOfferStatus.full);
    intercity.serverOffers = [
      IntercityTripOffer.fromJson(
        intercityOfferJson(status: 'cancelled', availableSeats: 4),
      ),
    ];
    realtime.intercityEventsController.add(
      const RealtimeEvent('intercity:booking:cancelled', {
        'offerId': 'offer-1',
      }),
    );
    await settle();
    offer = container.read(intercityDriverControllerProvider).offers.single;
    expect(offer.status, IntercityOfferStatus.cancelled);
    expect(offer.availableSeats, 4);
  });

  test('حدث إزالة العرض يمحو النسخة المحلية بعد تأكيد REST', () async {
    intercity.serverOffers = [
      IntercityTripOffer.fromJson(intercityOfferJson()),
    ];
    container.read(intercityDriverControllerProvider);
    await settle();
    await container
        .read(intercityDriverControllerProvider.notifier)
        .loadOffer('offer-1');
    intercity.serverOffers = [];
    realtime.intercityEventsController.add(
      const RealtimeEvent('intercity:offer:removed', {'offerId': 'offer-1'}),
    );
    await settle();
    final state = container.read(intercityDriverControllerProvider);
    expect(state.offers, isEmpty);
    expect(state.selectedOffer, isNull);
  });
}

IntercityOfferDraft _draft() => IntercityOfferDraft(
  originGovernorate: IraqiGovernorate.dhiQar,
  destinationGovernorate: IraqiGovernorate.baghdad,
  pickup: const LatLng(31.04, 46.26),
  dropoff: const LatLng(33.31, 44.36),
  pickupAddress: 'كراج الناصرية',
  dropoffAddress: 'كراج بغداد',
  departureAt: DateTime(2030, 1, 2, 8),
  totalSeats: 4,
  pricePerSeatDinars: 25000,
);

Ride _scheduledRide() => Ride.fromJson({
  'id': 'ride-scheduled',
  'status': 'DRIVER_ASSIGNED',
  'pickupLat': 31.04,
  'pickupLng': 46.26,
  'dropoffLat': 33.31,
  'dropoffLng': 44.36,
  'serviceTypeCode': 'intercity_full_vehicle',
  'scheduledAt': '2030-01-02T08:00:00Z',
  'quoteId': 'quote-1',
  'canStart': false,
});

class _FakeIntercityRepository implements IntercityDriverRepository {
  List<IntercityTripOffer> serverOffers = [];
  List<Ride> scheduled = [];
  var createCalls = 0;
  var updateCalls = 0;
  var cancelCalls = 0;

  @override
  Future<List<IntercityTripOffer>> offers() async => [...serverOffers];

  @override
  Future<IntercityTripOffer> offer(String offerId) async =>
      serverOffers.firstWhere((item) => item.id == offerId);

  @override
  Future<IntercityOfferPreview> preview(IntercityOfferDraft draft) async =>
      IntercityOfferPreview.fromJson({
        'previewId': 'preview-1',
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 5))
            .toUtc()
            .toIso8601String(),
        'minimumPriceDinars': 20000,
        'maximumPriceDinars': 30000,
        'distanceMeters': 360000,
        'durationSeconds': 14400,
        'expectedGrossDinars': 100000,
        'cancellationPolicy': 'حسب سياسة الخادم',
      });

  @override
  Future<IntercityTripOffer> create({
    required IntercityOfferDraft draft,
    IntercityOfferPreview? preview,
    required String idempotencyKey,
  }) async {
    createCalls++;
    final offer = IntercityTripOffer.fromJson(intercityOfferJson());
    serverOffers = [offer];
    return offer;
  }

  @override
  Future<IntercityTripOffer> update({
    required String offerId,
    required IntercityOfferDraft draft,
    required IntercityOfferPreview preview,
    required int version,
  }) async {
    updateCalls++;
    return offer(offerId);
  }

  @override
  Future<IntercityTripOffer> cancel(String offerId) async {
    cancelCalls++;
    final cancelled = IntercityTripOffer.fromJson(
      intercityOfferJson(status: 'cancelled', availableSeats: 4),
    );
    serverOffers = [cancelled];
    return cancelled;
  }

  @override
  Future<IntercityTripOffer> depart(String offerId) async => offer(offerId);

  @override
  Future<IntercityTripOffer> complete(String offerId) async => offer(offerId);

  @override
  Future<List<Ride>> scheduledFullVehicleRides() async => [...scheduled];
}
