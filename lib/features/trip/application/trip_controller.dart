import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/services/realtime_service.dart';
import '../../rides/data/backend_ride_repository.dart';
import '../../rides/domain/models/ride.dart';
import '../../rides/domain/ride_repository.dart';

/// حالة الرحلة النشطة للسائق. المصدر الوحيد للحقيقة هو Backend:
/// - الاستعادة عبر GET /rides/driver/current.
/// - التحديثات اللحظية عبر أحداث Socket الموجهة لغرفة السائق.
/// - كل انتقال حالة يتم عبر REST ويُعتمد رد الخادم فقط.
final tripControllerProvider = AsyncNotifierProvider<TripController, Ride?>(
  TripController.new,
);

class TripController extends AsyncNotifier<Ride?> {
  StreamSubscription<RealtimeEvent>? _eventsSubscription;
  StreamSubscription<void>? _reconnectSubscription;

  @override
  Future<Ride?> build() async {
    final realtime = ref.watch(realtimeServiceProvider);
    _eventsSubscription = realtime.rideEvents.listen(_handleRideEvent);
    _reconnectSubscription = realtime.connections.listen(
      (_) => unawaited(refresh()),
    );
    ref.onDispose(() {
      _eventsSubscription?.cancel();
      _reconnectSubscription?.cancel();
    });
    final cached = await ref.read(sessionStoreProvider).readActiveRide();
    if (cached != null) {
      unawaited(refresh());
      return cached;
    }
    return _loadCurrentRide();
  }

  /// يستدعى بعد قبول عرض: رد accept هو الرحلة المسندة.
  void rideAssigned(Ride ride) {
    state = AsyncData(ride);
    unawaited(_persistRide(ride));
  }

  Future<void> refresh() async {
    final result = await AsyncValue.guard(_loadCurrentRide);
    if (result.hasError) return;
    final refreshed = result.value;
    final current = state.valueOrNull;
    // GET /rides/driver/current يرجع الرحلات النشطة فقط؛ إذا كانت لدينا
    // رحلة منتهية معروضة للملخص فلا نمحوها بالتحديث الفارغ.
    if (refreshed == null && current != null && current.status.isFinished) {
      return;
    }
    if (refreshed != null || current == null || !current.status.isFinished) {
      final next = refreshed?.copyWith(rider: current?.rider);
      state = AsyncData(next);
      await _persistRide(next);
    }
  }

  Future<bool> markArrived() =>
      _transition((repo, id) => repo.driverArrived(id));

  Future<bool> startTrip() => _transition((repo, id) => repo.startTrip(id));

  Future<bool> completeTrip() =>
      _transition((repo, id) => repo.completeTrip(id));

  Future<bool> cancelRide() => _transition((repo, id) => repo.cancelRide(id));

  Future<void> clear() async {
    state = const AsyncData(null);
    await ref.read(sessionStoreProvider).clearActiveRide();
  }

  Future<bool> _transition(
    Future<Ride> Function(RideRepository repo, String rideId) action,
  ) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    state = const AsyncLoading<Ride?>().copyWithPrevious(state);
    final result = await AsyncValue.guard(
      () => action(ref.read(rideRepositoryProvider), current.id),
    );
    if (result.hasError) {
      state = AsyncError<Ride?>(
        result.error!,
        result.stackTrace!,
      ).copyWithPrevious(AsyncData(current));
      return false;
    }
    final next = result.requireValue.copyWith(rider: current.rider);
    state = AsyncData(next);
    await _persistRide(next);
    return true;
  }

  void _handleRideEvent(RealtimeEvent event) {
    final current = state.valueOrNull;
    if (current == null) return;
    final payload = event.payload;
    final rideId = (payload['rideId'] ?? payload['id'] ?? '').toString();
    if (rideId.isNotEmpty && rideId != current.id) return;
    try {
      final ride = Ride.fromJson(payload);
      final next = ride.copyWith(rider: current.rider);
      state = AsyncData(next);
      unawaited(_persistRide(next));
    } on FormatException {
      // حمولة مختصرة مثل {rideId, status} — نطبق الحالة فقط.
      final status = rideStatusFromBackend(payload['status']?.toString());
      if (status != null) {
        final next = current.copyWith(status: status);
        state = AsyncData(next);
        unawaited(_persistRide(next));
      }
    }
  }

  Future<Ride?> _loadCurrentRide() async {
    final ride = await ref.read(rideRepositoryProvider).currentRide();
    await _persistRide(ride);
    return ride;
  }

  Future<void> _persistRide(Ride? ride) {
    final store = ref.read(sessionStoreProvider);
    if (ride == null || !ride.status.isActiveForDriver) {
      return store.clearActiveRide();
    }
    return store.saveActiveRide(ride);
  }
}
