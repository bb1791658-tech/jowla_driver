import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/maps/runtime_environment.dart';
import '../../../core/providers.dart';
import '../../../core/services/road_position_matcher.dart';
import '../../../core/services/road_route_service.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/models/driver_session.dart';
import '../../driver/data/backend_driver_repository.dart';
import '../../driver/domain/models/driver_account.dart';
import '../../rides/data/backend_ride_repository.dart';
import '../../rides/domain/models/ride.dart';
import '../../rides/domain/models/ride_offer.dart';
import '../../trip/application/trip_controller.dart';
import '../../wallet/data/backend_wallet_repository.dart';
import 'driver_home_state.dart';

export 'driver_home_state.dart';

final driverHomeControllerProvider =
    NotifierProvider<DriverHomeController, DriverHomeState>(
      DriverHomeController.new,
    );

/// منطق الرئيسية:
/// - Online: PATCH /drivers/{id}/availability {status: 'online'} ثم اتصال
///   Socket ثم بث الموقع (حدث driver:location:update) ثم استعادة العروض
///   المعلقة عبر GET /rides/driver/offers.
/// - Offline: إيقاف بث الموقع (لا إرسال في وضع Offline إطلاقًا) ثم
///   PATCH {status: 'offline'}، مع إبقاء قناة الأحداث الإدارية الخفيفة.
/// - العروض من حدث ride:offer:new مع مهلة العرض من حقل expiresAt الذي
///   يحدده الخادم (driver_search_timeout_seconds = 30 ثانية افتراضيًا).
class DriverHomeController extends Notifier<DriverHomeState>
    with WidgetsBindingObserver {
  StreamSubscription<Position>? _positionsSubscription;
  StreamSubscription<Map<String, dynamic>>? _offersSubscription;
  StreamSubscription<Map<String, dynamic>>? _expirationsSubscription;
  StreamSubscription<Map<String, dynamic>>? _driverUpdatesSubscription;
  StreamSubscription<void>? _connectionsSubscription;
  Timer? _heartbeat;
  ({double lat, double lng, double? heading, double? speed})?
  _pendingLocationPersistence;
  Position? _pendingPositionForMatching;
  late RoadPositionMatcher _positionMatcher;
  var _isMatchingPosition = false;
  var _matchingGeneration = 0;
  var _isPersistingLocation = false;
  var _isRefreshingOffers = false;
  var _isRestoring = false;
  var _restored = false;
  var _disposed = false;

  @override
  DriverHomeState build() {
    _disposed = false;
    _positionMatcher = RoadPositionMatcher(ref.watch(roadRouteServiceProvider));
    WidgetsBinding.instance.addObserver(this);
    final realtime = ref.watch(realtimeServiceProvider);
    _offersSubscription = realtime.offers.listen(_handleOfferPayload);
    _expirationsSubscription = realtime.offerExpirations.listen(
      _handleOfferExpired,
    );
    _driverUpdatesSubscription = realtime.driverUpdates.listen(
      _handleDriverUpdated,
    );
    _connectionsSubscription = realtime.connections.listen(
      (_) => unawaited(_resyncAfterConnect()),
    );
    ref.listen<AsyncValue<Ride?>>(tripControllerProvider, (previous, next) {
      final previousRide = previous?.value;
      final currentRide = next.value;
      final justCompleted =
          currentRide?.status == RideStatus.completed &&
          previousRide?.status != RideStatus.completed;
      if (justCompleted) unawaited(refreshWallet());
    });
    ref.onDispose(() {
      _disposed = true;
      _matchingGeneration += 1;
      _stopLocationPublisher();
      _offersSubscription?.cancel();
      _expirationsSubscription?.cancel();
      _driverUpdatesSubscription?.cancel();
      _connectionsSubscription?.cancel();
      WidgetsBinding.instance.removeObserver(this);
    });
    if (!_restored) {
      _restored = true;
      Future<void>.microtask(_restoreFromBackend);
    }
    return const DriverHomeState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_restoreFromBackend());
    }
  }

  /// الخادم مصدر الحقيقة لحالة السائق: عند فتح التطبيق نقرأ
  /// GET /drivers/me ونستأنف وضع Online إذا كان الخادم يعتبرنا كذلك.
  Future<void> _restoreFromBackend() async {
    if (_isRestoring) return;
    final session = ref.read(authSessionProvider).value;
    if (session == null) return;
    _isRestoring = true;
    try {
      final account = await ref.read(driverRepositoryProvider).me();
      final status = account.profile.status;
      state = state.copyWith(
        accountStatus: status,
        services: account.services,
        activeService: account.activeService,
      );
      final shouldResumeWork =
          status == DriverAccountStatus.online ||
          status == DriverAccountStatus.busy ||
          status == DriverAccountStatus.onTrip;
      if (shouldResumeWork) {
        await _startOnlinePipeline(markAvailability: false);
        await ref.read(tripControllerProvider.notifier).refresh();
      } else {
        if (status?.canWork ?? false) await _ensureRealtimeConnected();
        await refreshWallet();
      }
    } catch (error) {
      state = state.copyWith(
        connection: HomeConnection.offline,
        error: error.toString(),
      );
    } finally {
      _isRestoring = false;
    }
  }

  Future<void> goOnline() async {
    if (state.isOnline || state.connection == HomeConnection.connecting) {
      return;
    }
    state = state.copyWith(
      connection: HomeConnection.connecting,
      clearError: true,
    );
    try {
      await ref.read(locationServiceProvider).ensurePermission();
      await _startOnlinePipeline(markAvailability: true);
    } catch (error) {
      state = state.copyWith(
        connection: HomeConnection.offline,
        error: error.toString(),
      );
    }
  }

  Future<void> chooseActiveService(String serviceTypeCode) async {
    final driverId = _driverId;
    if (driverId == null) return;
    try {
      final account = await ref
          .read(driverRepositoryProvider)
          .chooseActiveService(
            driverId: driverId,
            serviceTypeCode: serviceTypeCode,
          );
      state = state.copyWith(
        accountStatus: account.profile.status,
        services: account.services,
        activeService: account.activeService,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> goOffline() async {
    _stopLocationPublisher();
    final driverId = _driverId;
    try {
      if (driverId != null) {
        final account = await ref
            .read(driverRepositoryProvider)
            .setAvailability(driverId: driverId, online: false);
        state = state.copyWith(accountStatus: account.profile.status);
      }
    } catch (error) {
      state = state.copyWith(error: error.toString());
    } finally {
      // لا نقطع الـ Socket أثناء رحلة نشطة كي تستمر أحداث الرحلة.
      // نبقي الـ Socket متصلًا لاستقبال تحديثات الأدمن مثل الصورة والحالة.
      state = state.copyWith(
        connection: HomeConnection.offline,
        clearActiveOffer: true,
      );
    }
  }

  Future<void> requestCurrentLocation() async {
    if (state.lastPosition != null) return;
    try {
      final position = await ref
          .read(locationServiceProvider)
          .getCurrentPosition();
      state = state.copyWith(lastPosition: position, clearError: true);
      _queuePositionForMatching(position);
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> _startOnlinePipeline({required bool markAvailability}) async {
    final driverId = _driverId;
    if (driverId == null) {
      throw const AppException('لا توجد جلسة سائق نشطة.');
    }
    final initialPosition = await ref
        .read(locationServiceProvider)
        .getCurrentPosition();
    state = state.copyWith(lastPosition: initialPosition);
    if (markAvailability) {
      final account = await ref
          .read(driverRepositoryProvider)
          .setAvailability(driverId: driverId, online: true);
      state = state.copyWith(accountStatus: account.profile.status);
    }
    await ref.read(realtimeServiceProvider).connect();
    state = state.copyWith(connection: HomeConnection.online);
    _startLocationPublisher(initialPosition);
    await _refreshPendingOffers();
    await refreshWallet();
  }

  Future<void> _ensureRealtimeConnected() async {
    final realtime = ref.read(realtimeServiceProvider);
    if (realtime.isConnected) return;
    try {
      await realtime.connect();
    } catch (_) {
      // يبقى REST مصدر الحقيقة، وسيعاد الاتصال عند محاولة Online أو استئناف التطبيق.
    }
  }

  // ---------------------------------------------------------------- الموقع

  void _startLocationPublisher(Position initialPosition) {
    _stopLocationPublisher();
    _positionsSubscription = ref
        .read(locationServiceProvider)
        .positions()
        .listen(
          (position) {
            state = state.copyWith(lastPosition: position);
            _queuePositionForMatching(position);
          },
          onError: (Object error) {
            state = state.copyWith(
              error: 'انقطع تحديد الموقع: تحقق من تفعيل GPS.',
            );
          },
        );
    state = state.copyWith(lastPosition: initialPosition);
    _queuePositionForMatching(initialPosition);
    _heartbeat = Timer.periodic(AppConfig.locationHeartbeat, (_) {
      final position = state.lastPosition;
      final lastSent = state.lastLocationSentAt;
      if (position == null) return;
      if (lastSent != null &&
          DateTime.now().difference(lastSent) < AppConfig.locationHeartbeat) {
        return;
      }
      _publishLocation(
        position,
        mapPoint: state.mapPoint,
        mapHeading: state.mapHeading,
      );
    });
  }

  void _stopLocationPublisher() {
    _positionsSubscription?.cancel();
    _positionsSubscription = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _matchingGeneration += 1;
    _pendingPositionForMatching = null;
    _positionMatcher.reset();
    _pendingLocationPersistence = null;
  }

  void _queuePositionForMatching(Position position) {
    state = state.copyWith(lastPosition: position);
    if (isFlutterTestEnvironment || position.accuracy > 100) {
      state = state.copyWith(clearMatchedPosition: true);
      _publishLocation(position);
      return;
    }
    _pendingPositionForMatching = position;
    if (!_isMatchingPosition) unawaited(_matchLatestPositions());
  }

  Future<void> _matchLatestPositions() async {
    _isMatchingPosition = true;
    final generation = _matchingGeneration;
    try {
      while (!_disposed && generation == _matchingGeneration) {
        final position = _pendingPositionForMatching;
        if (position == null) break;
        _pendingPositionForMatching = null;
        MatchedRoadPosition result;
        try {
          result = await _positionMatcher
              .match(
                rawPoint: LatLng(position.latitude, position.longitude),
                recordedAt: position.timestamp,
                accuracyMeters: position.accuracy,
                rawHeadingDegrees: position.heading,
              )
              .timeout(const Duration(seconds: 4));
        } catch (_) {
          result = MatchedRoadPosition(
            point: LatLng(position.latitude, position.longitude),
            headingDegrees: position.heading,
            isMatched: false,
            confidence: 0,
            snapDistanceMeters: 0,
          );
        }
        if (_disposed || generation != _matchingGeneration) return;
        if (_pendingPositionForMatching != null) continue;
        state = result.isMatched
            ? state.copyWith(
                matchedPosition: result.point,
                matchedHeading: result.headingDegrees,
                mapMatchingConfidence: result.confidence,
              )
            : state.copyWith(clearMatchedPosition: true);
        _publishLocation(
          position,
          mapPoint: result.point,
          mapHeading: result.headingDegrees,
        );
      }
    } finally {
      _isMatchingPosition = false;
      if (!_disposed &&
          _pendingPositionForMatching != null &&
          generation == _matchingGeneration) {
        unawaited(_matchLatestPositions());
      }
    }
  }

  void _publishLocation(
    Position position, {
    LatLng? mapPoint,
    double? mapHeading,
  }) {
    // ممنوع الإرسال في وضع Offline.
    if (_positionsSubscription == null) return;
    final realtime = ref.read(realtimeServiceProvider);
    // UpdateDriverLocationDto: heading بين 0 و360 وspeed أكبر أو تساوي 0.
    final heading = mapHeading ?? position.heading;
    final speed = position.speed;
    final normalizedHeading = heading.isFinite && heading >= 0 && heading <= 360
        ? heading
        : null;
    final normalizedSpeed = speed.isFinite && speed >= 0 ? speed : null;
    if (realtime.isConnected) {
      realtime.sendLocation(
        lat: mapPoint?.latitude ?? position.latitude,
        lng: mapPoint?.longitude ?? position.longitude,
        heading: normalizedHeading,
        speed: normalizedSpeed,
      );
    }
    _pendingLocationPersistence = (
      lat: mapPoint?.latitude ?? position.latitude,
      lng: mapPoint?.longitude ?? position.longitude,
      heading: normalizedHeading,
      speed: normalizedSpeed,
    );
    if (!_isPersistingLocation) unawaited(_persistLatestLocation());
  }

  Future<void> _persistLatestLocation() async {
    _isPersistingLocation = true;
    try {
      while (!_disposed && _positionsSubscription != null) {
        final pending = _pendingLocationPersistence;
        if (pending == null) break;
        _pendingLocationPersistence = null;
        final driverId = _driverId;
        if (driverId == null) break;
        try {
          await ref
              .read(driverRepositoryProvider)
              .updateLocation(
                driverId: driverId,
                lat: pending.lat,
                lng: pending.lng,
                heading: pending.heading,
                speed: pending.speed,
              );
          if (!_disposed && _positionsSubscription != null) {
            state = state.copyWith(
              lastLocationSentAt: DateTime.now(),
              clearError: true,
            );
          }
        } catch (_) {
          if (!_disposed &&
              _positionsSubscription != null &&
              !ref.read(realtimeServiceProvider).isConnected) {
            state = state.copyWith(
              error: 'تعذر تحديث موقع العمل. تحقق من الاتصال بالإنترنت.',
            );
          }
        }
      }
    } finally {
      _isPersistingLocation = false;
      if (!_disposed &&
          _pendingLocationPersistence != null &&
          _positionsSubscription != null) {
        unawaited(_persistLatestLocation());
      }
    }
  }

  // --------------------------------------------------------------- العروض

  Future<void> _resyncAfterConnect() async {
    if (!state.isOnline) return;
    final position = state.lastPosition;
    if (position != null) {
      _publishLocation(
        position,
        mapPoint: state.mapPoint,
        mapHeading: state.mapHeading,
      );
    }
    await _resyncAvailableWork();
  }

  Future<void> _resyncAvailableWork() async {
    await _refreshPendingOffers();
    await refreshWallet();
    await ref.read(tripControllerProvider.notifier).refresh();
  }

  Future<void> refreshWallet() async {
    if (ref.read(authSessionProvider).value == null) return;
    state = state.copyWith(isWalletLoading: true, clearWalletError: true);
    try {
      final wallet = await ref.read(walletRepositoryProvider).currentWallet();
      state = state.copyWith(
        wallet: wallet,
        isWalletLoading: false,
        clearWalletError: true,
      );
    } catch (error) {
      state = state.copyWith(
        isWalletLoading: false,
        walletError: error.toString(),
      );
    }
  }

  Future<void> _refreshPendingOffers() async {
    if (!state.isOnline || _isRefreshingOffers) return;
    _isRefreshingOffers = true;
    try {
      final offers = await ref.read(rideRepositoryProvider).pendingOffers();
      // GET /rides/driver/offers يفلتر في الخادم حسب expiresAt > now.
      // لذلك لا نستخدم ساعة الجهاز هنا كي لا نسقط عرضًا صالحًا بسبب clock skew.
      state = state.copyWith(
        pendingOffers: _reconcileRestOffers(state.pendingOffers, offers),
        offerVisibleUntil: _mergeOfferVisibility(offers, useLocalWindow: true),
        clearOfferError: true,
      );
    } catch (_) {
      // فشل الاستعادة لا يوقف وضع Online؛ سيُعاد عند الاتصال التالي.
    } finally {
      _isRefreshingOffers = false;
    }
  }

  List<RideOffer> _reconcileRestOffers(
    List<RideOffer> current,
    List<RideOffer> restOffers,
  ) {
    // REST فارغ لا يعني دائمًا أن حدث Socket السابق غير صالح؛ قد يحدث سباق
    // قصير بين إنشاء العرض، بث Socket، وقراءة القائمة. الحذف النهائي يأتي من
    // ride:offer:expired أو timeout المحلي المبني على نافذة الظهور.
    return _mergeOffers(current, restOffers);
  }

  void _handleOfferPayload(Map<String, dynamic> payload) {
    final RideOffer offer;
    try {
      offer = RideOffer.fromSocketPayload(payload);
    } on FormatException {
      return;
    }
    state = state.copyWith(
      pendingOffers: _mergeOffers(state.pendingOffers, [offer]),
      offerVisibleUntil: _mergeOfferVisibility([offer], useLocalWindow: true),
      clearOfferError: true,
    );
    unawaited(_enrichOffer(offer));
  }

  /// حمولة Socket لا تتضمن الوجهة والعناوين؛ نكمل التفاصيل من
  /// GET /rides/{id} (مسموح للسائق صاحب العرض وفق rides.service.findOne).
  Future<void> _enrichOffer(RideOffer offer) async {
    try {
      final ride = await ref.read(rideRepositoryProvider).getRide(offer.rideId);
      final offers = state.pendingOffers;
      final index = offers.indexWhere((item) => item.offerId == offer.offerId);
      if (index != -1) {
        final nextOffers = [...offers];
        nextOffers[index] = nextOffers[index].withRide(ride);
        state = state.copyWith(pendingOffers: nextOffers);
      }
    } catch (_) {
      // تبقى بيانات الحمولة الأساسية (النقطة والأجرة والمهلة) كافية للقرار.
    }
  }

  void _handleOfferExpired(Map<String, dynamic> payload) {
    final offerId = payload['offerId']?.toString();
    if (offerId == null || !_hasOffer(offerId)) return;
    final reason = payload['reason']?.toString();
    final nextOffers = _removeOffer(offerId);
    state = state.copyWith(
      pendingOffers: nextOffers,
      offerError: switch (reason) {
        'accepted_by_other_driver' => 'قبل سائق آخر هذه الرحلة.',
        'ride_cancelled' => 'ألغى الراكب هذه الرحلة.',
        'server_timeout' => 'انتهت مهلة العرض.',
        'driver_rejected' => null,
        _ => 'انتهى هذا العرض.',
      },
    );
  }

  void _handleDriverUpdated(Map<String, dynamic> payload) {
    final account = DriverAccount.fromJson(payload);
    final status = account.profile.status;
    ref.read(authSessionProvider.notifier).profileUpdated(account.profile);
    state = state.copyWith(
      accountStatus: status,
      services: account.services,
      activeService: account.activeService,
      clearError: true,
    );
    if (status == DriverAccountStatus.online ||
        status == DriverAccountStatus.busy ||
        status == DriverAccountStatus.onTrip) {
      if (!state.isOnline) {
        unawaited(_startOnlinePipeline(markAvailability: false));
      }
      return;
    }
    if (status == null ||
        !status.canWork ||
        status == DriverAccountStatus.offline) {
      _stopLocationPublisher();
      state = state.copyWith(
        connection: HomeConnection.offline,
        clearActiveOffer: true,
      );
    }
  }

  /// انتهاء المهلة محليًا (وصلنا إلى expiresAt دون حدث من الخادم).
  void offerTimedOut(String offerId) {
    if (!_hasOffer(offerId)) return;
    state = state.copyWith(
      pendingOffers: _removeOffer(offerId),
      offerError: 'انتهت مهلة العرض.',
    );
  }

  Future<bool> acceptOffer() async {
    final offer = state.activeOffer;
    if (offer == null || state.isRespondingToOffer) return false;
    state = state.copyWith(isRespondingToOffer: true, clearOfferError: true);
    try {
      final ride = await ref
          .read(rideRepositoryProvider)
          .acceptOffer(rideId: offer.rideId, offerId: offer.offerId);
      ref
          .read(tripControllerProvider.notifier)
          .rideAssigned(ride.withMergedRider(offer.ride?.rider));
      final position = state.lastPosition;
      if (position != null) _publishLocation(position);
      state = state.copyWith(
        isRespondingToOffer: false,
        clearActiveOffer: true,
      );
      return true;
    } catch (error) {
      state = state.copyWith(
        isRespondingToOffer: false,
        pendingOffers: _removeOffer(offer.offerId),
        offerError: error.toString(),
      );
      return false;
    }
  }

  Future<void> rejectOffer() async {
    final offer = state.activeOffer;
    if (offer == null || state.isRespondingToOffer) return;
    state = state.copyWith(
      isRespondingToOffer: true,
      pendingOffers: _removeOffer(offer.offerId),
    );
    try {
      await ref
          .read(rideRepositoryProvider)
          .rejectOffer(rideId: offer.rideId, offerId: offer.offerId);
    } catch (_) {
      // الرفض المحلي كافٍ؛ الخادم سيُنهي العرض بمهلته إن لم يصل الرفض.
    } finally {
      state = state.copyWith(isRespondingToOffer: false);
    }
  }

  void showNextOffer() {
    if (state.offerCount < 2 || state.isRespondingToOffer) return;
    state = state.copyWith(
      currentOfferIndex: (state.currentOfferIndex + 1) % state.offerCount,
    );
  }

  void showPreviousOffer() {
    if (state.offerCount < 2 || state.isRespondingToOffer) return;
    state = state.copyWith(
      currentOfferIndex:
          (state.currentOfferIndex - 1 + state.offerCount) % state.offerCount,
    );
  }

  void showOffer(String offerId) {
    if (state.isRespondingToOffer) return;
    final index = state.pendingOffers.indexWhere(
      (item) => item.offerId == offerId,
    );
    if (index < 0) return;
    state = state.copyWith(currentOfferIndex: index);
  }

  List<RideOffer> _mergeOffers(
    List<RideOffer> current,
    List<RideOffer> incoming,
  ) {
    final next = [...current.where(_isOfferStillVisible)];
    for (final offer in incoming) {
      final index = next.indexWhere((item) => item.offerId == offer.offerId);
      if (index == -1) {
        next.add(offer);
      } else {
        next[index] = offer;
      }
    }
    return next;
  }

  bool _isOfferStillVisible(RideOffer offer) {
    final visibleUntil = state.offerVisibleUntil[offer.offerId];
    if (visibleUntil != null) return visibleUntil.isAfter(DateTime.now());
    return !offer.isExpired;
  }

  Map<String, DateTime> _mergeOfferVisibility(
    List<RideOffer> offers, {
    bool useLocalWindow = false,
  }) {
    final next = Map<String, DateTime>.of(state.offerVisibleUntil);
    final now = DateTime.now();
    for (final offer in offers) {
      next.putIfAbsent(
        offer.offerId,
        () => useLocalWindow
            ? now.add(const Duration(seconds: 30))
            : offer.expiresAt,
      );
    }
    return next;
  }

  bool _hasOffer(String offerId) =>
      state.pendingOffers.any((offer) => offer.offerId == offerId);

  List<RideOffer> _removeOffer(String offerId) => state.pendingOffers
      .where((offer) => offer.offerId != offerId)
      .toList(growable: false);

  String? get _driverId => ref.read(authSessionProvider).value?.id;
}
