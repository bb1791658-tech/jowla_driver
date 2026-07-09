import 'package:geolocator/geolocator.dart';

import '../../auth/domain/models/driver_session.dart';
import '../../rides/domain/models/ride_offer.dart';

enum HomeConnection { offline, connecting, online }

class DriverHomeState {
  const DriverHomeState({
    this.connection = HomeConnection.offline,
    this.accountStatus,
    this.pendingOffers = const [],
    this.offerVisibleUntil = const {},
    this.currentOfferIndex = 0,
    this.offerError,
    this.error,
    this.lastPosition,
    this.lastLocationSentAt,
    this.isRespondingToOffer = false,
  });

  final HomeConnection connection;
  final DriverAccountStatus? accountStatus;
  final List<RideOffer> pendingOffers;
  final Map<String, DateTime> offerVisibleUntil;
  final int currentOfferIndex;
  final String? offerError;
  final String? error;
  final Position? lastPosition;
  final DateTime? lastLocationSentAt;
  final bool isRespondingToOffer;

  bool get isOnline => connection == HomeConnection.online;
  int get offerCount => pendingOffers.length;
  int get availableOfferCount => pendingOffers.where(_isOfferAvailable).length;
  int get offerPosition => offerCount == 0 ? 0 : currentOfferIndex + 1;
  RideOffer? get activeOffer =>
      pendingOffers.isEmpty ? null : pendingOffers[currentOfferIndex];
  RideOffer? get nextAvailableOffer {
    final index = nextAvailableOfferIndex();
    return index == null ? null : pendingOffers[index];
  }

  DriverHomeState copyWith({
    HomeConnection? connection,
    DriverAccountStatus? accountStatus,
    List<RideOffer>? pendingOffers,
    Map<String, DateTime>? offerVisibleUntil,
    int? currentOfferIndex,
    String? offerError,
    String? error,
    Position? lastPosition,
    DateTime? lastLocationSentAt,
    bool? isRespondingToOffer,
    bool clearActiveOffer = false,
    bool clearError = false,
    bool clearOfferError = false,
  }) {
    final nextOffers = clearActiveOffer
        ? const <RideOffer>[]
        : pendingOffers ?? this.pendingOffers;
    final nextVisibility = clearActiveOffer
        ? const <String, DateTime>{}
        : offerVisibleUntil ?? this.offerVisibleUntil;
    final maxIndex = nextOffers.isEmpty ? 0 : nextOffers.length - 1;
    final requestedIndex = currentOfferIndex ?? this.currentOfferIndex;
    return DriverHomeState(
      connection: connection ?? this.connection,
      accountStatus: accountStatus ?? this.accountStatus,
      pendingOffers: nextOffers,
      offerVisibleUntil: nextVisibility,
      currentOfferIndex: requestedIndex.clamp(0, maxIndex).toInt(),
      offerError: clearOfferError ? null : offerError ?? this.offerError,
      error: clearError ? null : error ?? this.error,
      lastPosition: lastPosition ?? this.lastPosition,
      lastLocationSentAt: lastLocationSentAt ?? this.lastLocationSentAt,
      isRespondingToOffer: isRespondingToOffer ?? this.isRespondingToOffer,
    );
  }

  int? nextAvailableOfferIndex({bool forward = true}) {
    if (pendingOffers.length < 2) return null;
    for (var offset = 1; offset < pendingOffers.length; offset++) {
      final signedOffset = forward ? offset : -offset;
      final index =
          (currentOfferIndex + signedOffset + pendingOffers.length) %
          pendingOffers.length;
      if (_isOfferAvailable(pendingOffers[index])) return index;
    }
    return null;
  }

  bool _isOfferAvailable(RideOffer offer) {
    final visibleUntil = offerVisibleUntil[offer.offerId];
    if (visibleUntil == null) return !offer.isExpired;
    return visibleUntil.isAfter(DateTime.now());
  }
}
