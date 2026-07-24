import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/maps/jowla_vector_map.dart';
import '../../../core/services/road_route_service.dart';
import '../../../core/services/smart_route_controller.dart';
import '../../../core/services/smart_zones_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../rides/domain/models/ride.dart';
import '../../rides/domain/models/ride_offer.dart';
import '../../rides/presentation/ride_formatters.dart';
import '../../trip/application/trip_controller.dart';
import '../../trip_requests/presentation/ride_request_sheet.dart';
import '../application/driver_home_controller.dart';
import 'widgets/driver_map_car_marker.dart';
import 'widgets/trip_map_markers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _mapController = JowlaMapController();
  late final SmartRouteController _smartTripRoute;
  String? _lastOfferFocusSignature;
  String? _lastTripFocusSignature;

  @override
  void initState() {
    super.initState();
    _smartTripRoute = SmartRouteController(ref.read(roadRouteServiceProvider))
      ..addListener(_onSmartRouteChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref
            .read(driverHomeControllerProvider.notifier)
            .requestCurrentLocation(),
      );
    });
  }

  @override
  void dispose() {
    _smartTripRoute
      ..removeListener(_onSmartRouteChanged)
      ..dispose();
    super.dispose();
  }

  void _onSmartRouteChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(driverHomeControllerProvider);
    final smartZones = ref.watch(smartMapZonesProvider).value ?? const [];
    final colors = Theme.of(context).colorScheme;
    final trip = ref.watch(tripControllerProvider).value;
    final driverPoint = home.mapPoint;
    final heading = home.mapHeading;
    final intercityEnabled = home.services.any(
      (service) => service.code == 'intercity' && service.isActive,
    );

    ref.listen(driverHomeControllerProvider, (previous, next) {
      final message = next.offerError;
      if (message != null && message != previous?.offerError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    });

    final activeOffer = home.activeOffer;
    final nextOffer = home.availableOfferCount > 1
        ? home.nextAvailableOffer
        : null;
    final hasActiveTrip = trip != null && trip.status.isActiveForDriver;
    final activeOfferPickup = activeOffer?.pickup;
    final activeOfferDropoff = activeOffer?.ride?.dropoff;
    final activeOfferRouteRequest =
        activeOfferPickup != null && activeOfferDropoff != null
        ? RoadRouteRequest.fromPoints(activeOfferPickup, activeOfferDropoff)
        : null;
    final activeOfferRoute = activeOfferRouteRequest == null
        ? null
        : ref.watch(roadRoutePathProvider(activeOfferRouteRequest)).value;
    final activeOfferFallbackRoute =
        activeOfferPickup != null && activeOfferDropoff != null
        ? <LatLng>[activeOfferPickup, activeOfferDropoff]
        : const <LatLng>[];
    final activeOfferRoutePoints =
        activeOfferRoute != null && activeOfferRoute.length >= 2
        ? activeOfferRoute
        : activeOfferFallbackRoute;
    final headingToPickup =
        hasActiveTrip && trip.status == RideStatus.driverAccepted;
    final activeTripTarget = hasActiveTrip
        ? (headingToPickup ? trip.pickup : trip.dropoff)
        : null;
    final activeTripStart = hasActiveTrip
        ? (headingToPickup ? driverPoint ?? trip.pickup : trip.pickup)
        : null;
    _scheduleSmartTripRoute(
      activeTripStart,
      activeTripTarget,
      accuracyMeters: home.lastPosition?.accuracy ?? 0,
    );
    final activeTripRoute = _smartTripRoute.target == activeTripTarget
        ? _smartTripRoute.route?.points
        : null;
    final activeTripFallbackRoute =
        activeTripStart != null && activeTripTarget != null
        ? <LatLng>[activeTripStart, activeTripTarget]
        : const <LatLng>[];
    final activeTripRoutePoints =
        activeTripRoute != null && activeTripRoute.length >= 2
        ? activeTripRoute
        : activeTripFallbackRoute;
    final mapInitialCenter =
        driverPoint ??
        activeOffer?.pickup ??
        activeOffer?.ride?.dropoff ??
        activeTripTarget;
    _scheduleOfferFocus(activeOffer, driverPoint);
    _scheduleActiveTripFocus(
      activeOffer == null && hasActiveTrip ? trip : null,
      driverPoint,
    );

    return Scaffold(
      body: Stack(
        children: [
          if (mapInitialCenter == null)
            const _LocationPendingBackground()
          else
            JowlaVectorMap(
              controller: _mapController,
              initialCenter: mapInitialCenter,
              initialZoom: 14,
              polygons: [
                for (final zone in smartZones)
                  JowlaMapPolygon(
                    points: zone.boundary,
                    color: _smartZoneColor(zone),
                    outlineColor: _smartZoneOutlineColor(zone),
                  ),
              ],
              polylines: [
                if (activeOffer == null &&
                    hasActiveTrip &&
                    activeTripRoutePoints.length >= 2)
                  JowlaMapPolyline(
                    points: activeTripRoutePoints,
                    color: const Color(0xFF1D6BFF),
                  ),
                if (activeOffer != null && activeOfferRoutePoints.length >= 2)
                  JowlaMapPolyline(
                    points: activeOfferRoutePoints,
                    color: AppTheme.primaryGreen,
                  ),
              ],
              markers: [
                if (driverPoint != null && activeOffer == null)
                  JowlaMapMarker(
                    point: driverPoint,
                    size: const Size(48, 72),
                    smoothMovement: true,
                    child: DriverMapCarMarker(headingDegrees: heading),
                  ),
                if (activeOffer != null)
                  ..._offerMapMarkers(
                    offer: activeOffer,
                    driverLocation: driverPoint,
                    headingDegrees: heading,
                  ),
              ],
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (activeOffer == null)
                    _BalanceSummaryCard(
                      balance: home.wallet?.balance,
                      isLoading: home.isWalletLoading,
                      hasError: home.walletError != null,
                      activeRideId: hasActiveTrip ? trip.id : null,
                      onPressed: () => context.push('/wallet'),
                    ),
                  if (activeOffer == null) ...[
                    const SizedBox(height: 8),
                    _IntercityServiceCard(
                      isEnabled: intercityEnabled,
                      onPressed: () => context.push('/intercity'),
                    ),
                  ],
                  if (home.error != null) ...[
                    const SizedBox(height: 8),
                    Material(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(home.error!, textAlign: TextAlign.center),
                      ),
                    ),
                  ],
                  if (hasActiveTrip) ...[
                    const SizedBox(height: 8),
                    _ActiveTripBanner(
                      ride: trip,
                      onPressed: () => context.push('/trip'),
                    ),
                  ],
                  const Spacer(),
                  if (activeOffer == null) ...[
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: FloatingActionButton.small(
                        heroTag: 'recenter',
                        backgroundColor: colors.surface,
                        foregroundColor: colors.onSurface,
                        onPressed: driverPoint == null
                            ? null
                            : () => _mapController.move(driverPoint, 16),
                        child: const Icon(Icons.my_location_rounded),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (activeOffer != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (nextOffer != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _OtherOfferPriceButton(
                          offer: nextOffer,
                          isDisabled: home.isRespondingToOffer,
                          onPressed: () => ref
                              .read(driverHomeControllerProvider.notifier)
                              .showNextOffer(),
                        ),
                      ),
                    ),
                  ],
                  RideRequestSheet(
                    key: ValueKey(activeOffer.offerId),
                    offer: activeOffer,
                    driverLocation: driverPoint,
                    offerVisibleUntil:
                        home.offerVisibleUntil[activeOffer.offerId],
                    offerPosition: home.offerPosition,
                    offerCount: home.offerCount,
                    isResponding: home.isRespondingToOffer,
                    onPreviousOffer: () => ref
                        .read(driverHomeControllerProvider.notifier)
                        .showPreviousOffer(),
                    onNextOffer: () => ref
                        .read(driverHomeControllerProvider.notifier)
                        .showNextOffer(),
                    onAccept: () async {
                      final accepted = await ref
                          .read(driverHomeControllerProvider.notifier)
                          .acceptOffer();
                      if (accepted && context.mounted) context.push('/trip');
                    },
                    onReject: () => ref
                        .read(driverHomeControllerProvider.notifier)
                        .rejectOffer(),
                    onTimeout: () => ref
                        .read(driverHomeControllerProvider.notifier)
                        .offerTimedOut(activeOffer.offerId),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _scheduleSmartTripRoute(
    LatLng? start,
    LatLng? target, {
    required double accuracyMeters,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (start == null || target == null) {
        if (_smartTripRoute.target != null) _smartTripRoute.reset();
        return;
      }
      unawaited(
        _smartTripRoute.update(
          current: start,
          target: target,
          accuracyMeters: accuracyMeters,
        ),
      );
    });
  }

  void _scheduleOfferFocus(RideOffer? offer, LatLng? driverPoint) {
    if (offer == null) {
      _lastOfferFocusSignature = null;
      return;
    }
    final signature = _offerFocusSignature(offer, driverPoint);
    if (signature == _lastOfferFocusSignature) return;
    _lastOfferFocusSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusOffer(offer, driverPoint);
    });
  }

  void _scheduleActiveTripFocus(Ride? ride, LatLng? driverPoint) {
    if (ride == null) {
      _lastTripFocusSignature = null;
      return;
    }
    final signature = _tripFocusSignature(ride, driverPoint);
    if (signature == _lastTripFocusSignature) return;
    _lastTripFocusSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusActiveTrip(ride, driverPoint);
    });
  }

  String _offerFocusSignature(RideOffer offer, LatLng? driverPoint) {
    final pickup = offer.pickup;
    final dropoff = offer.ride?.dropoff;
    String pointKey(LatLng? point) => point == null
        ? 'none'
        : '${point.latitude.toStringAsFixed(6)},${point.longitude.toStringAsFixed(6)}';
    return [
      offer.offerId,
      pointKey(driverPoint),
      pointKey(pickup),
      pointKey(dropoff),
    ].join('|');
  }

  String _tripFocusSignature(Ride ride, LatLng? driverPoint) {
    final headingToPickup = ride.status == RideStatus.driverAccepted;
    final target = headingToPickup ? ride.pickup : ride.dropoff;
    final start = headingToPickup ? driverPoint ?? ride.pickup : ride.pickup;
    String pointKey(LatLng? point) => point == null
        ? 'none'
        : '${point.latitude.toStringAsFixed(5)},${point.longitude.toStringAsFixed(5)}';
    return [
      ride.id,
      ride.status.name,
      pointKey(start),
      pointKey(target),
    ].join('|');
  }

  void _focusOffer(RideOffer offer, LatLng? driverPoint) {
    final dropoff = offer.ride?.dropoff;
    final offerPoints = <LatLng>[?offer.pickup, ?dropoff];
    final points = offerPoints.isEmpty ? <LatLng>[?driverPoint] : offerPoints;
    if (points.isEmpty) return;

    try {
      if (points.length == 1) {
        _mapController.move(points.first, 15);
      } else {
        _mapController.fitCoordinates(
          points,
          maxZoom: 16,
          padding: const EdgeInsets.fromLTRB(104, 112, 104, 390),
        );
      }
    } catch (_) {
      // قد تصل أول رحلة قبل أن يكتمل بناء الخريطة؛ في هذه الحالة نترك
      // المركز الافتراضي بدل تعطيل شاشة السائق.
    }
  }

  void _focusActiveTrip(Ride ride, LatLng? driverPoint) {
    final headingToPickup = ride.status == RideStatus.driverAccepted;
    final start = headingToPickup ? driverPoint ?? ride.pickup : ride.pickup;
    final target = headingToPickup ? ride.pickup : ride.dropoff;
    final points = <LatLng>[start, target];

    try {
      _mapController.fitCoordinates(
        points,
        maxZoom: 16,
        padding: const EdgeInsets.fromLTRB(80, 220, 80, 260),
      );
    } catch (_) {
      // قد تتغير حالة الرحلة قبل اكتمال بناء الخريطة؛ في هذه الحالة
      // نترك موضع الكاميرا الحالي بدل تعطيل الشاشة.
    }
  }
}

