import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/maps/jowla_vector_map.dart';
import '../../../core/services/road_route_service.dart';
import '../../../core/services/smart_route_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../home/application/driver_home_controller.dart';
import '../../home/presentation/widgets/driver_map_car_marker.dart';
import '../../home/presentation/widgets/trip_map_markers.dart';
import '../../rides/domain/models/ride.dart';
import '../../rides/presentation/ride_formatters.dart';
import '../../communications/presentation/call_method_sheet.dart';
import '../application/trip_navigation_options.dart';
import '../application/trip_controller.dart';

class TripScreen extends ConsumerWidget {
  const TripScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripState = ref.watch(tripControllerProvider);
    final ride = tripState.value;

    ref.listen(tripControllerProvider, (_, next) {
      if (next.hasError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error.toString())));
      }
    });

    if (ride == null && tripState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (ride == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('الرحلة الحالية')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.route_outlined, size: 56, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('لا توجد رحلة نشطة'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go('/home'),
                child: const Text('العودة للرئيسية'),
              ),
            ],
          ),
        ),
      );
    }

    if (ride.status == RideStatus.completed) {
      return _TripSummaryScreen(ride: ride);
    }
    if (ride.status.isFinished) {
      return _TripEndedScreen(ride: ride);
    }
    return _ActiveTripScreen(ride: ride, isBusy: tripState.isLoading);
  }
}

class _ActiveTripScreen extends ConsumerStatefulWidget {
  const _ActiveTripScreen({required this.ride, required this.isBusy});

  final Ride ride;
  final bool isBusy;

