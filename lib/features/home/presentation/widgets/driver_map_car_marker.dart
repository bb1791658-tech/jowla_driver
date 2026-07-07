import 'package:flutter/material.dart';

class DriverMapCarMarker extends StatelessWidget {
  const DriverMapCarMarker({
    required this.headingDegrees,
    this.width = 42,
    this.height = 64,
    super.key,
  });

  static const assetPath = 'assets/map_markers/driver-car-top.png';

  final double? headingDegrees;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final heading = headingDegrees;
    final angle =
        (heading != null && heading.isFinite ? heading : 0) * 0.0174533;
    return Transform.rotate(
      angle: angle,
      child: Image.asset(
        assetPath,
        width: width,
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
