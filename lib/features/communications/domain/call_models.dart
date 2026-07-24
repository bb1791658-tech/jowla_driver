enum VoiceCallPhase {
  incoming,
  preparing,
  ringing,
  connecting,
  connected,
  ended,
  failed,
}

class CallRecord {
  const CallRecord({
    required this.id,
    required this.rideId,
    required this.status,
  });

  factory CallRecord.fromJson(Map<String, dynamic> json) => CallRecord(
    id: json['id']?.toString() ?? '',
    rideId: json['rideId']?.toString() ?? '',
    status: json['status']?.toString().toUpperCase() ?? '',
  );

  final String id;
  final String rideId;
  final String status;
}

class VoiceCallState {
  const VoiceCallState({
    required this.phase,
    this.callId,
    this.muted = false,
    this.speakerEnabled = false,
    this.message,
  });

  final VoiceCallPhase phase;
  final String? callId;
  final bool muted;
  final bool speakerEnabled;
  final String? message;

  VoiceCallState copyWith({
    VoiceCallPhase? phase,
    String? callId,
    bool? muted,
    bool? speakerEnabled,
    String? message,
  }) => VoiceCallState(
    phase: phase ?? this.phase,
    callId: callId ?? this.callId,
    muted: muted ?? this.muted,
    speakerEnabled: speakerEnabled ?? this.speakerEnabled,
    message: message ?? this.message,
  );
}
