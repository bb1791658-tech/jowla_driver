import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../rides/domain/models/ride_offer.dart';

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
    _remaining = _displayDuration;
    _totalDuration = _displayDuration;
    _expiryTimer = Timer(_remaining, _notifyTimeout);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining = _remaining - const Duration(seconds: 1);
      setState(() => _remaining = remaining);
      if (remaining <= Duration.zero) _notifyTimeout();
    });
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
    final pickupAddress =
        ride?.pickupAddress ?? 'موقع الراكب عند نقطة الانطلاق';
    final destinationName =
        ride?.dropoffAddress ?? 'الوجهة التي اختارها الراكب';
    final progress = _countdownProgress();

    return SizedBox(
      width: double.infinity,
      child: Material(
        color: const Color(0xFF111317),
        elevation: 24,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  textDirection: ui.TextDirection.rtl,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          key: const ValueKey('ride-offer-price'),
                          formatIqd(offer.estimatedFare ?? ride?.estimatedFare),
                          textAlign: TextAlign.right,
                          textDirection: ui.TextDirection.rtl,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 38,
                            height: 1,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'دينار',
                          textAlign: TextAlign.right,
                          textDirection: ui.TextDirection.rtl,
                          style: TextStyle(
                            color: Color(0xFFC9CDD3),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                    const Expanded(child: SizedBox(height: 1)),
                    if (widget.offerCount > 1)
                      _OfferSwitcher(
                        position: widget.offerPosition,
                        count: widget.offerCount,
                        isDisabled: widget.isResponding,
                        onPrevious: widget.onPreviousOffer,
                        onNext: widget.onNextOffer,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    return Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: constraints.maxWidth * 0.82,
                        child: Directionality(
                          textDirection: ui.TextDirection.rtl,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _TimelineRow(
                                icon: Icons.circle,
                                iconColor: AppTheme.primaryGreen,
                                label: 'الانطلاق',
                                metric:
                                    '${formatMinutes(pickupMinutes)} - $pickupDistanceText',
                                place: pickupAddress,
                                isLast: false,
                              ),
                              _TimelineRow(
                                icon: Icons.stop_rounded,
                                iconColor: Colors.white,
                                label: 'الوصول',
                                metric:
                                    '${formatMinutes(tripMinutes)} - $tripDistanceText',
                                place: destinationName,
                                isLast: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 18),
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

class _OfferSwitcher extends StatelessWidget {
  const _OfferSwitcher({
    required this.position,
    required this.count,
    required this.isDisabled,
    required this.onPrevious,
    required this.onNext,
  });

  final int position;
  final int count;
  final bool isDisabled;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('ride-offer-switcher'),
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1E23),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2B3330)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: ui.TextDirection.ltr,
        children: [
          _OfferSwitchButton(
            key: const ValueKey('ride-offer-previous'),
            icon: Icons.chevron_left_rounded,
            isDisabled: isDisabled,
            onPressed: onPrevious,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              key: const ValueKey('ride-offer-switcher-label'),
              '${formatNumber(position)} / ${formatNumber(count)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
          _OfferSwitchButton(
            key: const ValueKey('ride-offer-next'),
            icon: Icons.chevron_right_rounded,
            isDisabled: isDisabled,
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _OfferSwitchButton extends StatelessWidget {
  const _OfferSwitchButton({
    required super.key,
    required this.icon,
    required this.isDisabled,
    required this.onPressed,
  });

  final IconData icon;
  final bool isDisabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 30,
      child: IconButton(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        iconSize: 22,
        color: Colors.white,
        disabledColor: Colors.white.withValues(alpha: 0.35),
        onPressed: isDisabled ? null : onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.metric,
    required this.place,
    required this.isLast,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String metric;
  final String place;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    metric,
                    textAlign: TextAlign.right,
                    textDirection: ui.TextDirection.rtl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFF2F4F7),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    place,
                    textAlign: TextAlign.right,
                    textDirection: ui.TextDirection.rtl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFC9CDD3),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
                    ),
                  ),
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
                      : Colors.transparent,
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
                    color: const Color(0xFF4D5664),
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
              color: AppTheme.primaryGreen,
              borderRadius: BorderRadius.circular(12),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final overlayWidth = constraints.maxWidth * progress;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        width: overlayWidth,
                        decoration: const BoxDecoration(
                          color: Color(0xFF17221B),
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

String formatMinutes(int? minutes) =>
    minutes == null ? 'وقت الوصول' : '${formatNumber(minutes)} دقيقة';

String formatDistance(double km) {
  if (km < 1) {
    return '${formatNumber((km * 1000).round())} متر';
  }
  final value = km >= 10 ? km.round().toString() : km.toStringAsFixed(1);
  return '${formatNumberText(value)} كيلومتر';
}

/// تنسيق المبلغ بالدينار العراقي بأرقام عربية.
String formatIqd(double? amount) {
  if (amount == null) return 'السعر';
  return formatNumberText(
    NumberFormat.decimalPattern('ar_IQ').format(amount.round()),
  );
}

String formatNumber(num value) =>
    formatNumberText(NumberFormat.decimalPattern('ar_IQ').format(value));

String formatNumberText(String value) {
  const western = '0123456789.,';
  const eastern = '٠١٢٣٤٥٦٧٨٩٫٬';
  return value.split('').map((char) {
    final index = western.indexOf(char);
    return index == -1 ? char : eastern[index];
  }).join();
}
