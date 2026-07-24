import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/services/realtime_service.dart';
import '../../../core/utils/client_uuid.dart';
import '../data/call_repository.dart';
import '../domain/call_models.dart';

class VoiceCallSession {
  VoiceCallSession(this._repository, this._realtime, {required this.rideId});

  final CallRepository _repository;
  final RealtimeService _realtime;
  final String rideId;
  final _states = StreamController<VoiceCallState>.broadcast();
  final _pendingCandidates = <RTCIceCandidate>[];
  StreamSubscription<RealtimeEvent>? _eventsSubscription;
  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  String? _callId;
  var _outgoing = false;
  var _remoteDescriptionReady = false;
  var _offerSent = false;
  var _closed = false;
  var _state = const VoiceCallState(phase: VoiceCallPhase.preparing);

  Stream<VoiceCallState> get states => _states.stream;
  VoiceCallState get current => _state;

  Future<void> startOutgoing() async {
    _outgoing = true;
    _emit(const VoiceCallState(phase: VoiceCallPhase.preparing));
    try {
      await _prepareRealtime();
      await _preparePeer();
      final call = await _repository.start(
        rideId: rideId,
        clientCallId: newClientUuid(),
      );
      _callId = call.id;
      _emit(VoiceCallState(phase: VoiceCallPhase.ringing, callId: call.id));
    } catch (error) {
      await _fail(error);
    }
  }

  Future<void> prepareIncoming(String callId) async {
    _callId = callId;
    _outgoing = false;
    _emit(VoiceCallState(phase: VoiceCallPhase.incoming, callId: callId));
    try {
      await _prepareRealtime();
    } catch (error) {
      await _fail(error);
    }
  }

  Future<void> acceptIncoming() async {
    final callId = _callId;
    if (callId == null || _closed) return;
    _emit(_state.copyWith(phase: VoiceCallPhase.preparing));
    try {
      await _preparePeer();
      await _repository.updateStatus(callId: callId, status: 'ANSWERED');
      _emit(_state.copyWith(phase: VoiceCallPhase.connecting));
    } catch (error) {
      await _fail(error);
    }
  }

  Future<void> declineIncoming() async {
    final callId = _callId;
    if (callId != null) {
      await _repository
          .updateStatus(callId: callId, status: 'DECLINED')
          .catchError(
            (_) => CallRecord(id: callId, rideId: rideId, status: 'DECLINED'),
          );
    }
    await _close(VoiceCallPhase.ended);
  }

  Future<void> end() async {
    if (_closed) return;
    final callId = _callId;
    if (callId != null) {
      final status = switch (_state.phase) {
        VoiceCallPhase.incoming => 'DECLINED',
        VoiceCallPhase.ringing => 'CANCELLED',
        _ => 'ENDED',
      };
      await _repository
          .updateStatus(callId: callId, status: status)
          .catchError(
            (_) => CallRecord(id: callId, rideId: rideId, status: status),
          );
    }
    await _close(VoiceCallPhase.ended);
  }

  Future<void> toggleMute() async {
    final muted = !_state.muted;
    for (final track in _localStream?.getAudioTracks() ?? const []) {
      track.enabled = !muted;
    }
    _emit(_state.copyWith(muted: muted));
  }

  Future<void> toggleSpeaker() async {
    final enabled = !_state.speakerEnabled;
    await Helper.setSpeakerphoneOn(enabled);
    _emit(_state.copyWith(speakerEnabled: enabled));
  }

  Future<void> _prepareRealtime() async {
    _eventsSubscription ??= _realtime.communicationEvents.listen(_handleEvent);
    await _realtime.connect();
  }

