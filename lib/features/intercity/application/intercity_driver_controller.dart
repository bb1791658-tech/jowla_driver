import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../driver/data/backend_driver_repository.dart';
import '../../rides/domain/models/ride.dart';
import '../data/backend_intercity_driver_repository.dart';
import '../domain/models/intercity_offer.dart';
import '../domain/models/intercity_offer_draft.dart';

class IntercityDriverState {
  const IntercityDriverState({
    this.offers = const [],
    this.scheduledRides = const [],
    this.selectedOffer,
    this.preview,
    this.vehicleCapacity,
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
  });

  final List<IntercityTripOffer> offers;
  final List<Ride> scheduledRides;
  final IntercityTripOffer? selectedOffer;
  final IntercityOfferPreview? preview;
  final int? vehicleCapacity;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;

  List<IntercityTripOffer> get upcoming =>
      offers.where((item) => !item.status.isPast).toList(growable: false);

  List<IntercityTripOffer> get history =>
      offers.where((item) => item.status.isPast).toList(growable: false);

  IntercityDriverState copyWith({
    List<IntercityTripOffer>? offers,
    List<Ride>? scheduledRides,
    IntercityTripOffer? selectedOffer,
    IntercityOfferPreview? preview,
    int? vehicleCapacity,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    bool clearSelectedOffer = false,
    bool clearPreview = false,
    bool clearError = false,
  }) => IntercityDriverState(
    offers: offers ?? this.offers,
    scheduledRides: scheduledRides ?? this.scheduledRides,
    selectedOffer: clearSelectedOffer
        ? null
        : selectedOffer ?? this.selectedOffer,
    preview: clearPreview ? null : preview ?? this.preview,
    vehicleCapacity: vehicleCapacity ?? this.vehicleCapacity,
    isLoading: isLoading ?? this.isLoading,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    error: clearError ? null : error ?? this.error,
  );
}

final intercityDriverControllerProvider =
    NotifierProvider<IntercityDriverController, IntercityDriverState>(
      IntercityDriverController.new,
    );

class IntercityDriverController extends Notifier<IntercityDriverState> {
  StreamSubscription<dynamic>? _eventsSubscription;
  StreamSubscription<void>? _connectionsSubscription;
  Timer? _eventDebounce;
  var _initialized = false;

  @override
  IntercityDriverState build() {
    final realtime = ref.watch(realtimeServiceProvider);
    _eventsSubscription = realtime.intercityEvents.listen((_) {
      _eventDebounce?.cancel();
      _eventDebounce = Timer(
        const Duration(milliseconds: 180),
        () => unawaited(refresh(silent: true)),
      );
    });
    _connectionsSubscription = realtime.connections.listen(
      (_) => unawaited(refresh(silent: true)),
    );
    ref.onDispose(() {
      _eventsSubscription?.cancel();
      _connectionsSubscription?.cancel();
      _eventDebounce?.cancel();
    });
    if (!_initialized) {
      _initialized = true;
      Future<void>.microtask(refresh);
    }
    return const IntercityDriverState();
  }