Color _smartZoneColor(SmartMapZone zone) => switch (zone.kind) {
  SmartZoneKind.officialPickup => const Color(0x2834A853),
  SmartZoneKind.noPickup => const Color(0x30E53935),
  SmartZoneKind.danger => const Color(0x36D32F2F),
  SmartZoneKind.closure => const Color(0x3AFF8F00),
  SmartZoneKind.serviceArea => const Color(0x202F80ED),
  SmartZoneKind.pricing => const Color(0x28A855F7),
  SmartZoneKind.demand => switch (zone.demand) {
    SmartZoneDemand.moderate => const Color(0x242F80ED),
    SmartZoneDemand.high => const Color(0x2EF2994A),
    SmartZoneDemand.veryHigh => const Color(0x38EB5757),
  },
};

Color _smartZoneOutlineColor(SmartMapZone zone) => switch (zone.kind) {
  SmartZoneKind.officialPickup => const Color(0x9034A853),
  SmartZoneKind.noPickup => const Color(0xA0E53935),
  SmartZoneKind.danger => const Color(0xB0B71C1C),
  SmartZoneKind.closure => const Color(0xB0F57C00),
  SmartZoneKind.serviceArea => const Color(0x803B82F6),
  SmartZoneKind.pricing => const Color(0x909333EA),
  SmartZoneKind.demand => switch (zone.demand) {
    SmartZoneDemand.moderate => const Color(0x703B82F6),
    SmartZoneDemand.high => const Color(0x80F59E0B),
    SmartZoneDemand.veryHigh => const Color(0x90EF4444),
  },
};

