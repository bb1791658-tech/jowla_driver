import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/road_route_service.dart';
import '../../rides/domain/models/ride.dart';
import '../../rides/domain/models/ride_offer.dart';
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
  final _mapController = MapController();
  String? _lastOfferFocusSignature;
  String? _lastTripFocusSignature;
  static const _fallbackCenter = LatLng(30.9601, 46.9769); // الجبايش

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(driverHomeControllerProvider);
    final trip = ref.watch(tripControllerProvider).valueOrNull;
    final position = home.lastPosition;
    final driverPoint = position == null
        ? null
        : LatLng(position.latitude, position.longitude);
    final heading = position?.heading;

    ref.listen(driverHomeControllerProvider, (previous, next) {
      final message = next.offerError;
      if (message != null && message != previous?.offerError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    });

    final activeOffer = home.activeOffer;
    final hasActiveTrip = trip != null && trip.status.isActiveForDriver;
    final headingToPickup =
        hasActiveTrip && trip.status == RideStatus.driverAccepted;
    final activeTripTarget = hasActiveTrip
        ? (headingToPickup ? trip.pickup : trip.dropoff)
        : null;
    final activeTripStart = hasActiveTrip
        ? (headingToPickup ? driverPoint ?? trip.pickup : trip.pickup)
        : null;
    final activeTripRouteRequest =
        activeTripStart != null && activeTripTarget != null
        ? RoadRouteRequest.fromPoints(activeTripStart, activeTripTarget)
        : null;
    final activeTripRoute = activeTripRouteRequest == null
        ? null
        : ref.watch(roadRoutePathProvider(activeTripRouteRequest)).valueOrNull;
    final activeTripFallbackRoute =
        activeTripStart != null && activeTripTarget != null
        ? <LatLng>[activeTripStart, activeTripTarget]
        : const <LatLng>[];
    final activeTripRoutePoints =
        activeTripRoute != null && activeTripRoute.length >= 2
        ? activeTripRoute
        : activeTripFallbackRoute;
    _scheduleOfferFocus(activeOffer, driverPoint);
    _scheduleActiveTripFocus(
      activeOffer == null && hasActiveTrip ? trip : null,
      driverPoint,
    );

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: driverPoint ?? _fallbackCenter,
              initialZoom: 14,
              minZoom: 5,
              maxZoom: 18,
            ),
            children: [
              TileLayer(
                urlTemplate: AppConfig.mapTileUrlTemplate,
                userAgentPackageName: 'com.jowla.driver',
              ),
              if (activeOffer == null &&
                  hasActiveTrip &&
                  activeTripRoutePoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: activeTripRoutePoints,
                      strokeWidth: 5,
                      color: const Color(0xFF1D6BFF),
                    ),
                  ],
                ),
              if (driverPoint != null && activeOffer == null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: driverPoint,
                      width: 48,
                      height: 72,
                      child: DriverMapCarMarker(headingDegrees: heading),
                    ),
                  ],
                ),
              if (activeOffer != null)
                _OfferMapLayer(
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
                  if (activeOffer == null) const _BalanceSummaryCard(),
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
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
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
              child: RideRequestSheet(
                key: ValueKey(activeOffer.offerId),
                offer: activeOffer,
                driverLocation: driverPoint,
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
            ),
        ],
      ),
    );
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
        _mapController.fitCamera(
          CameraFit.coordinates(
            coordinates: points,
            maxZoom: 16,
            padding: const EdgeInsets.fromLTRB(104, 112, 104, 390),
          ),
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
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: points,
          maxZoom: 16,
          padding: const EdgeInsets.fromLTRB(80, 220, 80, 260),
        ),
      );
    } catch (_) {
      // قد تتغير حالة الرحلة قبل اكتمال بناء الخريطة؛ في هذه الحالة
      // نترك موضع الكاميرا الحالي بدل تعطيل الشاشة.
    }
  }
}

class _OfferMapLayer extends StatelessWidget {
  const _OfferMapLayer({
    required this.offer,
    required this.driverLocation,
    required this.headingDegrees,
  });

  final RideOffer offer;
  final LatLng? driverLocation;
  final double? headingDegrees;

  @override
  Widget build(BuildContext context) {
    final pickup = offer.pickup;
    final dropoff = offer.ride?.dropoff;
    final pickupDistanceKm = pickup != null && driverLocation != null
        ? const Distance().as(LengthUnit.Kilometer, driverLocation!, pickup)
        : null;
    final showCarBelowPickup =
        pickupDistanceKm != null && pickupDistanceKm < 0.08;

    return MarkerLayer(
      markers: [
        if (driverLocation != null)
          Marker(
            point: driverLocation!,
            width: showCarBelowPickup ? 56 : 48,
            height: showCarBelowPickup ? 86 : 72,
            child: showCarBelowPickup
                ? Transform.translate(
                    offset: const Offset(0, 30),
                    child: DriverMapCarMarker(
                      headingDegrees: headingDegrees,
                      width: 28,
                      height: 42,
                    ),
                  )
                : DriverMapCarMarker(headingDegrees: headingDegrees),
          ),
        if (pickup != null)
          Marker(
            point: pickup,
            width: 132,
            height: 48,
            child: PickupMapMarker(distanceKm: pickupDistanceKm),
          ),
        if (dropoff != null)
          Marker(
            point: dropoff,
            width: 58,
            height: 72,
            child: const DropoffMapMarker(),
          ),
      ],
    );
  }
}

class _BalanceSummaryCard extends StatelessWidget {
  const _BalanceSummaryCard();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(18),
            color: Colors.white,
            shadowColor: Colors.black.withValues(alpha: 0.12),
            child: Container(
              width: 220,
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'الرصيد الحالي',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFF6B756E),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                  SizedBox(height: 7),
                  Text(
                    '٠ د.ع',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFF17251C),
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Align(
            alignment: Alignment.centerLeft,
            child: _MessagesButton(),
          ),
        ],
      ),
    );
  }
}

class _MessagesButton extends StatelessWidget {
  const _MessagesButton();

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(18),
      color: Colors.white,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {},
        child: const SizedBox.square(
          dimension: 56,
          child: Icon(Icons.forum_rounded, size: 24, color: Color(0xFF234E2D)),
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