  Future<void> refresh({bool silent = false}) async {
    if (state.isLoading) return;
    if (!silent) state = state.copyWith(isLoading: true, clearError: true);
    try {
      final repository = ref.read(intercityDriverRepositoryProvider);
      final results = await Future.wait<dynamic>([
        repository.offers(),
        repository.scheduledFullVehicleRides(),
        ref.read(driverRepositoryProvider).me(),
      ]);
      final offers = results[0] as List<IntercityTripOffer>;
      final scheduled = results[1] as List<Ride>;
      final account = results[2];
      final selectedId = state.selectedOffer?.id;
      final selected = selectedId == null
          ? null
          : offers.cast<IntercityTripOffer?>().firstWhere(
              (item) => item?.id == selectedId,
              orElse: () => null,
            );
      state = state.copyWith(
        offers: offers,
        scheduledRides: scheduled,
        selectedOffer: selected,
        clearSelectedOffer: selectedId != null && selected == null,
        vehicleCapacity: account.activeVehicle?.seatCapacity,
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<void> loadOffer(String offerId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final offer = await ref
          .read(intercityDriverRepositoryProvider)
          .offer(offerId);
      state = state.copyWith(
        selectedOffer: offer,
        offers: _replaceOffer(state.offers, offer),
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<IntercityOfferPreview?> preview(IntercityOfferDraft draft) async {
    final capacity = state.vehicleCapacity ?? 0;
    final validation = draft.validate(vehicleCapacity: capacity);
    if (validation != null) {
      state = state.copyWith(error: validation, clearPreview: true);
      return null;
    }
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final preview = await ref
          .read(intercityDriverRepositoryProvider)
          .preview(draft);
      final priceError = draft.validate(
        vehicleCapacity: capacity,
        minimumPriceDinars: preview.minimumPriceDinars,
        maximumPriceDinars: preview.maximumPriceDinars,
      );
      state = state.copyWith(
        preview: preview,
        isSubmitting: false,
        error: priceError,
        clearError: priceError == null,
      );
      return priceError == null ? preview : null;
    } catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        error: error.toString(),
        clearPreview: true,
      );
      return null;
    }
  }

  Future<IntercityTripOffer?> create(IntercityOfferDraft draft) async {
    final preview = state.preview;
    final validation = draft.validate(
      vehicleCapacity: state.vehicleCapacity,
      minimumPriceDinars: preview?.minimumPriceDinars,
      maximumPriceDinars: preview?.maximumPriceDinars,
    );
    if (validation != null) {
      state = state.copyWith(error: validation);
      return null;
    }
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final created = await ref
          .read(intercityDriverRepositoryProvider)
          .create(
            draft: draft,
            preview: preview,
            idempotencyKey: _idempotencyKey(),
          );
      state = state.copyWith(
        offers: _replaceOffer(state.offers, created),
        selectedOffer: created,
        isSubmitting: false,
        clearPreview: true,
        clearError: true,
      );
      return created;
    } catch (error) {
      state = state.copyWith(isSubmitting: false, error: error.toString());
      return null;
    }
  }

  Future<IntercityTripOffer?> update(
    IntercityOfferDraft draft,
    IntercityTripOffer current,
  ) async {
    final preview = state.preview;
    final validation = draft.validate(
      vehicleCapacity: state.vehicleCapacity ?? 0,
      minimumPriceDinars: preview?.minimumPriceDinars,
      maximumPriceDinars: preview?.maximumPriceDinars,
    );
    if (!current.canEdit ||
        preview == null ||
        preview.isExpired ||
        validation != null) {
      state = state.copyWith(
        error: !current.canEdit
            ? 'الخادم لا يسمح بتعديل هذا العرض.'
            : validation ?? 'انتهت المعاينة. أعد مراجعة التفاصيل.',
      );
      return null;
    }
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final updated = await ref
          .read(intercityDriverRepositoryProvider)
          .update(
            offerId: current.id,
            draft: draft,
            preview: preview,
            version: current.version,
          );
      state = state.copyWith(
        offers: _replaceOffer(state.offers, updated),
        selectedOffer: updated,
        isSubmitting: false,
        clearPreview: true,
        clearError: true,
      );
      return updated;
    } catch (error) {
      state = state.copyWith(isSubmitting: false, error: error.toString());
      return null;
    }
  }

  Future<bool> cancel(String offerId) => _mutate(
    () => ref.read(intercityDriverRepositoryProvider).cancel(offerId),
  );

  Future<bool> depart(String offerId) => _mutate(
    () => ref.read(intercityDriverRepositoryProvider).depart(offerId),
  );

  Future<bool> complete(String offerId) => _mutate(
    () => ref.read(intercityDriverRepositoryProvider).complete(offerId),
  );

  Future<bool> _mutate(Future<IntercityTripOffer> Function() action) async {
    if (state.isSubmitting) return false;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final offer = await action();
      state = state.copyWith(
        offers: _replaceOffer(state.offers, offer),
        selectedOffer: offer,
        isSubmitting: false,
        clearError: true,
      );
      return true;
    } catch (error) {
      state = state.copyWith(isSubmitting: false, error: error.toString());
      return false;
    }
  }

  List<IntercityTripOffer> _replaceOffer(
    List<IntercityTripOffer> values,
    IntercityTripOffer replacement,
  ) {
    final next = [
      replacement,
      ...values.where((item) => item.id != replacement.id),
    ];
    next.sort((a, b) => a.departureAt.compareTo(b.departureAt));
    return next;
  }

  String _idempotencyKey() =>
      'driver-offer-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
}