  Future<void> _preparePeer() async {
    if (_peer != null) return;
    final servers = await _repository.iceServers();
    final peer = await createPeerConnection({
      'iceServers': servers,
      'sdpSemantics': 'unified-plan',
    });
    peer.onIceCandidate = (candidate) {
      final callId = _callId;
      if (callId == null || candidate.candidate == null) return;
      _realtime.sendCallSignal(
        callId: callId,
        kind: 'ice',
        payload: Map<String, dynamic>.from(candidate.toMap() as Map),
      );
    };
    peer.onConnectionState = (connectionState) {
      if (connectionState ==
          RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _emit(_state.copyWith(phase: VoiceCallPhase.connected));
      } else if (connectionState ==
              RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          connectionState ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        unawaited(_fail('تعذر استمرار الاتصال الصوتي.'));
      }
    };
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });
    for (final track in stream.getAudioTracks()) {
      await peer.addTrack(track, stream);
    }
    _peer = peer;
    _localStream = stream;
  }

  Future<void> _handleEvent(RealtimeEvent event) async {
    if (_closed) return;
    if (event.name == 'call:state') {
      final call = event.payload['call'];
      if (call is! Map || call['id']?.toString() != _callId) return;
      final status = call['status']?.toString().toUpperCase();
      if (status == 'ANSWERED' && _outgoing) {
        await _sendOffer();
      } else if ({
        'DECLINED',
        'CANCELLED',
        'FAILED',
        'MISSED',
        'TIMEOUT',
        'ENDED',
      }.contains(status)) {
        await _close(VoiceCallPhase.ended);
      }
      return;
    }
    if (event.name != 'call:signal' ||
        event.payload['callId']?.toString() != _callId) {
      return;
    }
    final kind = event.payload['kind']?.toString();
    final value = event.payload['payload'];
    if (value is! Map) return;
    final payload = Map<String, dynamic>.from(value);
    if (kind == 'offer' && !_outgoing) {
      await _receiveOffer(payload);
    } else if (kind == 'answer' && _outgoing) {
      await _setRemoteDescription(payload);
    } else if (kind == 'ice') {
      await _receiveCandidate(payload);
    }
  }

  Future<void> _sendOffer() async {
    if (_offerSent || _peer == null || _callId == null) return;
    _offerSent = true;
    _emit(_state.copyWith(phase: VoiceCallPhase.connecting));
    final offer = await _peer!.createOffer({'offerToReceiveAudio': true});
    await _peer!.setLocalDescription(offer);
    _realtime.sendCallSignal(
      callId: _callId!,
      kind: 'offer',
      payload: Map<String, dynamic>.from(offer.toMap() as Map),
    );
  }

  Future<void> _receiveOffer(Map<String, dynamic> payload) async {
    await _setRemoteDescription(payload);
    final answer = await _peer!.createAnswer({'offerToReceiveAudio': true});
    await _peer!.setLocalDescription(answer);
    _realtime.sendCallSignal(
      callId: _callId!,
      kind: 'answer',
      payload: Map<String, dynamic>.from(answer.toMap() as Map),
    );
  }

  Future<void> _setRemoteDescription(Map<String, dynamic> payload) async {
    final peer = _peer;
    final sdp = payload['sdp']?.toString();
    final type = payload['type']?.toString();
    if (peer == null || sdp == null || type == null) return;
    await peer.setRemoteDescription(RTCSessionDescription(sdp, type));
    _remoteDescriptionReady = true;
    for (final candidate in _pendingCandidates) {
      await peer.addCandidate(candidate);
    }
    _pendingCandidates.clear();
  }

  Future<void> _receiveCandidate(Map<String, dynamic> payload) async {
    final candidateText = payload['candidate']?.toString();
    if (candidateText == null || candidateText.isEmpty) return;
    final candidate = RTCIceCandidate(
      candidateText,
      payload['sdpMid']?.toString(),
      payload['sdpMLineIndex'] is num
          ? (payload['sdpMLineIndex'] as num).toInt()
          : null,
    );
    if (!_remoteDescriptionReady || _peer == null) {
      _pendingCandidates.add(candidate);
      return;
    }
    await _peer!.addCandidate(candidate);
  }

  Future<void> _fail(Object error) async {
    if (_closed) return;
    final callId = _callId;
    if (callId != null) {
      await _repository
          .updateStatus(
            callId: callId,
            status: 'FAILED',
            reason: error.toString(),
          )
          .catchError(
            (_) => CallRecord(id: callId, rideId: rideId, status: 'FAILED'),
          );
    }
    _emit(
      VoiceCallState(
        phase: VoiceCallPhase.failed,
        callId: callId,
        message: error.toString(),
      ),
    );
    await _releaseMedia();
  }

  void _emit(VoiceCallState next) {
    if (_closed) return;
    _state = next;
    _states.add(next);
  }

  Future<void> _close(VoiceCallPhase phase) async {
    if (_closed) return;
    _emit(_state.copyWith(phase: phase));
    _closed = true;
    await _releaseMedia();
  }

  Future<void> _releaseMedia() async {
    await _eventsSubscription?.cancel();
    _eventsSubscription = null;
    for (final track in _localStream?.getTracks() ?? const []) {
      await track.stop();
    }
    await _localStream?.dispose();
    _localStream = null;
    await _peer?.close();
    await _peer?.dispose();
    _peer = null;
    await Helper.setSpeakerphoneOn(false).catchError((_) {});
  }

  Future<void> dispose() async {
    if (!_closed) await _close(VoiceCallPhase.ended);
    await _states.close();
  }
}
