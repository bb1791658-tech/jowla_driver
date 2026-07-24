import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../application/voice_call_session.dart';
import '../data/call_repository.dart';
import '../domain/call_models.dart';

class VoiceCallScreen extends ConsumerStatefulWidget {
  const VoiceCallScreen({required this.rideId, this.incomingCallId, super.key});

  final String rideId;
  final String? incomingCallId;

  @override
  ConsumerState<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends ConsumerState<VoiceCallScreen> {
  VoiceCallSession? _session;
  StreamSubscription<VoiceCallState>? _subscription;
  var _state = const VoiceCallState(phase: VoiceCallPhase.preparing);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final session = VoiceCallSession(
      ref.read(callRepositoryProvider),
      ref.read(realtimeServiceProvider),
      rideId: widget.rideId,
    );
    _session = session;
    _subscription = session.states.listen((state) {
      if (!mounted) return;
      setState(() => _state = state);
      if (state.phase == VoiceCallPhase.ended) {
        Future<void>.delayed(const Duration(milliseconds: 500), () {
          if (mounted) Navigator.of(context).maybePop();
        });
      }
    });
    final incomingCallId = widget.incomingCallId;
    if (incomingCallId == null) {
      await session.startOutgoing();
    } else {
      await session.prepareIncoming(incomingCallId);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    unawaited(_session?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final incoming = _state.phase == VoiceCallPhase.incoming;
    return PopScope(
      canPop: _state.phase == VoiceCallPhase.ended,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_session?.end());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF151820),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                const Spacer(),
                const CircleAvatar(
                  radius: 54,
                  child: Icon(Icons.person_rounded, size: 58),
                ),
                const SizedBox(height: 24),
                const Text(
                  'مكالمة جولة الصوتية',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _phaseLabel(_state),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const Spacer(),
                if (incoming)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _CallButton(
                        label: 'رفض',
                        icon: Icons.call_end_rounded,
                        color: Colors.red,
                        onPressed: () => _session?.declineIncoming(),
                      ),
                      _CallButton(
                        label: 'رد',
                        icon: Icons.call_rounded,
                        color: Colors.green,
                        onPressed: () => _session?.acceptIncoming(),
                      ),
                    ],
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _CallButton(
                        label: _state.muted ? 'تشغيل الصوت' : 'كتم',
                        icon: _state.muted ? Icons.mic_off : Icons.mic,
                        color: Colors.white24,
                        onPressed: () => _session?.toggleMute(),
                      ),
                      _CallButton(
                        label: 'إنهاء',
                        icon: Icons.call_end_rounded,
                        color: Colors.red,
                        onPressed: () => _session?.end(),
                      ),
                      _CallButton(
                        label: 'مكبر',
                        icon: _state.speakerEnabled
                            ? Icons.volume_up_rounded
                            : Icons.volume_down_rounded,
                        color: Colors.white24,
                        onPressed: () => _session?.toggleSpeaker(),
                      ),
                    ],
                  ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _phaseLabel(VoiceCallState state) => switch (state.phase) {
    VoiceCallPhase.incoming => 'مكالمة واردة مرتبطة بالرحلة',
    VoiceCallPhase.preparing => 'جاري تجهيز الاتصال الآمن…',
    VoiceCallPhase.ringing => 'جاري الاتصال…',
    VoiceCallPhase.connecting => 'جاري توصيل الصوت…',
    VoiceCallPhase.connected => 'متصل',
    VoiceCallPhase.ended => 'انتهت المكالمة',
    VoiceCallPhase.failed => state.message ?? 'تعذر الاتصال',
  };
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IconButton.filled(
          style: IconButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            minimumSize: const Size.square(62),
          ),
          onPressed: onPressed,
          icon: Icon(icon),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}
