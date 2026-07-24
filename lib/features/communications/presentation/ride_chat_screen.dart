import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers.dart';
import '../../../core/utils/client_uuid.dart';
import '../../trip/application/trip_controller.dart';
import '../data/chat_repository.dart';
import '../domain/chat_message.dart';

class RideChatScreen extends ConsumerStatefulWidget {
  const RideChatScreen({required this.rideId, super.key});

  final String rideId;

  @override
  ConsumerState<RideChatScreen> createState() => _RideChatScreenState();
}

class _RideChatScreenState extends ConsumerState<RideChatScreen> {
  static const _suggestedMessages = <String>[
    'أنا في انتظارك عند نقطة الانطلاق',
    'وصلت إلى نقطة الانطلاق',
    'سأصل خلال دقائق',
  ];

  final _text = TextEditingController();
  final _focusNode = FocusNode();
  StreamSubscription<ChatMessage>? _subscription;
  List<ChatMessage>? _messages;
  Object? _error;
  var _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repository = ref.read(chatRepositoryProvider);
    _subscription = repository.watchRide(widget.rideId).listen(_merge);
    unawaited(ref.read(realtimeServiceProvider).connect().catchError((_) {}));
    try {
      final messages = await repository.list(widget.rideId);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _error = null;
      });
      unawaited(repository.markRead(widget.rideId));
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _send([String? suggestedMessage]) async {
    final body = (suggestedMessage ?? _text.text).trim();
    if (_sending || body.isEmpty || body.length > 2000) return;
    setState(() => _sending = true);
    try {
      final message = await ref
          .read(chatRepositoryProvider)
          .sendText(
            rideId: widget.rideId,
            clientMessageId: newClientUuid(),
            body: body,
          );
      _merge(message);
      _text.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _merge(ChatMessage message) {
    if (!mounted) return;
    final current = _messages ?? const <ChatMessage>[];
    if (current.any(
      (item) =>
          item.id == message.id ||
          item.clientMessageId == message.clientMessageId,
    )) {
      return;
    }
    setState(() => _messages = [...current, message]);
    unawaited(ref.read(chatRepositoryProvider).markRead(widget.rideId));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _text.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = _messages;
    final colors = Theme.of(context).colorScheme;
    final activeRide = ref.watch(tripControllerProvider).value;
    final rider = activeRide?.id == widget.rideId ? activeRide?.rider : null;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: colors.surface,
        systemNavigationBarColor: colors.surface,
      ),
      child: SafeArea(
        top: true,
        bottom: false,
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            titleSpacing: 0,
            title: _ChatPeerHeader(name: rider?.displayName ?? 'راكب جولة'),
            backgroundColor: colors.surface,
            surfaceTintColor: colors.surface,
            systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: colors.surface,
            ),
          ),
          body: Column(
            children: [
              Expanded(
                child: _error != null
                    ? Center(child: Text(_error.toString()))
                    : messages == null
                    ? const Center(child: CircularProgressIndicator())
                    : messages.isEmpty
                    ? const Center(child: Text('ابدأ المحادثة مع الراكب'))
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (context, index) => _MessageBubble(
                          message: messages[messages.length - index - 1],
                        ),
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'رسائل سريعة',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF65736D),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final message in _suggestedMessages)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  end: 8,
                                ),
                                child: ActionChip(
                                  key: ValueKey('suggested-message-$message'),
                                  avatar: const Icon(
                                    Icons.bolt_rounded,
                                    size: 17,
                                  ),
                                  label: Text(message),
                                  onPressed: _sending
                                      ? null
                                      : () => unawaited(_send(message)),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const Key('ride-chat-message-field'),
                              controller: _text,
                              focusNode: _focusNode,
                              minLines: 1,
                              maxLines: 4,
                              maxLength: 2000,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                              decoration: const InputDecoration(
                                hintText: 'اكتب رسالة…',
                                counterText: '',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: _sending ? null : _send,
                            icon: _sending
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatPeerHeader extends StatelessWidget {
  const _ChatPeerHeader({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const CircleAvatar(
          radius: 18,
          child: Icon(Icons.person_rounded, size: 20),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text('الراكب', style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.sentByDriver;
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine
              ? colors.primaryContainer
              : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.body ?? 'رسالة غير مدعومة'),
            const SizedBox(height: 3),
            Text(
              DateFormat('HH:mm').format(message.createdAt),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
