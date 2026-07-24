import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../auth/domain/models/driver_session.dart';
import '../../driver/domain/models/driver_account.dart';
import '../../rides/domain/models/ride_offer.dart';
import '../../wallet/domain/models/driver_wallet.dart';

enum HomeConnection { offline, connecting, online }

class DriverHomeState {
  const DriverHomeState({
    this.connection = HomeConnection.offline,
    this.accountStatus,
    this.services = const [],
    this.activeService,
    this.pendingOffers = const [],
    this.offerVisibleUntil = const {},
    this.currentOfferIndex = 0,
    this.offerError,
    this.error,
    this.wallet,
    this.walletError,
    this.isWalletLoading = false,
    this.lastPosition,
    this.matchedPosition,
    this.matchedHeading,
    this.mapMatchingConfidence = 0,
    this.lastLocationSentAt,
    this.isRespondingToOffer = false,
  });

  final HomeConnection connection;
  final DriverAccountStatus? accountStatus;
  final List<DriverService> services;
  final DriverService? activeService;
  final List<RideOffer> pendingOffers;
  final Map<String, DateTime> offerVisibleUntil;
  final int currentOfferIndex;
  final String? offerError;
  final String? error;
  final DriverWallet? wallet;
  final String? walletError;
  final bool isWalletLoading;
  final Position? lastPosition;
  final LatLng? matchedPosition;
  final double? matchedHeading;
  final double mapMatchingConfidence;
  final DateTime? lastLocationSentAt;
  final bool isRespondingToOffer;

  bool get isOnline => connection == HomeConnection.online;
  bool get isMapMatched => matchedPosition != null;
  LatLng? get mapPoint {
    final matched = matchedPosition;
    if (matched != null) return matched;
    final raw = lastPosition;
    return raw == null ? null : LatLng(raw.latitude, raw.longitude);
  }

  double? get mapHeading => matchedHeading ?? lastPosition?.heading;
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
    List<DriverService>? services,
    DriverService? activeService,
    List<RideOffer>? pendingOffers,
    Map<String, DateTime>? offerVisibleUntil,
    int? currentOfferIndex,
    String? offerError,
    String? error,
    DriverWallet? wallet,
    String? walletError,
    bool? isWalletLoading,
    Position? lastPosition,
    LatLng? matchedPosition,
    double? matchedHeading,
    double? mapMatchingConfidence,
    DateTime? lastLocationSentAt,
    bool? isRespondingToOffer,
    bool clearActiveOffer = false,
    bool clearError = false,
    bool clearOfferError = false,
    bool clearWalletError = false,
    bool clearMatchedPosition = false,
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
      services: services ?? this.services,
      activeService: activeService ?? this.activeService,
      pendingOffers: nextOffers,
      offerVisibleUntil: nextVisibility,
      currentOfferIndex: requestedIndex.clamp(0, maxIndex).toInt(),
      offerError: clearOfferError ? null : offerError ?? this.offerError,
      error: clearError ? null : error ?? this.error,
      wallet: wallet ?? this.wallet,
      walletError: clearWalletError ? null : walletError ?? this.walletError,
      isWalletLoading: isWalletLoading ?? this.isWalletLoading,
      lastPosition: lastPosition ?? this.lastPosition,
      matchedPosition: clearMatchedPosition
          ? null
          : matchedPosition ?? this.matchedPosition,
      matchedHeading: clearMatchedPosition
          ? null
          : matchedHeading ?? this.matchedHeading,
      mapMatchingConfidence: clearMatchedPosition
          ? 0
          : mapMatchingConfidence ?? this.mapMatchingConfidence,
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
