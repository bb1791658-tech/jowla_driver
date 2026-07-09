import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jowla_driver/features/trip/application/trip_navigation_options.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const destination = LatLng(30.96, 46.97);

  test('يبني خيارات الملاحة حسب منصة الجهاز', () {
    final ios = buildTripNavigationOptions(
      destination: destination,
      platform: TargetPlatform.iOS,
    );
    final android = buildTripNavigationOptions(
      destination: destination,
      platform: TargetPlatform.android,
    );

    expect(ios.map((option) => option.app), [
      TripNavigationApp.appleMaps,
      TripNavigationApp.googleMaps,
      TripNavigationApp.waze,
      TripNavigationApp.browser,
    ]);
    expect(android.map((option) => option.app), [
      TripNavigationApp.googleMaps,
      TripNavigationApp.waze,
      TripNavigationApp.systemMaps,
      TripNavigationApp.browser,
    ]);
  });

  test('خيار المتصفح يبقى متاحًا حتى إذا لم تتوفر التطبيقات الأصلية', () async {
    final available = await availableTripNavigationOptions(
      destination: destination,
      platform: TargetPlatform.android,
      canOpen: (_) async => false,
    );

    expect(available, hasLength(1));
    expect(available.single.app, TripNavigationApp.browser);
    expect(available.single.url.host, 'www.google.com');
  });
}
