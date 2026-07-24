import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/services/place_name_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../rides/domain/models/ride_offer.dart';
import '../../rides/presentation/ride_formatters.dart';

/// بطاقة عرض الرحلة الوارد عبر ride:offer:new.
///
/// واجهة العد ثابتة على 30 ثانية من لحظة ظهور العرض في جهاز السائق. لا
/// نعتمد بصريًا على ساعة الجهاز أو expiresAt حتى لا ينهار العد على هاتف
/// حقيقي إذا كان توقيته مختلفًا عن الخادم؛ الخادم يبقى مصدر الحقيقة عند
/// القبول أو انتهاء العرض.
class RideRequestSheet extends StatefulWidget {
  const RideRequestSheet({
    required this.offer,
    required this.driverLocation,
    required this.onAccept,
    required this.onReject,
    required this.onTimeout,
    this.offerVisibleUntil,
    this.offerPosition = 1,
    this.offerCount = 1,
    this.onPreviousOffer,
    this.onNextOffer,
    this.isResponding = false,
    super.key,
  });

  final RideOffer offer;
  final LatLng? driverLocation;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onTimeout;
  final DateTime? offerVisibleUntil;
  final int offerPosition;
  final int offerCount;
  final VoidCallback? onPreviousOffer;
  final VoidCallback? onNextOffer;
  final bool isResponding;

  @override
  State<RideRequestSheet> createState() => _RideRequestSheetState();
}

class _RideRequestSheetState extends State<RideRequestSheet> {
  static const _displayDuration = Duration(seconds: 30);

  Timer? _ticker;
  Timer? _expiryTimer;
  late Duration _remaining;
  late Duration _totalDuration;
  var _timeoutSent = false;

