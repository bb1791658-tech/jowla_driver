import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_paths.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/services/realtime_service.dart';
import '../domain/chat_message.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(
    ref.watch(apiClientProvider),
    ref.watch(realtimeServiceProvider),
  );
});

class ChatRepository {
  const ChatRepository(this._api, this._realtime);

  final ApiClient _api;
  final RealtimeService _realtime;

  Stream<ChatMessage> watchRide(String rideId) => _realtime.communicationEvents
      .where(
        (event) =>
            event.name == 'chat:message:new' &&
            event.payload['rideId']?.toString() == rideId,
      )
      .map((event) => _messageFromEnvelope(event.payload));

  Future<List<ChatMessage>> list(String rideId) async {
    try {
      final response = await _api.dio.get<Map<String, dynamic>>(
        ApiPaths.rideChatMessages(rideId),
      );
      final items = response.data?['items'];
      if (items is! List) return const [];
      return items
          .whereType<Map>()
          .map((item) => ChatMessage.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } catch (error) {
      throw ApiClient.mapError(error);
    }
  }

  Future<ChatMessage> sendText({
    required String rideId,
    required String clientMessageId,
    required String body,
  }) async {
    try {
      final response = await _api.dio.post<Map<String, dynamic>>(
        ApiPaths.rideChatMessages(rideId),
        data: {
          'clientMessageId': clientMessageId,
          'type': 'TEXT',
          'body': body,
        },
      );
      return _messageFromEnvelope(response.data ?? const {});
    } catch (error) {
      throw ApiClient.mapError(error);
    }
  }

  Future<void> markRead(String rideId) async {
    try {
      await _api.dio.post<void>(ApiPaths.rideChatRead(rideId));
    } catch (_) {
      // القراءة تحسين ثانوي ولا يجب أن تمنع عرض الرسائل.
    }
  }

  ChatMessage _messageFromEnvelope(Map<String, dynamic> envelope) {
    final value = envelope['message'];
    if (value is! Map) {
      throw const AppException('استجابة الرسالة غير مكتملة.');
    }
    final message = ChatMessage.fromJson(Map<String, dynamic>.from(value));
    if (message.id.isEmpty || message.clientMessageId.isEmpty) {
      throw const AppException('استجابة الرسالة غير مكتملة.');
    }
    return message;
  }
}
