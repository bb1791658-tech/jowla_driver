import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_paths.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../domain/models/ride.dart';
import '../domain/models/ride_offer.dart';
import '../domain/ride_repository.dart';

final rideRepositoryProvider = Provider<RideRepository>(
  (ref) => BackendRideRepository(ref.watch(apiClientProvider)),
);

class BackendRideRepository implements RideRepository {
  const BackendRideRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<RideOffer>> pendingOffers() async {
    try {
      final response = await _client.dio.get<List<dynamic>>(
        ApiPaths.driverOffers,
      );
      final items = response.data ?? const [];
      final offers = <RideOffer>[];
      for (final item in items) {
        if (item is! Map) continue;
        try {
          offers.add(RideOffer.fromRestOffer(Map<String, dynamic>.from(item)));
        } on FormatException {
          // عنصر غير مكتمل لا يجب أن يمنع عرض بقية العروض.
        }
      }
      return offers;
    } catch (error) {
      throw ApiClient.mapError(error);
    }
  }

  @override
  Future<Ride?> currentRide() async {
    try {
      final response = await _client.dio.get<dynamic>(
        ApiPaths.driverCurrentRide,
      );
      final data = response.data;
      if (data is! Map || data.isEmpty) return null;
      return Ride.fromJson(Map<String, dynamic>.from(data));
    } on FormatException {
      throw const AppException('استجابة الرحلة الحالية غير مكتملة.');
    } catch (error) {
      throw ApiClient.mapError(error);
    }
  }

  @override
  Future<Ride> getRide(String rideId) =>
      _rideCall(() => _client.dio.get(ApiPaths.ride(rideId)));

  @override
  Future<Ride> acceptOffer({required String rideId, required String offerId}) =>
      _rideCall(() => _client.dio.post(ApiPaths.acceptOffer(rideId, offerId)));

  @override
  Future<void> rejectOffer({
    required String rideId,
    required String offerId,
  }) async {
    try {
      await _client.dio.post<void>(ApiPaths.rejectOffer(rideId, offerId));
    } catch (error) {
      throw ApiClient.mapError(error);
    }
  }

  @override
  Future<Ride> driverArrived(String rideId) =>
      _rideCall(() => _client.dio.post(ApiPaths.driverArrived(rideId)));

  @override
  Future<Ride> startTrip(String rideId) =>
      _rideCall(() => _client.dio.post(ApiPaths.startRide(rideId)));

  @override
  Future<Ride> pauseTrip(String rideId) =>
      _rideCall(() => _client.dio.post(ApiPaths.pauseRide(rideId)));

  @override
  Future<Ride> resumeTrip(String rideId) =>
      _rideCall(() => _client.dio.post(ApiPaths.resumeRide(rideId)));

  @override
  Future<Ride> completeTrip(String rideId) =>
      _rideCall(() => _client.dio.post(ApiPaths.completeRide(rideId)));

  @override
  Future<Ride> cancelRide(String rideId) =>
      _rideCall(() => _client.dio.post(ApiPaths.cancelRide(rideId)));

  Future<Ride> _rideCall(Future<Response<dynamic>> Function() request) async {
    try {
      final response = await request();
      final data = response.data;
      if (data is! Map) {
        throw const AppException('استجابة الرحلة غير مكتملة.');
      }
      return Ride.fromJson(Map<String, dynamic>.from(data));
    } on FormatException {
      throw const AppException('استجابة الرحلة غير مكتملة.');
    } catch (error) {
      throw ApiClient.mapError(error);
    }
  }
}
