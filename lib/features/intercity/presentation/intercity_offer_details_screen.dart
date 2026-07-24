import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../rides/presentation/ride_formatters.dart';
import '../application/intercity_driver_controller.dart';
import '../domain/models/intercity_offer.dart';

class IntercityOfferDetailsScreen extends ConsumerStatefulWidget {
  const IntercityOfferDetailsScreen({super.key, required this.offerId});

  final String offerId;

  @override
  ConsumerState<IntercityOfferDetailsScreen> createState() =>
      _IntercityOfferDetailsScreenState();
}

class _IntercityOfferDetailsScreenState
    extends ConsumerState<IntercityOfferDetailsScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref
          .read(intercityDriverControllerProvider.notifier)
          .loadOffer(widget.offerId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(intercityDriverControllerProvider);
    final offer = state.selectedOffer?.id == widget.offerId
        ? state.selectedOffer
        : state.offers.cast<IntercityTripOffer?>().firstWhere(
            (item) => item?.id == widget.offerId,
            orElse: () => null,
          );
    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل عرض الرحلة'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: state.isLoading
                ? null
                : () => ref
                      .read(intercityDriverControllerProvider.notifier)
                      .loadOffer(widget.offerId),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: offer == null
          ? _MissingOffer(state: state, offerId: widget.offerId)
          : RefreshIndicator(
              onRefresh: () => ref
                  .read(intercityDriverControllerProvider.notifier)
                  .loadOffer(widget.offerId),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (state.error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(state.error!),
                      ),
                    ),
                  _Overview(offer: offer),
                  const SizedBox(height: 12),
                  _MoneySummary(offer: offer),
                  const SizedBox(height: 12),
                  Text(
                    'الحجوزات المؤكدة (${offer.confirmedBookingCount})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (offer.bookings.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('لا توجد حجوزات مؤكدة حتى الآن.'),
                      ),
                    )
                  else
                    for (final booking in offer.bookings)
                      _BookingCard(booking: booking),
                  const SizedBox(height: 16),
                  _OfferActions(offer: offer, isBusy: state.isSubmitting),
                  const SizedBox(height: 28),
                ],
              ),
            ),
    );
  }
}

class _MissingOffer extends ConsumerWidget {
  const _MissingOffer({required this.state, required this.offerId});

  final IntercityDriverState state;
  final String offerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: state.isLoading
          ? const CircularProgressIndicator()
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 48),
                const SizedBox(height: 12),
                Text(state.error ?? 'لم يعد العرض متاحًا.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref
                      .read(intercityDriverControllerProvider.notifier)
                      .loadOffer(offerId),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
    ),
  );
}

class _Overview extends StatelessWidget {
  const _Overview({required this.offer});

  final IntercityTripOffer offer;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${offer.originGovernorate.arabicName} ← ${offer.destinationGovernorate.arabicName}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Chip(label: Text(offer.status.arabicLabel)),
            ],
          ),
          const Divider(),
          _row(Icons.trip_origin_rounded, 'التجمع', offer.pickupAddress),
          _row(Icons.location_on_rounded, 'الوصول', offer.dropoffAddress),
          _row(
            Icons.schedule_rounded,
            'المغادرة',
            DateFormat(
              'EEEE d MMMM، h:mm a',
              'ar_IQ',
            ).format(offer.departureAt),
          ),
          _row(
            Icons.event_seat_rounded,
            'المقاعد',
            '${offer.availableSeats} متبقي • ${offer.bookedSeats} محجوز • ${offer.totalSeats} كلي',
          ),
          _row(
            Icons.payments_outlined,
            'سعر المقعد',
            formatIqd(offer.pricePerSeatDinars.toDouble()),
          ),
        ],
      ),
    ),
  );

  Widget _row(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        SizedBox(width: 72, child: Text(label)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _MoneySummary extends StatelessWidget {
  const _MoneySummary({required this.offer});

  final IntercityTripOffer offer;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 24,
        runSpacing: 12,
        children: [
          _Money(
            label: 'المتوقع عند الامتلاء',
            value: offer.expectedGrossDinars == null
                ? 'بانتظار الخادم'
                : formatIqd(offer.expectedGrossDinars!.toDouble()),
          ),
          _Money(
            label: 'المبلغ المستحق',
            value: offer.dueAmountDinars == null
                ? 'بانتظار الخادم'
                : formatIqd(offer.dueAmountDinars!.toDouble()),
          ),
        ],
      ),
    ),
  );
}

class _Money extends StatelessWidget {
  const _Money({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
    ],
  );
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking});
  final IntercitySeatBooking booking;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
      title: Text(booking.passenger?.displayName ?? 'راكب جولة'),
      subtitle: Text(
        'الحجز ${booking.id}\n${booking.seatCount} مقعد • ${formatIqd(booking.totalPriceDinars.toDouble())} • نقدًا\n'
        '${booking.cancelUntil == null ? 'الإلغاء حسب سياسة الخادم' : 'يسمح بالإلغاء حتى ${DateFormat('d/M، h:mm a', 'ar_IQ').format(booking.cancelUntil!)}'}',
      ),
      isThreeLine: true,
      trailing: Chip(label: Text(booking.status)),
    ),
  );
}

class _OfferActions extends ConsumerWidget {
  const _OfferActions({required this.offer, required this.isBusy});
  final IntercityTripOffer offer;
  final bool isBusy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(intercityDriverControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (offer.canDepart)
          FilledButton.icon(
            onPressed: isBusy ? null : () => controller.depart(offer.id),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('بدء الرحلة'),
          ),
        if (offer.canEdit)
          OutlinedButton.icon(
            onPressed: isBusy
                ? null
                : () => context.push('/intercity/offers/${offer.id}/edit'),
            icon: const Icon(Icons.edit_rounded),
            label: const Text('تعديل العرض'),
          ),
        if (offer.canComplete)
          FilledButton.icon(
            onPressed: isBusy ? null : () => controller.complete(offer.id),
            icon: const Icon(Icons.check_circle_rounded),
            label: const Text('إكمال الرحلة'),
          ),
        if (offer.canCancel)
          OutlinedButton.icon(
            onPressed: isBusy
                ? null
                : () => _confirmCancel(context, controller, offer),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('إلغاء العرض'),
          ),
      ],
    );
  }

  Future<void> _confirmCancel(
    BuildContext context,
    IntercityDriverController controller,
    IntercityTripOffer offer,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد إلغاء العرض'),
        content: Text(
          'سيتأثر ${offer.confirmedBookingCount} حجز مؤكد. سيبلّغ الخادم الركاب ويطبق سياسة الإلغاء.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إرسال طلب الإلغاء'),
          ),
        ],
      ),
    );
    if (confirmed == true) unawaited(controller.cancel(offer.id));
  }
}
