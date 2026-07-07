import 'dart:async';

import 'package:jowla_driver/core/services/realtime_service.dart';
import 'package:jowla_driver/core/storage/session_store.dart';
import 'package:jowla_driver/features/auth/domain/auth_repository.dart';
import 'package:jowla_driver/features/auth/domain/models/driver_session.dart';
import 'package:jowla_driver/features/driver/domain/driver_repository.dart';
import 'package:jowla_driver/features/driver/domain/models/driver_account.dart';
import 'package:jowla_driver/features/rides/domain/models/ride.dart';
import 'package:jowla_driver/features/rides/domain/models/ride_offer.dart';
import 'package:jowla_driver/features/rides/domain/ride_repository.dart';

class InMemorySecureStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class FakeRealtimeService implements RealtimeService {
  final offersController = StreamController<Map<String, dynamic>>.broadcast();
  final expirationsController =
      StreamController<Map<String, dynamic>>.broadcast();
  final rideEventsController = StreamController<RealtimeEvent>.broadcast();
  final connectionsController = StreamController<void>.broadcast();
  final sentLocations = <Map<String, double?>>[];
  var connectCalls = 0;
  var disconnectCalls = 0;
  var connected = false;

  @override
  Stream<Map<String, dynamic>> get offers => offersController.stream;

  @override
  Stream<Map<String, dynamic>> get offerExpirations =>
      expirationsController.stream;

  @override
  Stream<RealtimeEvent> get rideEvents => rideEventsController.stream;

  @override
  Stream<void> get connections => connectionsController.stream;

  @override
  bool get isConnected => connected;

  @override
  Future<void> connect() async {
    connectCalls++;
    connected = true;
  }

  @override
  void sendLocation({
    required double lat,
    required double lng,
    double? heading,
    double? speed,
  }) {
    sentLocations.add({
      'lat': lat,
      'lng': lng,
      'heading': heading,
      'speed': speed,
    });
  }

  @override
  void disconnect() {
    disconnectCalls++;
    connected = false;
  }

  @override
  void dispose() {
    offersController.close();
    expirationsController.close();
    rideEventsController.close();
    connectionsController.close();
  }
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.driver});

  DriverProfile? driver;
  OtpRequestResult otpResult =
      const OtpRequestResult(requestId: 'req-1', mockCode: '123456');
  Object? requestError;
  var logoutCalls = 0;

  @override
  Future<OtpRequestResult> requestOtp(String phone) async {
    if (requestError != null) throw requestError!;
    return otpResult;
  }

  @override
  Future<DriverProfile> verifyOtp({
    required String phone,
    required String code,
    required String platform,
  }) async {
    final profile = driver ??
        const DriverProfile(
          id: 'driver-1',
          name: 'سائق اختبار',
          phone: '+9647700000001',
          status: DriverAccountStatus.approved,
        );
    driver = profile;
    return profile;
  }

  @override
  Future<DriverProfile?> restoreSession() async => driver;

  @override
  Future<void> logout() async {
    logoutCalls++;
    driver = null;
  }
}

class FakeDriverRepository implements DriverRepository {
  FakeDriverRepository({required this.account});

  DriverAccount account;
  final availabilityChanges = <bool>[];
  final locationUpdates = <Map<String, double?>>[];

  @override
  Future<DriverAccount> me() async => account;

  @override
  Future<DriverAccount> setAvailability({
    required String driverId,
    required bool online,
  }) async {
    availabilityChanges.add(online);
    account = DriverAccount(
      profile: account.profile.copyWith(
        status: online
            ? DriverAccountStatus.online
            : DriverAccountStatus.offline,
      ),
      vehicles: account.vehicles,
      serviceNames: account.serviceNames,
    );
    return account;
  }

  @override
  Future<void> updateLocation({
    required String driverId,
    required double lat,
    required double lng,
    double? heading,
    double? speed,
  }) async {
    locationUpdates.add({'lat': lat, 'lng': lng});
  }
}

class FakeRideRepository implements RideRepository {
  Ride? current;
  List<RideOffer> offers = [];
  final accepted = <String>[];
  final rejected = <String>[];
  Object? acceptError;
  Ride Function(String rideId, RideStatus status)? transitionBuilder;

  @override
  Future<List<RideOffer>> pendingOffers() async => offers;

  @override
  Future<Ride?> currentRide() async => current;

  @override
  Future<Ride> getRide(String rideId) async {
    final ride = current;
    if (ride != null && ride.id == rideId) return ride;
    throw StateError('ride not found');
  }

  @override
  Future<Ride> acceptOffer({
    required String rideId,
    required String offerId,
  }) async {
    if (acceptError != null) throw acceptError!;
    accepted.add(offerId);
    final ride = _build(rideId, RideStatus.driverAccepted);
    current = ride;
    return ride;
  }

  @override
  Future<void> rejectOffer({
    required String rideId,
    required String offerId,
  }) async {
    rejected.add(offerId);
  }

  @override
  Future<Ride> driverArrived(String rideId) async =>
      current = _build(rideId, RideStatus.driverArrived);

  @override
  Future<Ride> startTrip(String rideId) async =>
      current = _build(rideId, RideStatus.tripStarted);

  @override
  Future<Ride> completeTrip(String rideId) async =>
      current = _build(rideId, RideStatus.completed);

  @override
  Future<Ride> cancelRide(String rideId) async =>
      current = _build(rideId, RideStatus.cancelled);

  Ride _build(String rideId, RideStatus status) {
    final builder = transitionBuilder;
    if (builder != null) return builder(rideId, status);
    return (current ?? sampleRide(id: rideId)).copyWith(status: status);
  }
}

Ride sampleRide({String id = 'ride-1', RideStatus status = RideStatus.driverAccepted}) =>
    Ride.fromJson({
      'id': id,
      'status': switch (status) {
        RideStatus.driverAccepted => 'DRIVER_ACCEPTED',
        RideStatus.driverArrived => 'DRIVER_ARRIVED',
        RideStatus.tripStarted => 'TRIP_STARTED',
        RideStatus.completed => 'COMPLETED',
        RideStatus.cancelled => 'CANCELLED',
        _ => 'SEARCHING_DRIVER',
      },
      'pickupLat': '30.9601000',
      'pickupLng': '46.9769000',
      'dropoffLat': '30.9700000',
      'dropoffLng': '46.9900000',
      'estimatedFare': '5000.00',
      'distanceKm': '3.250',
      'durationMinutes': 9,
      'currency': 'IQD',
      'user': {'id': 'user-1', 'name': 'راكب', 'phone': '+9647711111111'},
    });
