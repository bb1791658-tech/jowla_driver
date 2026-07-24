import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../rides/presentation/ride_formatters.dart';
import '../../rides/domain/models/ride_offer.dart';
import '../../home/application/driver_home_controller.dart';
import '../application/intercity_driver_controller.dart';
import '../domain/models/intercity_offer.dart';

class IntercityOffersScreen extends ConsumerWidget {
  const IntercityOffersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(intercityDriverControllerProvider);
    final fullVehicleRequests = ref
        .watch(driverHomeControllerProvider)
        .pendingOffers
        .where((item) => item.ride?.isIntercityFullVehicle == true)
        .toList(growable: false);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('بين المحافظات'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'القادمة'),
              Tab(text: 'السابقة'),
            ],
          ),
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
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/intercity/create'),
          icon: const Icon(Icons.add_road_rounded),
          label: const Text('إنشاء رحلة'),
        ),
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(
              child: _FullVehicleRequests(
                requests: fullVehicleRequests,
                onPressed: (offerId) {
                  ref
                      .read(driverHomeControllerProvider.notifier)
                      .showOffer(offerId);
                  context.go('/home');
                },
              ),
            ),
            SliverToBoxAdapter(
              child: _ScheduledLink(
                count: state.scheduledRides.length,
                onPressed: () => context.push('/intercity/scheduled'),
              ),
            ),
            if (state.error != null)
              SliverToBoxAdapter(
                child: Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.error_outline_rounded),
                    title: Text(state.error!),
                    trailing: TextButton(
                      onPressed: () => ref
                          .read(intercityDriverControllerProvider.notifier)
                          .refresh(),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ),
                ),
              ),
          ],
          body: state.isLoading && state.offers.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  children: [
                    _OfferList(
                      offers: state.upcoming,
                      onRefresh: () => ref
                          .read(intercityDriverControllerProvider.notifier)
                          .refresh(),
                    ),
                    _OfferList(
                      offers: state.history,
                      onRefresh: () => ref
                          .read(intercityDriverControllerProvider.notifier)
                          .refresh(),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _FullVehicleRequests extends StatelessWidget {
  const _FullVehicleRequests({required this.requests, required this.onPressed});

  final List<RideOffer> requests;
  final ValueChanged<String> onPressed;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: ExpansionTile(
      leading: const Icon(Icons.local_taxi_rounded),
      title: const Text('طلبات السيارة الكاملة'),
      subtitle: Text(
        requests.isEmpty
            ? 'لا توجد طلبات فورية الآن'
            : '${requests.length} طلب بانتظار الرد',
      ),
      children: [
        for (final request in requests)
          ListTile(
            title: Text(request.ride?.dropoffAddress ?? 'رحلة بين المحافظات'),
            subtitle: Text(
              request.estimatedFare == null
                  ? 'السعر المثبت يظهر في الطلب'
                  : formatIqd(request.estimatedFare),
            ),
            trailing: const Icon(Icons.chevron_left_rounded),
            onTap: () => onPressed(request.offerId),
          ),
      ],
    ),
  );
}

class _ScheduledLink extends StatelessWidget {
  const _ScheduledLink({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: ListTile(
      leading: const Icon(Icons.event_available_rounded),
      title: const Text('طلبات السيارة الكاملة المجدولة'),
      subtitle: Text(count == 0 ? 'لا توجد رحلات مؤكدة' : '$count رحلة مؤكدة'),
      trailing: const Icon(Icons.chevron_left_rounded),
      onTap: onPressed,
    ),
  );
}

class _OfferList extends StatelessWidget {
  const _OfferList({required this.offers, required this.onRefresh});

  final List<IntercityTripOffer> offers;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (offers.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.route_outlined, size: 56),
              SizedBox(height: 12),
              Text('لا توجد عروض في هذا القسم'),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        itemCount: offers.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _OfferCard(offer: offers[index]),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer});

  final IntercityTripOffer offer;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('/intercity/offers/${offer.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 8,
              children: [
                Text(
                  '${offer.originGovernorate.arabicName} ← ${offer.destinationGovernorate.arabicName}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Chip(label: Text(offer.status.arabicLabel)),
              ],
            ),
            Text(
              '${offer.pickupAddress} ← ${offer.dropoffAddress}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _Metric(
                  icon: Icons.schedule_rounded,
                  text: DateFormat(
                    'EEE d MMM، h:mm a',
                    'ar_IQ',
                  ).format(offer.departureAt),
                ),
                _Metric(
                  icon: Icons.event_seat_rounded,
                  text: '${offer.availableSeats} متبقي من ${offer.totalSeats}',
                ),
                _Metric(
                  icon: Icons.payments_outlined,
                  text:
                      '${formatIqd(offer.pricePerSeatDinars.toDouble())} للمقعد',
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [Icon(icon, size: 18), const SizedBox(width: 4), Text(text)],
  );
}