class _IntercityServiceCard extends StatelessWidget {
  const _IntercityServiceCard({
    required this.isEnabled,
    required this.onPressed,
  });

  final bool isEnabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('intercity-service-card'),
      color: colors.primaryContainer,
      elevation: 6,
      shadowColor: colors.primary.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(Icons.route_rounded, color: colors.onPrimary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'بين المحافظات',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'جديد',
                            style: TextStyle(
                              color: colors.onPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      isEnabled
                          ? 'إنشاء عرض مقاعد وإدارة الرحلات المجدولة'
                          : 'استعرض الخدمة؛ سيؤكد الخادم أهلية النشر',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _OtherOfferPriceButton extends StatelessWidget {
  const _OtherOfferPriceButton({
    required this.offer,
    required this.isDisabled,
    required this.onPressed,
  });

  final RideOffer offer;
  final bool isDisabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final fare = formatIqd(offer.estimatedFare ?? offer.ride?.estimatedFare);
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      elevation: 10,
      shadowColor: colors.shadow.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('other-offer-price-button'),
        onTap: isDisabled ? null : onPressed,
        child: Container(
          height: 44,
          padding: const EdgeInsetsDirectional.only(start: 14, end: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            textDirection: ui.TextDirection.rtl,
            children: [
              Text(
                '$fare د.ع',
                textDirection: ui.TextDirection.rtl,
                style: TextStyle(
                  color: isDisabled
                      ? AppTheme.primaryGreen.withValues(alpha: 0.42)
                      : AppTheme.primaryGreen,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_left_rounded,
                size: 22,
                color: isDisabled
                    ? AppTheme.primaryGreen.withValues(alpha: 0.42)
                    : AppTheme.primaryGreen,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationPendingBackground extends StatelessWidget {
  const _LocationPendingBackground();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.my_location_rounded,
                size: 52,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 14),
              Text(
                'بانتظار موقعك الحقيقي',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'فعّل خدمة الموقع واسمح للتطبيق بالوصول إليها.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<JowlaMapMarker> _offerMapMarkers({
  required RideOffer offer,
  required LatLng? driverLocation,
  required double? headingDegrees,
}) {
  final pickup = offer.pickup;
  final dropoff = offer.ride?.dropoff;
  final pickupDistanceKm = pickup != null && driverLocation != null
      ? const Distance().as(LengthUnit.Kilometer, driverLocation, pickup)
      : null;
  final showCarBelowPickup =
      pickupDistanceKm != null && pickupDistanceKm < 0.08;

  return [
    if (driverLocation != null)
      JowlaMapMarker(
        point: driverLocation,
        size: Size(showCarBelowPickup ? 56 : 48, showCarBelowPickup ? 102 : 72),
        smoothMovement: true,
        child: showCarBelowPickup
            ? Transform.translate(
                offset: const Offset(0, 44),
                child: DriverMapCarMarker(
                  headingDegrees: headingDegrees,
                  width: 28,
                  height: 42,
                ),
              )
            : DriverMapCarMarker(headingDegrees: headingDegrees),
      ),
    if (pickup != null)
      JowlaMapMarker(
        alignment: Alignment.bottomCenter,
        point: pickup,
        size: Size(
          PickupMapMarker.markerWidth,
          PickupMapMarker.markerHeight(showCarBelowPickup ? 8 : 0),
        ),
        child: PickupMapMarker(
          distanceKm: pickupDistanceKm,
          liftPixels: showCarBelowPickup ? 8 : 0,
        ),
      ),
    if (dropoff != null)
      JowlaMapMarker(
        alignment: Alignment.bottomCenter,
        point: dropoff,
        size: const Size(
          DropoffMapMarker.markerWidth,
          DropoffMapMarker.markerHeight,
        ),
        child: const DropoffMapMarker(),
      ),
  ];
}

class _BalanceSummaryCard extends StatelessWidget {
  const _BalanceSummaryCard({
    required this.balance,
    required this.isLoading,
    required this.hasError,
    required this.activeRideId,
    required this.onPressed,
  });

  final double? balance;
  final bool isLoading;
  final bool hasError;
  final String? activeRideId;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 68,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(18),
            color: colors.surface,
            shadowColor: colors.shadow.withValues(alpha: 0.12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: Container(
                width: 220,
                height: 68,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الرصيد الحالي',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _balanceText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasError ? colors.error : colors.onSurface,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: _MessagesButton(activeRideId: activeRideId),
          ),
        ],
      ),
    );
  }

  String get _balanceText {
    if (isLoading && balance == null) return '...';
    if (balance == null) return hasError ? 'غير متاح' : '٠ د.ع';
    return '${formatIqd(balance)} د.ع';
  }
}

class _MessagesButton extends StatelessWidget {
  const _MessagesButton({required this.activeRideId});

  final String? activeRideId;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(18),
      color: colors.surface,
      shadowColor: colors.shadow.withValues(alpha: 0.12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          final rideId = activeRideId;
          if (rideId != null && rideId.isNotEmpty) {
            context.push('/rides/$rideId/chat');
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تتوفر المراسلة أثناء الرحلة النشطة.'),
            ),
          );
        },
        child: SizedBox.square(
          dimension: 56,
          child: Icon(Icons.forum_rounded, size: 24, color: colors.primary),
        ),
      ),
    );
  }
}

class _ActiveTripBanner extends StatelessWidget {
  const _ActiveTripBanner({required this.ride, required this.onPressed});

  final Ride ride;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        onTap: onPressed,
        leading: const Icon(Icons.route_rounded),
        title: const Text('لديك رحلة نشطة'),
        subtitle: Text(ride.status.arabicLabel),
        trailing: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
      ),
    );
  }
}
