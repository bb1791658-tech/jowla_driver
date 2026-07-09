import 'package:flutter/material.dart';

import '../../../rides/presentation/ride_formatters.dart';

class PickupMapMarker extends StatelessWidget {
  const PickupMapMarker({
    required this.distanceKm,
    this.liftPixels = 0,
    super.key,
  });

  static const scale = 0.65;
  static const markerWidth = 132.0 * scale;
  static double markerHeight(double liftPixels) => (52 + liftPixels) * scale;

  final double? distanceKm;
  final double liftPixels;

  @override
  Widget build(BuildContext context) {
    final distanceText = distanceKm == null
        ? 'قريب'
        : formatDistance(distanceKm!);

    return SizedBox(
      width: markerWidth,
      height: markerHeight(liftPixels),
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 132,
          height: 52 + liftPixels,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Positioned(
                top: 0,
                child: Container(
                  height: 34,
                  padding: const EdgeInsetsDirectional.fromSTEB(6, 3, 7, 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.24),
                        blurRadius: 7,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    textDirection: TextDirection.rtl,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF1EA85B,
                          ).withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF1EA85B),
                            width: 2,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.circle,
                          color: Color(0xFF1EA85B),
                          size: 10,
                        ),
                      ),
                      const SizedBox(width: 7),
                      const Text(
                        'الانطلاق',
                        style: TextStyle(
                          color: Color(0xFF141820),
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141820),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          distanceText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 37,
                child: Container(
                  width: 3,
                  height: 14 + liftPixels,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 3,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DropoffMapMarker extends StatelessWidget {
  const DropoffMapMarker({super.key});

  static const scale = 0.65;
  static const markerWidth = 58.0 * scale;
  static const markerHeight = 52.0 * scale;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: markerWidth,
      height: markerHeight,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 58,
          height: 52,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Positioned(
                top: 0,
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.24),
                        blurRadius: 7,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'وصول',
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      color: Color(0xFF141820),
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 37,
                child: Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 3,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
