import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../config/locator.dart';
import '../../../../data/models/call_document_model.dart';
import '../../../../data/models/call_state_model.dart';
import '../../../../data/models/signalling_message_model.dart';
import '../../../../data/models/user_model.dart';
import '../../../../data/repositories/presence_repository.dart';
import '../../../../data/repositories/signalling_repository.dart';
import '../../../../data/services/webrtc_service.dart';
import '../../../../utils/constant.dart';
import '../../../../utils/local_storage.dart';
import '../../../base/base_cubit.dart';
import '../state/call_state.dart';

// Call lifecycle + WebRTC logic
class CallCubit extends BaseCubit<CallUiState> {
  CallCubit({
    required UserModel peer,
    required bool isOutgoing,
    required this.isVideoCall,
    this.existingCallId,
    this.existingOffer,
  })  : _peer = peer,
        _isOutgoing = isOutgoing,
        _webrtc = WebRTCService(),
        super(CallUiState(isVideoCall: isVideoCall)) {
    _signallingRepo = locator<SignallingRepository>();
  }

  final UserModel _peer;
  final bool _isOutgoing;
  final bool isVideoCall;
  final String? existingCallId;
  final Map<String, dynamic>? existingOffer;

  late final SignallingRepository _signallingRepo;
  final WebRTCService _webrtc;

  WebRTCService get webrtc => _webrtc;

  final Set<String> _handledIceIds = {};
  bool _answerHandled = false;
  bool _connected = false;
  bool _callTerminated = false; // true after hang-up or terminal end — blocks reconnect
  final List<SignallingMessageModel> _pendingIce = [];
  StreamSubscription<CallDocumentModel?>? _callSub;
  StreamSubscription<SignallingMessageModel>? _iceSub;
  Timer? _durationTimer;
  Timer? _ringTimeout;
  Timer? _reconnectTimer;
  Timer? _iceRecoveryTimer;
  Timer? _offlineCheckTimer;

  String? _callId;
  String get _localUserId => LocalStorage.deviceId;

  Future<void> start() async {
    _setupWebRtcCallbacks();
    try {
      await _webrtc.init(audio: true, video: isVideoCall);
    } catch (_) {
      _emitFailed('Microphone/camera unavailable');
      return;
    }

    if (_isOutgoing) {
      await _startOutgoingCall();
    } else {
      await _startIncomingCall();
    }
  }

  void _setupWebRtcCallbacks() {
    _webrtc.onIceCandidate = (candidate) {
      final message = SignallingMessageModel(
        type: SignallingType.ice,
        candidate: candidate.candidate,
        sdpMid: candidate.sdpMid,
        sdpMLineIndex: candidate.sdpMLineIndex,
        fromUserId: _localUserId,
      );
      final callId = _callId;
      if (callId == null) {
        _pendingIce.add(message);
        return;
      }
      _signallingRepo.sendIceCandidate(callId: callId, candidate: message);
    };

    _webrtc.onConnectionStateChange = (connectionState) {
      if (connectionState ==
          RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        if (state.isReconnecting) {
          _onReconnected();
        } else {
          _onConnected();
        }
      } else if (connectionState ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          connectionState ==
              RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        // Only reconnect on network loss — not when peer hung up
        if (_connected && !_callTerminated) {
          unawaited(_enterReconnecting());
        }
      }
    };

    _webrtc.onRemoteStream = (_) {
      emit(state.copyWith(hasRemoteVideo: true));
    };
  }

  Future<void> _startOutgoingCall() async {
    // Block call if callee went offline before ringing
    final presenceRepo = locator<PresenceRepository>();
    final peer = await presenceRepo.getUser(_peer.deviceId);
    if (peer == null || !presenceRepo.isUserCurrentlyOnline(peer)) {
      _emitFailed('User is offline');
      return;
    }

    emit(state.copyWith(statusMessage: 'Ringing…'));

    try {
      final offer = await _webrtc.createOffer();
      _callId = await _signallingRepo.createCall(
        callerId: _localUserId,
        calleeId: _peer.deviceId,
        callerName: LocalStorage.displayName ?? 'Caller',
        offer: offer,
        isVideo: isVideoCall,
      );
    } catch (_) {
      _emitFailed('Network error');
      return;
    }

    for (final ice in _pendingIce) {
      await _signallingRepo.sendIceCandidate(callId: _callId!, candidate: ice);
    }
    _pendingIce.clear();

    _emitCallState(CallStatus.ringing, 'Ringing…');
    _listenToCall(_callId!);
    _listenToIce(_callId!);
    _startOfflineCheck();

    _ringTimeout = Timer(const Duration(seconds: 30), () {
      if (state.call?.status == CallStatus.ringing) {
        _emitFailed('No answer');
        _finalizeCall('ended');
      }
    });
  }

