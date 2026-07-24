import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_paths.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../domain/call_models.dart';

final callRepositoryProvider = Provider<CallRepository>(
  (ref) => CallRepository(ref.watch(apiClientProvider)),
);

class CallRepository {
  const CallRepository(this._api);

  final ApiClient _api;

  Future<CallRecord> start({
    required String rideId,
    required String clientCallId,
  }) async {
    try {
      final response = await _api.dio.post<Map<String, dynamic>>(
        ApiPaths.rideCalls(rideId),
        data: {'clientCallId': clientCallId},
      );
      return _callFromEnvelope(response.data ?? const {});
    } catch (error) {
      throw ApiClient.mapError(error);
    }
  }

  Future<CallRecord> updateStatus({
    required String callId,
    required String status,
    String? reason,
  }) async {
    try {
      final response = await _api.dio.post<Map<String, dynamic>>(
        ApiPaths.callStatus(callId),
        data: {
          'status': status,
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
      );
      return _callFromEnvelope(response.data ?? const {});
    } catch (error) {
      throw ApiClient.mapError(error);
    }
  }

  Future<List<Map<String, dynamic>>> iceServers() async {
    try {
      final response = await _api.dio.get<Map<String, dynamic>>(
        ApiPaths.callIceServers,
      );
      final values = response.data?['iceServers'];
      if (values is! List) return const [];
      return values
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList(growable: false);
    } catch (error) {
      throw ApiClient.mapError(error);
    }
  }

  CallRecord _callFromEnvelope(Map<String, dynamic> envelope) {
    final value = envelope['call'];
    if (value is! Map) {
      throw const AppException('استجابة المكالمة غير مكتملة.');
    }
    final call = CallRecord.fromJson(Map<String, dynamic>.from(value));
    if (call.id.isEmpty) {
      throw const AppException('استجابة المكالمة غير مكتملة.');
    }
    return call;
  }
}
