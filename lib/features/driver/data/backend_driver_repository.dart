import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_paths.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../domain/driver_repository.dart';
import '../domain/models/driver_account.dart';

final driverRepositoryProvider = Provider<DriverRepository>(
  (ref) => BackendDriverRepository(ref.watch(apiClientProvider)),
);

class BackendDriverRepository implements DriverRepository {
  const BackendDriverRepository(this._client);

  final ApiClient _client;

  @override
  Future<DriverAccount> me() async {
    try {
      final response = await _client.dio.get<Map<String, dynamic>>(
        ApiPaths.driverProfile,
      );
      final account = DriverAccount.fromJson(response.data ?? const {});
      if (account.profile.id.isEmpty) {
        throw const AppException('استجابة ملف السائق غير مكتملة.');
      }
      return account;
    } catch (error) {
      throw ApiClient.mapError(error);
    }
  }

  @override
  Future<DriverAccount> setAvailability({
    required String driverId,
    required bool online,
  }) async {
    try {
      final response = await _client.dio.patch<Map<String, dynamic>>(
        ApiPaths.driverAvailability(driverId),
        data: {'status': online ? 'online' : 'offline'},
      );
      return DriverAccount.fromJson(response.data ?? const {});
    } catch (error) {
      throw ApiClient.mapError(error);
    }
  }

  @override
  Future<void> updateLocation({
    required String driverId,
    required double lat,
    required double lng,
    double? heading,
    double? speed,
  }) async {
    try {
      await _client.dio.put<void>(
        ApiPaths.driverLocation(driverId),
        data: {'lat': lat, 'lng': lng, 'heading': ?heading, 'speed': ?speed},
      );
    } catch (error) {
      throw ApiClient.mapError(error);
    }
  }
}