  // Poll callee presence while ringing — fail fast if they go offline
  void _startOfflineCheck() {
    _offlineCheckTimer?.cancel();
    _offlineCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (state.call?.status != CallStatus.ringing) {
        _offlineCheckTimer?.cancel();
        return;
      }
      final presenceRepo = locator<PresenceRepository>();
      final peer = await presenceRepo.getUser(_peer.deviceId);
      if (peer == null || !presenceRepo.isUserCurrentlyOnline(peer)) {
        _offlineCheckTimer?.cancel();
        _ringTimeout?.cancel();
        _emitFailed('User is offline');
        _finalizeCall('ended');
      }
    });
  }

  // Stop reconnect timers and hide banner
  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _iceRecoveryTimer?.cancel();
    if (state.isReconnecting) {
      emit(state.copyWith(isReconnecting: false));
    }
  }

  // Peer hung up or call ended remotely — end immediately, no reconnect
  Future<void> _handleRemoteCallEnd(String firestoreStatus) async {
    if (_callTerminated) return;
    _callTerminated = true;
    _connected = false;
    _cancelReconnect();
    _ringTimeout?.cancel();
    _offlineCheckTimer?.cancel();

    if (firestoreStatus == 'declined') {
      _emitCallState(CallStatus.declined, 'Call declined');
    } else {
      _emitCallState(CallStatus.ended, 'Call ended');
    }
    await _cleanup();
  }

  // 30s grace window + ICE recovery — only when network drops, not on hang-up
  Future<void> _enterReconnecting() async {
    if (!_connected || state.isReconnecting || _callTerminated) return;

    // Peer may have ended call — check Firestore before showing reconnect banner
    final callId = _callId;
    if (callId != null) {
      try {
        final doc = await _signallingRepo.getCall(callId);
        if (doc != null &&
            (doc.status == 'ended' || doc.status == 'declined')) {
          await _handleRemoteCallEnd(doc.status);
          return;
        }
      } catch (_) {
        // Firestore unreachable — treat as network loss and try reconnect
      }
    }

    if (_callTerminated || !_connected) return;

    emit(state.copyWith(
      isReconnecting: true,
      statusMessage: 'Reconnecting…',
    ));

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      const Duration(seconds: AppConstants.callReconnectGraceSeconds),
      () {
        if (state.isReconnecting && !_callTerminated) {
          _failConnection('Connection lost');
        }
      },
    );

    _startIceRecovery();
  }

  // Retry ICE while waiting — helps auto-reconnect when data is turned back on
  void _startIceRecovery() {
    _iceRecoveryTimer?.cancel();
    _attemptIceRecovery();
    _iceRecoveryTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!state.isReconnecting) {
        _iceRecoveryTimer?.cancel();
        return;
      }
      _attemptIceRecovery();
    });
  }

  Future<void> _attemptIceRecovery() async {
    try {
      await _webrtc.restartIce();
    } catch (_) {
      // Network still down — keep retrying until grace timer expires
    }
  }

  // Network restored within 30s — resume call UI and timer
  void _onReconnected() {
    _reconnectTimer?.cancel();
    _iceRecoveryTimer?.cancel();
    if (_callId != null) {
      _signallingRepo.updateCallStatus(_callId!, 'connected');
    }
    emit(state.copyWith(
      isReconnecting: false,
      statusMessage: 'Connected',
      call: state.call?.copyWith(status: CallStatus.connected),
    ));
    // Resume duration if timer was stopped during disconnect
    if (_durationTimer == null || !(_durationTimer?.isActive ?? false)) {
      _startDurationTimer();
    }
  }

  void _failConnection(String message) {
    if (_callTerminated) return;
    _callTerminated = true;
    _connected = false;
    _cancelReconnect();
    _emitFailed(message);
    _finalizeCall('ended');
  }

  Future<void> _startIncomingCall() async {
    _callId = existingCallId;
    final offer = existingOffer;
    if (_callId == null || offer == null) {
      _emitFailed('Invalid call');
      return;
    }

    emit(state.copyWith(statusMessage: 'Connecting…'));
    _emitCallState(CallStatus.connecting, 'Connecting…');

    await _webrtc.setRemoteDescription(offer);
    final answer = await _webrtc.createAnswer();
    await _signallingRepo.sendAnswer(callId: _callId!, answer: answer);

    _listenToCall(_callId!);
    _listenToIce(_callId!);
  }

  void _listenToCall(String callId) {
    _callSub?.cancel();
    _callSub = _signallingRepo.watchCall(callId).listen((doc) async {
      if (doc == null) return;

      if (doc.status == 'declined') {
        unawaited(_handleRemoteCallEnd('declined'));
        return;
      }

      if (doc.status == 'ended') {
        unawaited(_handleRemoteCallEnd('ended'));
        return;
      }

      // Callee accepted — move caller from ringing to connecting
      if (doc.status == 'connecting' &&
          state.call?.status == CallStatus.ringing) {
        _emitCallState(CallStatus.connecting, 'Connecting…');
      }

      if (_isOutgoing && doc.answer != null && !_answerHandled) {
        _answerHandled = true;
        _emitCallState(CallStatus.connecting, 'Connecting…');
        await _webrtc.setRemoteDescription(doc.answer!);
      }
    });
  }

  void _listenToIce(String callId) {
    _iceSub?.cancel();
    _iceSub = _signallingRepo
        .watchIceCandidates(callId: callId, localUserId: _localUserId)
        .listen((candidate) async {
      final key =
          '${candidate.candidate}_${candidate.sdpMid}_${candidate.sdpMLineIndex}';
      if (_handledIceIds.contains(key)) return;
      _handledIceIds.add(key);
      await _webrtc.addIceCandidate(candidate);
    });
  }

  void _onConnected() {
    if (_connected) return;
    _connected = true;
    _ringTimeout?.cancel();
    _offlineCheckTimer?.cancel();
    _signallingRepo.updateCallStatus(_callId!, 'connected');
    _emitCallState(CallStatus.connected, 'Connected');
    _startDurationTimer();
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      emit(state.copyWith(durationSeconds: state.durationSeconds + 1));
    });
  }

  void _emitCallState(CallStatus status, String? message) {
    emit(state.copyWith(
      call: CallStateModel(
        callId: _callId ?? '',
        callerId: _isOutgoing ? _localUserId : _peer.deviceId,
        calleeId: _isOutgoing ? _peer.deviceId : _localUserId,
        status: status,
        peerName: _peer.name,
      ),
      statusMessage: message,
    ));
  }

  void _emitFailed(String message) {
    _emitCallState(CallStatus.failed, message);
  }

  void toggleMute() {
    final muted = !state.isMuted;
    _webrtc.setMuted(muted);
    emit(state.copyWith(isMuted: muted));
  }

  void toggleCamera() {
    if (!isVideoCall) return;
    final cameraOn = !state.isCameraOn;
    _webrtc.setCameraEnabled(cameraOn);
    emit(state.copyWith(isCameraOn: cameraOn));
  }

  Future<void> switchCamera() async {
    if (!isVideoCall) return;
    await _webrtc.switchCamera();
  }

  void toggleSpeaker() {
    final speakerOn = !state.isSpeakerOn;
    Helper.setSpeakerphoneOn(speakerOn);
    emit(state.copyWith(isSpeakerOn: speakerOn));
  }

  Future<void> declineCall() async {
    _callTerminated = true;
    _connected = false;
    _cancelReconnect();
    if (_callId != null) {
      await _signallingRepo.updateCallStatus(_callId!, 'declined');
    }
    _emitCallState(CallStatus.declined, 'Call declined');
    await _cleanup();
  }

  Future<void> endCall() async {
    // Mark terminated first so WebRTC disconnect won't trigger reconnect
    _callTerminated = true;
    _connected = false;
    _cancelReconnect();

    if (state.call?.status != CallStatus.failed &&
        state.call?.status != CallStatus.declined) {
      _emitCallState(CallStatus.ended, 'Call ended');
    }
    await _finalizeCall('ended');
  }

  // Update Firestore + cleanup without changing visible failed/declined text
  Future<void> _finalizeCall(String firestoreStatus) async {
    _callTerminated = true;
    _connected = false;
    _cancelReconnect();
    _ringTimeout?.cancel();
    _offlineCheckTimer?.cancel();
    if (_callId != null) {
      try {
        await _signallingRepo.updateCallStatus(_callId!, firestoreStatus);
      } catch (_) {
        // Signalling may be down — UI already shows the error
      }
    }
    await _cleanup();
  }

  Future<void> _cleanup() async {
    _callTerminated = true;
    _connected = false;
    _cancelReconnect();
    _ringTimeout?.cancel();
    _offlineCheckTimer?.cancel();
    _reconnectTimer?.cancel();
    _iceRecoveryTimer?.cancel();
    _durationTimer?.cancel();
    await _callSub?.cancel();
    await _iceSub?.cancel();
    await _webrtc.hangUp();
  }

  @override
  Future<void> close() async {
    await _cleanup();
    return super.close();
  }
}
