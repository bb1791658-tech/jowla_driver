import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../rides/domain/models/ride.dart';
import '../../rides/presentation/ride_formatters.dart';
import '../../trip/application/trip_controller.dart';
import '../application/intercity_driver_controller.dart';

class ScheduledIntercityRidesScreen extends ConsumerWidget {
  const ScheduledIntercityRidesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(intercityDriverControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('الرحلات المجدولة'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: state.isLoading
                ? null
                : () => ref
                      .read(intercityDriverControllerProvider.notifier)
                      .refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: state.isLoading && state.scheduledRides.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : state.scheduledRides.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.event_busy_rounded, size: 56),
                    const SizedBox(height: 12),
                    const Text('لا توجد رحلات سيارة كاملة مجدولة.'),
                    if (state.error != null) ...[
                      const SizedBox(height: 8),
                      Text(state.error!, textAlign: TextAlign.center),
                    ],
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () => ref
                  .read(intercityDriverControllerProvider.notifier)
                  .refresh(),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: state.scheduledRides.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) =>
                    _ScheduledRideCard(ride: state.scheduledRides[index]),
              ),
            ),
    );
  }
}

class _ScheduledRideCard extends ConsumerWidget {
  const _ScheduledRideCard({required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduledAt = ride.scheduledAt;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.directions_car_filled_rounded),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'سيارة كاملة بين المحافظات',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Chip(label: Text(ride.status.arabicLabel)),
              ],
            ),
            Text(ride.pickupAddress ?? 'نقطة الانطلاق'),
            const Icon(Icons.arrow_downward_rounded, size: 18),
            Text(ride.dropoffAddress ?? 'نقطة الوصول'),
            const Divider(),
            if (scheduledAt != null)
              Text(
                'المغادرة: ${DateFormat('EEEE d MMMM، h:mm a', 'ar_IQ').format(scheduledAt)}\n${_remainingLabel(scheduledAt)}',
              ),
            if (ride.distanceKm != null)
              Text('المسافة: ${ride.distanceKm!.toStringAsFixed(1)} كم'),
            if (ride.durationMinutes != null)
              Text('المدة: ${ride.durationMinutes} دقيقة'),
            if (ride.estimatedFare != null)
              Text('السعر المثبت: ${formatIqd(ride.estimatedFare!)}'),
            if (ride.quoteId != null) Text('مرجع التسعير: ${ride.quoteId}'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: !ride.canStart
                  ? null
                  : () async {
                      final current = await ref
                          .read(tripControllerProvider.notifier)
                          .refresh();
                      if (current?.id == ride.id && context.mounted) {
                        context.push('/trip');
                      }
                    },
              child: Text(
                ride.canStart
                    ? 'فتح الرحلة في الوقت المسموح'
                    : 'بانتظار وقت البدء من الخادم',
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _remainingLabel(DateTime scheduledAt) {
    final remaining = scheduledAt.difference(DateTime.now());
    if (remaining.isNegative) return 'حان موعد المغادرة';
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    return 'متبقي $hours ساعة و$minutes دقيقة';
  }
}
