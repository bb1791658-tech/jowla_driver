import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/push_registration_service.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_navigator.dart';
import '../../../core/services/realtime_service.dart';

class CommunicationNavigationBridge extends ConsumerStatefulWidget {
  const CommunicationNavigationBridge({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<CommunicationNavigationBridge> createState() =>
      _CommunicationNavigationBridgeState();
}

class _CommunicationNavigationBridgeState
    extends ConsumerState<CommunicationNavigationBridge> {
  StreamSubscription<RealtimeEvent>? _realtimeSubscription;
  StreamSubscription<Map<String, dynamic>>? _pushSubscription;
  String? _lastCallId;
  String? _lastChatMessageId;

  @override
  void initState() {
    super.initState();
    final realtime = ref.read(realtimeServiceProvider);
    _realtimeSubscription = realtime.communicationEvents
        .where(
          (event) =>
              event.name == 'call:incoming' || event.name == 'chat:message:new',
        )
        .listen((event) {
          if (event.name == 'chat:message:new') {
            _showIncomingChat(event.payload);
            return;
          }
          _handle(event.payload);
        });
    final push = ref.read(pushTokenSourceProvider);
    _pushSubscription = push.notificationOpens.listen(_handle);
    unawaited(
      push.takeInitialOpen().then((value) {
        if (value != null) _handle(value);
      }),
    );
  }

  void _handle(Map<String, dynamic> payload) {
    final type = payload['type']?.toString();
    final rideId = payload['rideId']?.toString();
    final callValue = payload['call'];
    final call = callValue is Map
        ? Map<String, dynamic>.from(callValue)
        : const <String, dynamic>{};
    final callId = payload['callId']?.toString() ?? call['id']?.toString();
    if ((type == 'incoming_call' || callId != null) &&
        rideId != null &&
        rideId.isNotEmpty &&
        callId != null &&
        callId.isNotEmpty &&
        callId != _lastCallId) {
      _lastCallId = callId;
      unawaited(
        pushAppRoute(
          Uri(
            path: '/rides/$rideId/call',
            queryParameters: {'callId': callId},
          ).toString(),
        ).whenComplete(() => _lastCallId = null),
      );
      return;
    }
    if (type == 'chat_message' && rideId != null && rideId.isNotEmpty) {
      unawaited(pushAppRoute('/rides/$rideId/chat'));
    }
  }

  void _showIncomingChat(Map<String, dynamic> payload) {
    final rideId = payload['rideId']?.toString();
    final value = payload['message'];
    if (rideId == null || rideId.isEmpty || value is! Map) return;
    final message = Map<String, dynamic>.from(value);
    if (message['senderType']?.toString().toUpperCase() != 'USER') return;
    final messageId = message['id']?.toString();
    if (messageId == null ||
        messageId.isEmpty ||
        messageId == _lastChatMessageId) {
      return;
    }
    _lastChatMessageId = messageId;
    final body = message['body']?.toString().trim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = rootScaffoldMessengerKey.currentState;
      if (messenger == null) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              body == null || body.isEmpty
                  ? 'رسالة جديدة من الراكب'
                  : 'الراكب: $body',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            action: SnackBarAction(
              label: 'فتح',
              onPressed: () => unawaited(pushAppRoute('/rides/$rideId/chat')),
            ),
          ),
        );
    });
  }

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    _pushSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