  @override
  void initState() {
    super.initState();
    _remaining = _initialRemaining();
    _totalDuration = _displayDuration;
    _expiryTimer = Timer(_remaining, _notifyTimeout);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining = _initialRemaining();
      setState(() => _remaining = remaining);
      if (remaining <= Duration.zero) _notifyTimeout();
    });
  }

  @override
  void didUpdateWidget(covariant RideRequestSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.offer.offerId != widget.offer.offerId ||
        oldWidget.offerVisibleUntil != widget.offerVisibleUntil) {
      _ticker?.cancel();
      _expiryTimer?.cancel();
      _timeoutSent = false;
      _remaining = _initialRemaining();
      _expiryTimer = Timer(_remaining, _notifyTimeout);
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final remaining = _initialRemaining();
        setState(() => _remaining = remaining);
        if (remaining <= Duration.zero) _notifyTimeout();
      });
    }
  }

  void _notifyTimeout() {
    if (_timeoutSent) return;
    _timeoutSent = true;
    _ticker?.cancel();
    widget.onTimeout();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }

  Duration _initialRemaining() {
    final visibleUntil = widget.offerVisibleUntil;
    if (visibleUntil == null) return _displayDuration;
    final remaining = visibleUntil.difference(DateTime.now());
    if (remaining <= Duration.zero) return Duration.zero;
    return remaining > _displayDuration ? _displayDuration : remaining;
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final ride = offer.ride;
    final pickupDistanceKm = _pickupDistanceKm();
    final pickupDistanceText = pickupDistanceKm == null
        ? 'موقع الراكب'
        : formatDistance(pickupDistanceKm);
    final pickupMinutes = pickupDistanceKm == null
        ? null
        : math.max(1, (pickupDistanceKm / 0.5).round());
    final tripDistanceText = ride?.distanceKm == null
        ? 'مسافة الرحلة'
        : formatDistance(ride!.distanceKm!);
    final tripMinutes = ride?.durationMinutes;
    final pickupAddress = ride?.pickupAddress;
    final destinationName = ride?.dropoffAddress;
    final progress = _countdownProgress();
    final colors = Theme.of(context).colorScheme;

    return SizedBox(
      width: double.infinity,
      child: Material(
        color: colors.surface,
        elevation: 18,
        shadowColor: colors.shadow.withValues(alpha: 0.18),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  key: const ValueKey('ride-offer-price'),
                  '${formatIqd(offer.estimatedFare ?? ride?.estimatedFare)} د.ع',
                  textAlign: TextAlign.center,
                  textDirection: ui.TextDirection.rtl,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 36,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 14),
                Directionality(
                  textDirection: ui.TextDirection.rtl,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TimelineRow(
                        icon: Icons.person_outline_rounded,
                        iconColor: AppTheme.primaryGreen,
                        label: 'نقطة الانطلاق',
                        metric: pickupAddress,
                        metricPoint: ride?.pickup ?? offer.pickup,
                        place: pickupDistanceText,
                        placePoint: ride?.pickup ?? offer.pickup,
                        isLast: false,
                      ),
                      _TimelineRow(
                        icon: Icons.location_on_outlined,
                        iconColor: const Color(0xFFE53935),
                        label: 'الوجهة',
                        metric: destinationName,
                        metricPoint: ride?.dropoff,
                        place: tripDistanceText,
                        placePoint: ride?.dropoff,
                        isLast: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  textDirection: ui.TextDirection.rtl,
                  children: [
                    Expanded(
                      child: _TripStat(
                        icon: Icons.schedule_rounded,
                        label: 'الوقت المتوقع',
                        value: formatMinutes(tripMinutes ?? pickupMinutes),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TripStat(
                        icon: Icons.route_rounded,
                        label: 'المسافة',
                        value: tripDistanceText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  textDirection: ui.TextDirection.ltr,
                  children: [
                    Expanded(
                      child: _AcceptButton(
                        progress: progress,
                        seconds: _remaining.inSeconds,
                        isResponding: widget.isResponding,
                        onPressed: widget.isResponding ? null : widget.onAccept,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _RejectButton(
                      isDisabled: widget.isResponding,
                      onPressed: widget.onReject,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _countdownProgress() {
    if (_totalDuration.inMilliseconds <= 0) return 0;
    final value = _remaining.inMilliseconds / _totalDuration.inMilliseconds;
    return value.clamp(0, 1).toDouble();
  }

  double? _pickupDistanceKm() {
    final pickup = widget.offer.pickup;
    final driver = widget.driverLocation;
    if (pickup == null || driver == null) return null;
    return const Distance().as(LengthUnit.Kilometer, driver, pickup);
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.metric,
    required this.metricPoint,
    required this.place,
    required this.placePoint,
    required this.isLast,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String? metric;
  final LatLng? metricPoint;
  final String? place;
  final LatLng? placePoint;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      textDirection: ui.TextDirection.ltr,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    label,
                    textAlign: TextAlign.right,
                    textDirection: ui.TextDirection.rtl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: _PlaceNameText(
                    place: metric,
                    point: metricPoint,
                    fallback: 'جار تحديد اسم الموقع',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                SizedBox(
                  width: double.infinity,
                  child: _PlaceNameText(place: place, point: placePoint),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 34,
          child: Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: icon == Icons.circle
                      ? iconColor.withValues(alpha: 0.18)
                      : iconColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 17),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 48,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.outlineVariant,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlaceNameText extends StatelessWidget {
  const _PlaceNameText({
    required this.place,
    required this.point,
    this.fallback = 'جار تحديد اسم الموقع',
    this.style,
  });

  final String? place;
  final LatLng? point;
  final String fallback;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final existing = place?.trim();
    if (existing != null && existing.isNotEmpty) {
      return _text(context, existing);
    }
    final target = point;
    if (target == null) return _text(context, fallback);

    return FutureBuilder<String?>(
      future: PlaceNameService.instance.nameFor(target),
      builder: (context, snapshot) {
        final resolved = snapshot.data?.trim();
        if (resolved != null && resolved.isNotEmpty) {
          return _text(context, resolved);
        }
        return _text(context, fallback);
      },
    );
  }

  Widget _text(BuildContext context, String value) {
    final effectiveStyle =
        style ??
        TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.25,
        );
    return Text(
      value,
      textAlign: TextAlign.right,
      textDirection: ui.TextDirection.rtl,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: effectiveStyle,
    );
  }
}

class _TripStat extends StatelessWidget {
  const _TripStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        textDirection: ui.TextDirection.rtl,
        children: [
          Icon(icon, color: colors.onSurfaceVariant, size: 22),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AcceptButton extends StatelessWidget {
  const _AcceptButton({
    required this.progress,
    required this.seconds,
    required this.isResponding,
    required this.onPressed,
  });

  final double progress;
  final int seconds;
  final bool isResponding;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('ride-offer-accept'),
          onTap: onPressed,
          child: Ink(
            decoration: BoxDecoration(
              color: const Color(0xFF17221B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final fillWidth = constraints.maxWidth * progress;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: AnimatedContainer(
                        key: const ValueKey('ride-offer-countdown-fill'),
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        width: fillWidth,
                        decoration: const BoxDecoration(
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                    ),
                    Center(
                      child: isResponding
                          ? const SizedBox.square(
                              dimension: 26,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'قبول الرحلة',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                    ),
                    PositionedDirectional(
                      start: 16,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Text(
                          formatNumber(seconds),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _RejectButton extends StatelessWidget {
  const _RejectButton({required this.isDisabled, required this.onPressed});

  final bool isDisabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Material(
        color: isDisabled ? const Color(0xFF61342E) : const Color(0xFFF24C3F),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('ride-offer-reject'),
          onTap: isDisabled ? null : onPressed,
          child: const Icon(Icons.close_rounded, color: Colors.white, size: 38),
        ),
      ),
    );
  }
}
