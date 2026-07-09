import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/models/driver_session.dart';
import '../../driver/data/backend_driver_repository.dart';
import '../../rides/data/backend_ride_repository.dart';
import '../../rides/domain/models/ride.dart';
import '../../rides/domain/models/ride_offer.dart';
import '../../trip/application/trip_controller.dart';
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
///   PATCH {status: 'offline'} ثم قطع Socket.
/// - العروض من حدث ride:offer:new مع مهلة العرض من حقل expiresAt الذي
///   يحدده الخادم (driver_search_timeout_seconds = 30 ثانية افتراضيًا).
class DriverHomeController extends Notifier<DriverHomeState> {
  StreamSubscription<Position>? _positionsSubscription;
  StreamSubscription<Map<String, dynamic>>? _offersSubscription;
  StreamSubscription<Map<String, dynamic>>? _expirationsSubscription;
  StreamSubscription<void>? _connectionsSubscription;
  Timer? _heartbeat;
  var _restored = false;

  @override
  DriverHomeState build() {
    final realtime = ref.watch(realtimeServiceProvider);
    _offersSubscription = realtime.offers.listen(_handleOfferPayload);
    _expirationsSubscription = realtime.offerExpirations.listen(
      _handleOfferExpired,
    );
    _connectionsSubscription = realtime.connections.listen(
      (_) => unawaited(_resyncAfterConnect()),
    );
    ref.onDispose(() {
      _positionsSubscription?.cancel();
      _offersSubscription?.cancel();
      _expirationsSubscription?.cancel();
      _connectionsSubscription?.cancel();
      _heartbeat?.cancel();
    });
    if (!_restored) {
      _restored = true;
      Future<void>.microtask(_restoreFromBackend);
    }
    return const DriverHomeState();
  }

  /// الخادم مصدر الحقيقة لحالة السائق: عند فتح التطبيق نقرأ
  /// GET /drivers/me ونستأنف وضع Online إذا كان الخادم يعتبرنا كذلك.
  Future<void> _restoreFromBackend() async {
    final session = ref.read(authSessionProvider).valueOrNull;
    if (session == null) return;
    if (session.id == AppConfig.devDriverId) {
      state = state.copyWith(accountStatus: DriverAccountStatus.approved);
      return;
    }
    try {
      final account = await ref.read(driverRepositoryProvider).me();
      final status = account.profile.status;
      state = state.copyWith(accountStatus: status);
      if (status == DriverAccountStatus.online ||
          status == DriverAccountStatus.busy ||
          status == DriverAccountStatus.onTrip) {
        await _startOnlinePipeline(markAvailability: false);
      }
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> goOnline() async {
    if (state.isOnline || state.connection == HomeConnection.connecting) {
      return;
    }
    if (_driverId == AppConfig.devDriverId) {
      state = state.copyWith(
        error: 'وضع التطوير يعرض الواجهة فقط. شغّل Backend للاتصال بالرحلات.',
      );
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
      final activeRide = ref.read(tripControllerProvider).valueOrNull;
      if (activeRide == null || activeRide.status.isFinished) {
        ref.read(realtimeServiceProvider).disconnect();
      }
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
    _startLocationPublisher(initialPosition);
    state = state.copyWith(connection: HomeConnection.online);
    await _refreshPendingOffers();
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
            _publishLocation(position);
          },
          onError: (Object error) {
            state = state.copyWith(
              error: 'انقطع تحديد الموقع: تحقق من تفعيل GPS.',
            );
          },
        );
    state = state.copyWith(lastPosition: initialPosition);
    _publishLocation(initialPosition);
    _heartbeat = Timer.periodic(AppConfig.locationHeartbeat, (_) {
      final position = state.lastPosition;
      final lastSent = state.lastLocationSentAt;
      if (position == null) return;
      if (lastSent != null &&
          DateTime.now().difference(lastSent) < AppConfig.locationHeartbeat) {
        return;
      }
      _publishLocation(position);
    });
  }

  void _stopLocationPublisher() {
    _positionsSubscription?.cancel();
    _positionsSubscription = null;
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  void _publishLocation(Position position) {
    // ممنوع الإرسال في وضع Offline.
    if (_positionsSubscription == null) return;
    final realtime = ref.read(realtimeServiceProvider);
    if (!realtime.isConnected) return;
    // UpdateDriverLocationDto: heading بين 0 و360 وspeed أكبر أو تساوي 0.
    final heading = position.heading;
    final speed = position.speed;
    realtime.sendLocation(
      lat: position.latitude,
      lng: position.longitude,
      heading: heading.isFinite && heading >= 0 && heading <= 360
          ? heading
          : null,
      speed: speed.isFinite && speed >= 0 ? speed : null,
    );
    state = state.copyWith(lastLocationSentAt: DateTime.now());
  }

  // --------------------------------------------------------------- العروض

  Future<void> _resyncAfterConnect() async {
    if (!state.isOnline) return;
    await _refreshPendingOffers();
    await ref.read(tripControllerProvider.notifier).refresh();
  }

  Future<void> _refreshPendingOffers() async {
    try {
      final offers = await ref.read(rideRepositoryProvider).pendingOffers();
      final freshOffers = offers.where((offer) => !offer.isExpired).toList();
      if (freshOffers.isNotEmpty) {
        state = state.copyWith(
          pendingOffers: _mergeOffers(state.pendingOffers, freshOffers),
          clearOfferError: true,
        );
      }
    } catch (_) {
      // فشل الاستعادة لا يوقف وضع Online؛ سيُعاد عند الاتصال التالي.
    }
  }

  void _handleOfferPayload(Map<String, dynamic> payload) {
    final RideOffer offer;
    try {
      offer = RideOffer.fromSocketPayload(payload);
    } on FormatException {
      return;
    }
    if (offer.isExpired) return;
    state = state.copyWith(
      pendingOffers: _mergeOffers(state.pendingOffers, [offer]),
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
          .rideAssigned(ride.copyWith(rider: offer.ride?.rider));
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

  List<RideOffer> _mergeOffers(
    List<RideOffer> current,
    List<RideOffer> incoming,
  ) {
    final next = [...current.where((offer) => !offer.isExpired)];
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

  bool _hasOffer(String offerId) =>
      state.pendingOffers.any((offer) => offer.offerId == offerId);

  List<RideOffer> _removeOffer(String offerId) => state.pendingOffers
      .where((offer) => offer.offerId != offerId)
      .toList(growable: false);

  String? get _driverId => ref.read(authSessionProvider).valueOrNull?.id;
}
