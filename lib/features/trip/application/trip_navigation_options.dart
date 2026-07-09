import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

enum TripNavigationApp { appleMaps, googleMaps, waze, systemMaps, browser }

class TripNavigationOption {
  const TripNavigationOption({
    required this.app,
    required this.title,
    required this.url,
  });

  final TripNavigationApp app;
  final String title;
  final Uri url;
}

Future<List<TripNavigationOption>> availableTripNavigationOptions({
  required LatLng destination,
  required TargetPlatform platform,
  required Future<bool> Function(Uri url) canOpen,
}) async {
  final options = buildTripNavigationOptions(
    destination: destination,
    platform: platform,
  );
  final available = <TripNavigationOption>[];
  for (final option in options) {
    if (option.app == TripNavigationApp.browser || await canOpen(option.url)) {
      available.add(option);
    }
  }
  return available;
}

List<TripNavigationOption> buildTripNavigationOptions({
  required LatLng destination,
  required TargetPlatform platform,
}) {
  final lat = destination.latitude.toStringAsFixed(7);
  final lng = destination.longitude.toStringAsFixed(7);
  return [
    if (platform == TargetPlatform.iOS)
      TripNavigationOption(
        app: TripNavigationApp.appleMaps,
        title: 'خرائط Apple',
        url: Uri.parse('maps://?daddr=$lat,$lng&dirflg=d'),
      ),
    TripNavigationOption(
      app: TripNavigationApp.googleMaps,
      title: 'Google Maps',
      url: platform == TargetPlatform.iOS
          ? Uri.parse('comgooglemaps://?daddr=$lat,$lng&directionsmode=driving')
          : Uri.parse('google.navigation:q=$lat,$lng&mode=d'),
    ),
    TripNavigationOption(
      app: TripNavigationApp.waze,
      title: 'Waze',
      url: Uri.parse('waze://?ll=$lat,$lng&navigate=yes'),
    ),
    if (platform == TargetPlatform.android)
      TripNavigationOption(
        app: TripNavigationApp.systemMaps,
        title: 'تطبيقات الملاحة',
        url: Uri.parse('geo:$lat,$lng?q=$lat,$lng'),
      ),
    TripNavigationOption(
      app: TripNavigationApp.browser,
      title: 'فتح في المتصفح',
      url: Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': '$lat,$lng',
        'travelmode': 'driving',
      }),
    ),
  ];
}
