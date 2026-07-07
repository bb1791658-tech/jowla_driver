import 'package:flutter/material.dart';

import '../../../trip_requests/presentation/ride_request_sheet.dart'
    show formatDistance;

class PickupMapMarker extends StatelessWidget {
  const PickupMapMarker({required this.distanceKm, super.key});

  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    final distanceText = distanceKm == null
        ? 'قريب'
        : formatDistance(distanceKm!);
    return SizedBox(
      width: 132,
      height: 48,
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
                      color: const Color(0xFF1F6BFF),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFEAF1FF),
                        width: 4,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
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
            bottom: 6,
            child: Container(
              width: 3,
              height: 12,
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
    );
  }
}

class DropoffMapMarker extends StatelessWidget {
  const DropoffMapMarker({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      height: 72,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 0,
            child: Container(
              width: 39,
              height: 39,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: const Color(0xFF20252D), width: 6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Icon(
                Icons.stop_rounded,
                color: Color(0xFF20252D),
                size: 14,
              ),
            ),
          ),
          Positioned(
            bottom: 5,
            child: Container(
              width: 4,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Positioned(
            bottom: 1,
            child: Container(
              width: 17,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
