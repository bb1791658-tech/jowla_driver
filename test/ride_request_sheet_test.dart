import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:jowla_driver/features/rides/domain/models/ride_offer.dart';
import 'package:jowla_driver/features/trip_requests/presentation/ride_request_sheet.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(body: child),
  ),
);

RideOffer _offer({int seconds = 5}) => RideOffer.fromSocketPayload({
  'rideId': 'ride-1',
  'offerId': 'offer-1',
  'expiresAt': DateTime.now().add(Duration(seconds: seconds)).toIso8601String(),
  'pickup': {'lat': 30.96, 'lng': 46.97},
  'estimatedFare': 5000,
  'currency': 'IQD',
});

void main() {
  testWidgets('العد التنازلي يبقى 30 ثانية بصريًا ولا يتأثر بساعة الجهاز', (
    tester,
  ) async {
    var timedOut = false;
    await tester.pumpWidget(
      _wrap(
        RideRequestSheet(
          offer: _offer(seconds: 3),
          driverLocation: null,
          onAccept: () {},
          onReject: () {},
          onTimeout: () => timedOut = true,
        ),
      ),
    );
    expect(find.text('قبول الرحلة'), findsOneWidget);
    expect(find.textContaining('د.ع'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(timedOut, isFalse);
    await tester.pump(const Duration(seconds: 27));
    expect(timedOut, isTrue);
  });

  testWidgets('قبول ورفض يستدعيان الإجراء الصحيح', (tester) async {
    var accepted = false;
    var rejected = false;
    await tester.pumpWidget(
      _wrap(
        RideRequestSheet(
          offer: _offer(seconds: 30),
          driverLocation: null,
          onAccept: () => accepted = true,
          onReject: () => rejected = true,
          onTimeout: () {},
        ),
      ),
    );
    expect(find.text('قبول الرحلة'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ride-offer-accept')));
    expect(accepted, isTrue);
    await tester.tap(find.byKey(const ValueKey('ride-offer-reject')));
    expect(rejected, isTrue);
    // تنظيف مؤقت العد قبل نهاية الاختبار.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('أثناء الرد تُعطل الأزرار', (tester) async {
    await tester.pumpWidget(
      _wrap(
        RideRequestSheet(
          offer: _offer(seconds: 30),
          driverLocation: null,
          isResponding: true,
          onAccept: () {},
          onReject: () {},
          onTimeout: () {},
        ),
      ),
    );
    final accept = tester.widget<InkWell>(
      find.byKey(const ValueKey('ride-offer-accept')),
    );
    expect(accept.onTap, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('السعر وتفاصيل الرحلة تظهر في بطاقة بيضاء بأرقام عربية', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _wrap(
        RideRequestSheet(
          offer: _offer(seconds: 30),
          driverLocation: const LatLng(30.955, 46.985),
          onAccept: () {},
          onReject: () {},
          onTimeout: () {},
        ),
      ),
    );

    final priceText = tester.widget<Text>(
      find.byKey(const ValueKey('ride-offer-price')),
    );
    expect(priceText.data, contains('٥'));
    expect(priceText.data, contains('٠'));
    expect(priceText.data, isNot(contains('5')));
    expect(find.text('نقطة الانطلاق'), findsOneWidget);
    expect(find.text('الوجهة'), findsOneWidget);
    expect(find.text('الوقت المتوقع'), findsOneWidget);
    expect(find.text('المسافة'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('عند وجود عدة عروض لا يأخذ زر التنقل مساحة داخل البطاقة', (
    tester,
  ) async {
    var previous = 0;
    var next = 0;
    await tester.pumpWidget(
      _wrap(
        RideRequestSheet(
          offer: _offer(seconds: 30),
          driverLocation: null,
          offerPosition: 2,
          offerCount: 3,
          onPreviousOffer: () => previous++,
          onNextOffer: () => next++,
          onAccept: () {},
          onReject: () {},
          onTimeout: () {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('ride-offer-switcher')), findsNothing);
    expect(find.text('قبول الرحلة'), findsOneWidget);
    expect(previous, 0);
    expect(next, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
