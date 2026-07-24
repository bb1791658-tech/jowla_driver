import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

abstract final class IraqMapConfig {
  static const south = 29.0612;
  static const west = 38.7936;
  static const north = 37.3809;
  static const east = 48.5759;
  static const minZoom = 6.0;
  static const maxZoom = 18.0;
  static const center = LatLng(33.3152, 44.3661);
  static const backgroundColor = Color(0xFFF9F4EE);

  static bool contains(LatLng point) =>
      point.latitude >= south &&
      point.latitude <= north &&
      point.longitude >= west &&
      point.longitude <= east;
}