  @override
  ConsumerState<_ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends ConsumerState<_ActiveTripScreen> {
  late final SmartRouteController _smartRoute;

  @override
  void initState() {
    super.initState();
    _smartRoute = SmartRouteController(ref.read(roadRouteServiceProvider))
      ..addListener(_onRouteChanged);
  }

  @override
  void dispose() {
    _smartRoute
      ..removeListener(_onRouteChanged)
      ..dispose();
    super.dispose();
  }

  void _onRouteChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final isBusy = widget.isBusy;
    final home = ref.watch(driverHomeControllerProvider);
    final position = home.lastPosition;
    final driverPoint = home.mapPoint;
    final headingToPickup = ride.status == RideStatus.driverAccepted;
    final target = headingToPickup ? ride.pickup : ride.dropoff;
    final routeStart = headingToPickup
        ? driverPoint ?? ride.pickup
        : ride.pickup;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        _smartRoute.update(
          current: routeStart,
          target: target,
          accuracyMeters: position?.accuracy ?? 0,
        ),
      );
    });
    final routePoints =
        (_smartRoute.target == target ? _smartRoute.route?.points : null)
            ?.where(
              (point) => point.latitude.isFinite && point.longitude.isFinite,
            )
            .toList();
    final fallbackRoute = routeStart == target
        ? <LatLng>[routeStart]
        : <LatLng>[routeStart, target];
    final displayedRoute = routePoints != null && routePoints.length >= 2
        ? routePoints
        : fallbackRoute;
    final distanceToTargetKm = driverPoint == null
        ? null
        : const Distance().as(LengthUnit.Kilometer, driverPoint, target);
    final pickupDistanceKm = driverPoint == null
        ? null
        : const Distance().as(LengthUnit.Kilometer, driverPoint, ride.pickup);
    final showCarBelowPickup =
        headingToPickup &&
        distanceToTargetKm != null &&
        distanceToTargetKm < 0.08;
    final smartEta = _smartRoute.target == target
        ? _smartRoute.eta(
            currentSpeedMetersPerSecond: position?.speed,
            localDeparture: DateTime.now(),
          )
        : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/home');
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: JowlaVectorMap(
                initialCenter: driverPoint ?? ride.pickup,
                initialZoom: 14,
                polylines: [
                  JowlaMapPolyline(
                    points: displayedRoute,
                    color: const Color(0xFF1D6BFF),
                  ),
                ],
                markers: [
                  if (driverPoint != null && !showCarBelowPickup)
                    JowlaMapMarker(
                      point: driverPoint,
                      size: const Size(40, 58),
                      smoothMovement: true,
                      child: DriverMapCarMarker(
                        headingDegrees: home.mapHeading,
                        width: 30,
                        height: 46,
                      ),
                    ),
                  if (driverPoint != null && showCarBelowPickup)
                    JowlaMapMarker(
                      point: driverPoint,
                      size: const Size(56, 102),
                      smoothMovement: true,
                      child: Transform.translate(
                        offset: const Offset(0, 44),
                        child: DriverMapCarMarker(
                          headingDegrees: home.mapHeading,
                          width: 28,
                          height: 42,
                        ),
                      ),
                    ),
                  if (headingToPickup)
                    JowlaMapMarker(
                      alignment: Alignment.bottomCenter,
                      point: ride.pickup,
                      size: Size(
                        PickupMapMarker.markerWidth,
                        PickupMapMarker.markerHeight(
                          showCarBelowPickup ? 8 : 0,
                        ),
                      ),
                      child: PickupMapMarker(
                        distanceKm: pickupDistanceKm,
                        liftPixels: showCarBelowPickup ? 8 : 0,
                      ),
                    ),
                  JowlaMapMarker(
                    alignment: Alignment.bottomCenter,
                    point: ride.dropoff,
                    size: const Size(
                      DropoffMapMarker.markerWidth,
                      DropoffMapMarker.markerHeight,
                    ),
                    child: const DropoffMapMarker(),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: _TripPanel(
                ride: ride,
                isBusy: isBusy,
                distanceToTargetKm: distanceToTargetKm,
                smartEta: smartEta,
                headingToPickup: headingToPickup,
                navigationTarget: target,
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: SafeArea(
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  elevation: 8,
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'إلغاء الرحلة',
                    visualDensity: VisualDensity.compact,
                    onPressed: isBusy
                        ? null
                        : () => _confirmCancelTrip(context, ref),
                    icon: Icon(
                      Icons.close_rounded,
                      color: Theme.of(context).colorScheme.error,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _confirmCancelTrip(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('هل أنت متأكد من إلغاء الرحلة؟'),
      content: const Text('قد يترتب عليك مخالفة عند إلغاء الرحلة.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('رجوع للرحلة'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('إلغاء الرحلة'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await ref.read(tripControllerProvider.notifier).cancelRide();
}

Future<void> _openNavigation(
  BuildContext context, {
  required LatLng destination,
}) async {
  final available = await availableTripNavigationOptions(
    destination: destination,
    platform: defaultTargetPlatform,
    canOpen: canLaunchUrl,
  );

  if (!context.mounted) return;
  final selected = await showModalBottomSheet<TripNavigationOption>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'اختر تطبيق الملاحة',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          for (final option in available)
            ListTile(
              leading: Icon(_navigationIcon(option.app)),
              title: Text(option.title),
              onTap: () => Navigator.pop(context, option),
            ),
        ],
      ),
    ),
  );
  if (selected == null) return;

  try {
    final launched = await launchUrl(
      selected.url,
      mode: LaunchMode.externalApplication,
    );
    if (launched) return;
  } catch (_) {}

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر فتح تطبيق الملاحة على هذا الجهاز.')),
    );
  }
}

IconData _navigationIcon(TripNavigationApp app) {
  return switch (app) {
    TripNavigationApp.appleMaps => Icons.map_rounded,
    TripNavigationApp.googleMaps => Icons.map_outlined,
    TripNavigationApp.waze => Icons.navigation_rounded,
    TripNavigationApp.systemMaps => Icons.assistant_direction_rounded,
    TripNavigationApp.browser => Icons.public_rounded,
  };
}

class _TripPanel extends ConsumerWidget {
  const _TripPanel({
    required this.ride,
    required this.isBusy,
    required this.distanceToTargetKm,
    required this.smartEta,
    required this.headingToPickup,
    required this.navigationTarget,
  });

  final Ride ride;
  final bool isBusy;
  final double? distanceToTargetKm;
  final SmartEta? smartEta;
  final bool headingToPickup;
  final LatLng navigationTarget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rider = ride.rider;
    final showPrimaryAction =
        ride.status == RideStatus.driverAccepted ||
        ride.status == RideStatus.driverArrived ||
        ride.status == RideStatus.tripStarted ||
        ride.status == RideStatus.tripPaused;
    return SizedBox(
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              elevation: 16,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const _RiderAvatar(),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  rider?.displayName ?? 'راكب جولة',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  headingToPickup
                                      ? (ride.pickupAddress ?? 'نقطة الانطلاق')
                                      : (ride.dropoffAddress ?? 'الوجهة'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          IconButton.filledTonal(
                            tooltip: 'الاتصال بالراكب',
                            onPressed: () =>
                                unawaited(_callRider(context, ride)),
                            icon: const Icon(Icons.call_rounded),
                          ),
                          IconButton.filledTonal(
                            tooltip: 'محادثة الراكب',
                            onPressed: () =>
                                context.push('/rides/${ride.id}/chat'),
                            icon: const Icon(Icons.chat_bubble_outline_rounded),
                          ),
                        ],
                      ),
                      const Divider(height: 22),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          if (distanceToTargetKm != null)
                            _PanelMetric(
                              label: headingToPickup
                                  ? 'حتى الانطلاق'
                                  : 'حتى الوجهة',
                              value:
                                  '${distanceToTargetKm!.toStringAsFixed(1)} كم',
                            ),
                          if (ride.distanceKm != null)
                            _PanelMetric(
                              label: 'مسافة الرحلة',
                              value:
                                  '${ride.distanceKm!.toStringAsFixed(1)} كم',
                            ),
                          if (smartEta != null)
                            _PanelMetric(
                              label: 'الوصول المتوقع',
                              value:
                                  '≈ ${(smartEta!.expected.inSeconds / 60).ceil()} د',
                            )
                          else if (ride.durationMinutes != null)
                            _PanelMetric(
                              label: 'الوقت المقدر',
                              value: '${ride.durationMinutes} د',
                            ),
                          if (ride.estimatedFare != null)
                            _PanelMetric(
                              label: 'الأجرة المقدرة',
                              value: formatIqd(ride.estimatedFare!),
                            ),
                        ],
                      ),
                      if (showPrimaryAction) ...[
                        const SizedBox(height: 14),
                        _PrimaryAction(ride: ride, isBusy: isBusy),
                        if (ride.status == RideStatus.tripStarted) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: isBusy
                                ? null
                                : () => ref
                                      .read(tripControllerProvider.notifier)
                                      .pauseTrip(),
                            icon: const Icon(Icons.pause_rounded),
                            label: const Text('إيقاف الرحلة مؤقتًا'),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: 0,
            start: 20,
            child: _RoutePillButton(
              onPressed: () =>
                  _openNavigation(context, destination: navigationTarget),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _callRider(BuildContext context, Ride ride) async {
    final phoneNumber = ride.rider?.phone?.trim();
    final method = await showCallMethodSheet(
      context,
      phoneAvailable: phoneNumber != null && phoneNumber.isNotEmpty,
    );
    if (method == null || !context.mounted) return;

    if (method == CallMethod.devicePhone) {
      var launched = false;
      try {
        launched = await launchUrl(
          Uri(scheme: 'tel', path: phoneNumber!),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {}
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر فتح تطبيق الهاتف على هذا الجهاز.'),
          ),
        );
      }
      return;
    }

    await context.push('/rides/${ride.id}/call');
  }
}

