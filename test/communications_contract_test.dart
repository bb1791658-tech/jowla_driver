import 'package:flutter_test/flutter_test.dart';
import 'package:jowla_driver/core/constants/api_paths.dart';
import 'package:jowla_driver/core/utils/client_uuid.dart';
import 'package:jowla_driver/features/communications/domain/call_models.dart';
import 'package:jowla_driver/features/communications/domain/chat_message.dart';

void main() {
  group('communications API contract', () {
    test('builds the versioned backend-relative paths', () {
      expect(
        ApiPaths.rideChatMessages('ride-1'),
        '/rides/ride-1/chat/messages',
      );
      expect(ApiPaths.rideChatRead('ride-1'), '/rides/ride-1/chat/read');
      expect(ApiPaths.rideCalls('ride-1'), '/rides/ride-1/calls');
      expect(ApiPaths.callStatus('call-1'), '/calls/call-1/status');
      expect(ApiPaths.callIceServers, '/calls/ice-servers');
    });

    test('uses RFC 4122 version 4 identifiers for safe retries', () {
      final first = newClientUuid();
      final second = newClientUuid();

      expect(first, isNot(second));
      expect(
        first,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test('normalizes backend chat and call values', () {
      final message = ChatMessage.fromJson({
        'id': 'message-1',
        'clientMessageId': 'client-1',
        'senderType': 'driver',
        'senderId': 'driver-1',
        'type': 'text',
        'body': 'أنا في الطريق',
        'createdAt': '2026-07-24T06:00:00.000Z',
        'readAt': '2026-07-24T06:01:00.000Z',
      });
      final call = CallRecord.fromJson({
        'id': 'call-1',
        'rideId': 'ride-1',
        'status': 'answered',
      });

      expect(message.sentByDriver, isTrue);
      expect(message.type, 'TEXT');
      expect(message.createdAt.toUtc(), DateTime.utc(2026, 7, 24, 6));
      expect(message.readAt?.toUtc(), DateTime.utc(2026, 7, 24, 6, 1));
      expect(call.status, 'ANSWERED');
    });
  });
}
