import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jowla_driver/core/providers.dart';
import 'package:jowla_driver/features/auth/domain/models/driver_session.dart';
import 'package:jowla_driver/features/driver/data/backend_driver_repository.dart';
import 'package:jowla_driver/features/driver/domain/models/driver_account.dart';
import 'package:jowla_driver/features/intercity/data/backend_intercity_driver_repository.dart';
import 'package:jowla_driver/features/intercity/domain/intercity_driver_repository.dart';
import 'package:jowla_driver/features/intercity/domain/models/intercity_offer.dart';
import 'package:jowla_driver/features/intercity/domain/models/intercity_offer_draft.dart';
import 'package:jowla_driver/features/intercity/presentation/intercity_offers_screen.dart';
import 'package:jowla_driver/features/rides/domain/models/ride.dart';

import 'intercity_models_test.dart';
import 'support/fakes.dart';

void main() {
  testWidgets('واجهة RTL تعمل على شاشة صغيرة ومع تكبير النص', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final realtime = FakeRealtimeService();
    addTearDown(realtime.dispose);
    final driver = FakeDriverRepository(
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          realtimeServiceProvider.overrideWithValue(realtime),
          driverRepositoryProvider.overrideWithValue(driver),
          intercityDriverRepositoryProvider.overrideWithValue(
            _ScreenIntercityRepository(),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('ar', 'IQ'),
          supportedLocales: const [Locale('ar', 'IQ')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          ),
          home: const IntercityOffersScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('بين المحافظات'), findsOneWidget);
    expect(find.text('إنشاء رحلة'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('بين المحافظات'))),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });
}

class _ScreenIntercityRepository implements IntercityDriverRepository {
  final offerValue = IntercityTripOffer.fromJson(intercityOfferJson());

  @override
  Future<List<IntercityTripOffer>> offers() async => [offerValue];

  @override
  Future<IntercityTripOffer> offer(String offerId) async => offerValue;

  @override
  Future<List<Ride>> scheduledFullVehicleRides() async => const [];

  @override
  Future<IntercityOfferPreview> preview(IntercityOfferDraft draft) =>
      throw UnimplementedError();

  @override
  Future<IntercityTripOffer> create({
    required IntercityOfferDraft draft,
    IntercityOfferPreview? preview,
    required String idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<IntercityTripOffer> update({
    required String offerId,
    required IntercityOfferDraft draft,
    required IntercityOfferPreview preview,
    required int version,
  }) => throw UnimplementedError();

  @override
  Future<IntercityTripOffer> cancel(String offerId) =>
      throw UnimplementedError();

  @override
  Future<IntercityTripOffer> depart(String offerId) =>
      throw UnimplementedError();

  @override
  Future<IntercityTripOffer> complete(String offerId) =>
      throw UnimplementedError();
}
