import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/signalling_message_model.dart';

// WebRTC peer connection — audio + optional video
class WebRTCService {
  static const _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
  };

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  bool _audio = true;
  bool _video = false;

  void Function(RTCIceCandidate candidate)? onIceCandidate;
  void Function(RTCPeerConnectionState state)? onConnectionStateChange;
  void Function(MediaStream stream)? onRemoteStream;

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  Future<void> init({required bool audio, bool video = false}) async {
    _audio = audio;
    _video = video;
    _localStream = await _captureMedia();
    _peerConnection = await createPeerConnection(_iceServers);
    _bindPeerConnectionEvents();

    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }
  }

  // Rebuild peer connection after network drop (Android may kill tracks)
  Future<void> reestablish({bool force = false}) async {
    final state = _peerConnection?.connectionState;
    final needsNewPc = force ||
        _peerConnection == null ||
        state == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
        state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
        state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected;

    if (!needsNewPc) return;

    await _peerConnection?.close();
    _peerConnection = null;

    // Android releases camera/mic on failed state — always re-capture
    _localStream?.getTracks().forEach((t) => t.stop());
    await _localStream?.dispose();
    _localStream = await _captureMedia();

    _peerConnection = await createPeerConnection(_iceServers);
    _bindPeerConnectionEvents();

    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }
  }

  Future<MediaStream> _captureMedia() async {
    return navigator.mediaDevices.getUserMedia({
      'audio': _audio,
      'video': _video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 640},
              'height': {'ideal': 480},
            }
          : false,
    });
  }

  void _bindPeerConnectionEvents() {
    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
        onIceCandidate?.call(candidate);
      }
    };

    _peerConnection!.onConnectionState = (state) {
      onConnectionStateChange?.call(state);
    };

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        onRemoteStream?.call(_remoteStream!);
      }
    };
  }

  Future<Map<String, dynamic>> createOffer() async {
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    return {'sdp': offer.sdp, 'type': offer.type};
  }

  // ICE restart offer for mid-call network recovery
  Future<Map<String, dynamic>> createReconnectOffer() async {
    final offer = await _peerConnection!.createOffer({'iceRestart': true});
    await _peerConnection!.setLocalDescription(offer);
    return {'sdp': offer.sdp, 'type': offer.type};
  }

  Future<Map<String, dynamic>> createAnswer() async {
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    return {'sdp': answer.sdp, 'type': answer.type};
  }

  Future<void> setRemoteDescription(Map<String, dynamic> sdpMap) async {
    final desc = RTCSessionDescription(
      sdpMap['sdp'] as String?,
      sdpMap['type'] as String?,
    );
    await _peerConnection!.setRemoteDescription(desc);
  }

  Future<void> addIceCandidate(SignallingMessageModel candidate) async {
    if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
    final pc = _peerConnection;
    if (pc == null) {
      // ICE can arrive while peer connection is rebuilding after reconnect.
      // Ignored intentionally to prevent null-crash loop.
      return;
    }
    await pc.addCandidate(
      RTCIceCandidate(
        candidate.candidate,
        candidate.sdpMid,
        candidate.sdpMLineIndex,
      ),
    );
  }

  void setMuted(bool muted) {
    for (final track in _localStream?.getAudioTracks() ?? []) {
      track.enabled = !muted;
    }
  }

  void setCameraEnabled(bool enabled) {
    for (final track in _localStream?.getVideoTracks() ?? []) {
      track.enabled = enabled;
    }
  }

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isEmpty) return;
    await Helper.switchCamera(tracks.first);
  }

  Future<void> restartIce() async {
    await _peerConnection?.restartIce();
  }

  Future<void> hangUp() async {
    await dispose();
  }

  Future<void> dispose() async {
    _localStream?.getTracks().forEach((track) => track.stop());
    await _localStream?.dispose();
    _remoteStream?.getTracks().forEach((track) => track.stop());
    await _remoteStream?.dispose();
    await _peerConnection?.close();
    _localStream = null;
    _remoteStream = null;
    _peerConnection = null;
  }
}