class _RiderAvatar extends StatelessWidget {
  const _RiderAvatar();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 44,
      height: 40,
      child: Align(
        alignment: Alignment.centerRight,
        child: CircleAvatar(radius: 20, child: Icon(Icons.person_rounded)),
      ),
    );
  }
}

class _RoutePillButton extends StatelessWidget {
  const _RoutePillButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.primaryGreen,
      elevation: 6,
      borderRadius: BorderRadius.circular(22),
      shadowColor: Colors.black.withValues(alpha: 0.24),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onPressed,
        child: const Tooltip(
          message: 'تحديد المسار',
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(12, 8, 10, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              textDirection: TextDirection.rtl,
              children: [
                Icon(Icons.near_me_rounded, size: 20, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  'تحديد المسار',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryAction extends ConsumerWidget {
  const _PrimaryAction({required this.ride, required this.isBusy});

  final Ride ride;
  final bool isBusy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(tripControllerProvider.notifier);
    final action = switch (ride.status) {
      RideStatus.driverAccepted => (
        label: 'وصلت إلى نقطة الانطلاق',
        color: AppTheme.primaryGreen,
        run: () => controller.markArrived(),
      ),
      RideStatus.driverArrived => (
        label: 'ركب الزبون السيارة',
        color: AppTheme.primaryGreen,
        run: () => controller.startTrip(),
      ),
      RideStatus.tripStarted => (
        label: 'إتمام الرحلة',
        color: const Color(0xFF0F8A3A),
        run: () => _confirmCashAndComplete(context, ref),
      ),
      RideStatus.tripPaused => (
        label: 'متابعة الرحلة',
        color: AppTheme.primaryGreen,
        run: () => controller.resumeTrip(),
      ),
      _ => null,
    };
    if (action == null) {
      return const SizedBox.shrink();
    }
    return FilledButton(
      onPressed: isBusy
          ? null
          : () async {
              await action.run();
            },
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        backgroundColor: action.color,
      ),
      child: isBusy
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              action.label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
    );
  }
}

Future<void> _confirmCashAndComplete(
  BuildContext context,
  WidgetRef ref,
) async {
  final ride = ref.read(tripControllerProvider).value;
  if (ride == null) return;
  final amount = ride.finalFare ?? ride.estimatedFare;
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.52,
      child: _CashConfirmationSheet(amount: amount),
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final controller = ref.read(tripControllerProvider.notifier);
  final completed = await controller.completeTrip();
  if (completed && context.mounted) {
    context.go('/home');
  }
}

class _CashConfirmationSheet extends StatelessWidget {
  const _CashConfirmationSheet({required this.amount});

  final double? amount;

  @override
  Widget build(BuildContext context) {
    final amountText = amount == null ? 'غير محدد' : formatIqd(amount);
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(34),
                      ),
                      child: const Icon(
                        Icons.payments_rounded,
                        color: Color(0xFF0F8A3A),
                        size: 56,
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'تأكيد استلام النقد',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      amountText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 34,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'تأكد من استلام المبلغ من الراكب قبل إنهاء الرحلة.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: const Color(0xFF0F8A3A),
                ),
                child: const Text(
                  'تأكيد وإنهاء الرحلة',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('رجوع للرحلة'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelMetric extends StatelessWidget {
  const _PanelMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

/// ملخص الرحلة المكتملة: الأجرة النهائية والعمولة وصافي المبلغ.
/// المصدر: رد POST /rides/{id}/complete الذي يتضمن payment
/// {amount, commissionAmount} (rides.service.complete + payments.service).
class _TripSummaryScreen extends ConsumerWidget {
  const _TripSummaryScreen({required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payment = ride.payment;
    final fare = payment?.amount ?? ride.finalFare ?? ride.estimatedFare;
    final commission = payment?.commissionAmount;
    final net =
        payment?.netAmount ??
        (fare != null && commission != null ? fare - commission : null);
    return Scaffold(
      appBar: AppBar(title: const Text('ملخص الرحلة')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            Card(
              elevation: 0,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: .07),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 64,
                      color: AppTheme.primaryGreen,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'اكتملت الرحلة',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (fare != null)
              _SummaryRow(label: 'الأجرة النهائية', value: formatIqd(fare)),
            if (commission != null)
              _SummaryRow(label: 'عمولة جولة', value: formatIqd(commission)),
            if (net != null)
              _SummaryRow(
                label: 'صافي المبلغ لك',
                value: formatIqd(net),
                emphasized: true,
              ),
            if (payment != null && payment.method != null)
              _SummaryRow(
                label: 'طريقة الدفع',
                value: payment.method == 'CASH' ? 'نقدًا' : payment.method!,
              ),
            if (ride.distanceKm != null)
              _SummaryRow(
                label: 'المسافة',
                value: '${ride.distanceKm!.toStringAsFixed(1)} كم',
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () async {
                await ref.read(tripControllerProvider.notifier).clear();
                if (context.mounted) context.go('/home');
              },
              child: const Text('العودة للرئيسية'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripEndedScreen extends ConsumerWidget {
  const _TripEndedScreen({required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('الرحلة')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cancel_rounded,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 14),
              Text(
                ride.status.arabicLabel,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: () async {
                  await ref.read(tripControllerProvider.notifier).clear();
                  if (context.mounted) context.go('/home');
                },
                child: const Text('العودة للرئيسية'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: emphasized ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: emphasized ? 18 : 15,
            color: emphasized ? AppTheme.primaryGreen : null,
          ),
        ),
      ],
    ),
  );
}
