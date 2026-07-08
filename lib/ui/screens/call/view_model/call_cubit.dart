import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
  Timer? _peerWaitTimer; // user with network waits for peer to return
  Timer? _networkPollTimer; // polls for local network during reconnect
  Timer? _reconnectRetryTimer; // retries SDP renegotiation while reconnecting
  Timer? _offlineCheckTimer;
  Timer? _disconnectDebounceTimer;

  bool _waitingForPeer = false; // peer lost network, we still have it
  bool _reconnectOfferSent = false;
  bool _reconnectAttemptInFlight = false;
  DateTime? _lastReconnectOfferAt;
  String? _lastHandledReconnectOfferSdp;
  DateTime? _lastHandledReconnectOfferAt;
  String? _lastAppliedReconnectAnswerSdp;
  DateTime? _ignoreDisconnectUntil;
  RTCPeerConnectionState? _lastConnectionState;

  String? _callId;
  String get _localUserId => LocalStorage.deviceId;

  void _log(String message) {
    debugPrint('[CallCubit][$_localUserId] $message');
  }

  bool _inReconnectStabilizationWindow() {
    final until = _ignoreDisconnectUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  void _scheduleDebouncedConnectionLoss() {
    if (_disconnectDebounceTimer?.isActive ?? false) return;
    _log('DISCONNECTED detected, waiting debounce');
    _disconnectDebounceTimer = Timer(const Duration(seconds: 3), () async {
      _disconnectDebounceTimer = null;
      if (_callTerminated || !_connected) return;
      if (_lastConnectionState ==
          RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _log('Debounce resolved: recovered to connected');
        return;
      }
      _log('Debounce resolved: still disconnected');
      await _handleConnectionLoss();
    });
  }

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
      _lastConnectionState = connectionState;
      _log('WebRTC state -> $connectionState');
      if (connectionState ==
          RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _disconnectDebounceTimer?.cancel();
        if (state.isReconnecting) {
          _onReconnected();
        } else if (_waitingForPeer) {
          _onPeerCameBack();
        } else {
          _onConnected();
        }
      } else if (connectionState ==
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        if (_inReconnectStabilizationWindow()) {
          _log('Ignoring transient disconnect in stabilization window');
          return;
        }
        // Only handle loss mid-call — not after hang-up
        if (_connected && !_callTerminated) {
          _scheduleDebouncedConnectionLoss();
        }
      } else if (connectionState ==
              RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          connectionState ==
              RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        if (_inReconnectStabilizationWindow()) {
          _log('Ignoring transient failed/closed in stabilization window');
          return;
        }
        // During peer-wait, re-check local network before showing red banner.
        if (_waitingForPeer && !_callTerminated) {
          unawaited(_handleFailureWhileWaitingForPeer());
          return;
        }
        if (_connected && !_callTerminated) {
          unawaited(_handleConnectionLoss());
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

  // Stop reconnect / wait timers and hide banner
  void _cancelReconnect() {
    _disconnectDebounceTimer?.cancel();
    _reconnectTimer?.cancel();
    _iceRecoveryTimer?.cancel();
    _peerWaitTimer?.cancel();
    _networkPollTimer?.cancel();
    _reconnectRetryTimer?.cancel();
    _waitingForPeer = false;
    _reconnectAttemptInFlight = false;
    if (state.isReconnecting || state.isPeerReconnecting) {
      emit(state.copyWith(
        isReconnecting: false,
        isPeerReconnecting: false,
      ));
    }
  }

  void _resetReconnectNegotiation() {
    _reconnectOfferSent = false;
    _reconnectAttemptInFlight = false;
    _lastReconnectOfferAt = null;
    _lastHandledReconnectOfferSdp = null;
    _lastHandledReconnectOfferAt = null;
    _lastAppliedReconnectAnswerSdp = null;
    _handledIceIds.clear();
  }

  void _clearReconnectSession() {
    _resetReconnectNegotiation();
    _networkPollTimer?.cancel();
    final callId = _callId;
    if (callId != null) {
      _signallingRepo.markCallConnected(callId);
    }
  }

  // True when this device has active internet connectivity.
  Future<bool> _hasLocalNetwork() async {
    // Use internet probe only for reconnect-side decision. Backend checks can
    // fail transiently and incorrectly put both users into local reconnect.
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 3));
      if (result.isEmpty || result.first.rawAddress.isEmpty) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // Confirm local outage with retries to avoid false banner on peer side.
  Future<bool?> _detectLocalNetworkDown() async {
    var failedChecks = 0;
    const totalChecks = 2;
    for (var i = 0; i < totalChecks; i++) {
      final hasNetwork = await _hasLocalNetwork();
      if (!hasNetwork) failedChecks++;
      // Small gap helps avoid transient DNS/probe race.
      if (i < totalChecks - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }
    if (failedChecks == 0) return false;
    if (failedChecks == totalChecks) return true;
    // Mixed result -> uncertain state; avoid showing local red banner.
    return null;
  }

  // WebRTC dropped — route to local reconnect vs silent peer-wait
  Future<void> _handleConnectionLoss() async {
    if (!_connected ||
        _callTerminated ||
        state.isReconnecting ||
        _waitingForPeer) {
      return;
    }

    // Peer may have hung up — end immediately if Firestore says so
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
        // Firestore unreachable — local network likely down
      }
    }

    if (_callTerminated || !_connected) return;

    final localNetworkDown = await _detectLocalNetworkDown();
    _log('Connection lost detected, localNetworkDown=$localNetworkDown');
    if (localNetworkDown == true) {
      // We lost network — show reconnect banner only on this device.
      _enterLocalReconnecting();
      return;
    }
    // Local network is up/uncertain — treat as peer reconnect (no red banner).
    _enterWaitingForPeer();
  }

  // Decide reconnect side again when peer-wait gets failed/closed state.
  Future<void> _handleFailureWhileWaitingForPeer() async {
    if (!_waitingForPeer || _callTerminated) return;
    final localNetworkDown = await _detectLocalNetworkDown();
    _log('Peer-wait failed/closed, localNetworkDown=$localNetworkDown');
    if (_callTerminated || !_waitingForPeer) return;
    if (localNetworkDown == true) {
      _waitingForPeer = false;
      _peerWaitTimer?.cancel();
      _enterLocalReconnecting();
      return;
    }
    // Keep waiting for peer if local network is up/uncertain.
    _startIceRecovery();
  }

  // Peer lost network — text only "Reconnecting…", no red banner
  void _enterWaitingForPeer() {
    if (_waitingForPeer || state.isReconnecting || _callTerminated) return;
    _waitingForPeer = true;
    _resetReconnectNegotiation();
    _log('Entered peer reconnect wait state');

    emit(state.copyWith(
      statusMessage: 'Reconnecting…',
      isPeerReconnecting: true,
    ));

    _peerWaitTimer?.cancel();
    _peerWaitTimer = Timer(
      const Duration(seconds: AppConstants.callReconnectGraceSeconds),
      () {
        if (_waitingForPeer && !_callTerminated) {
          // Strict grace limit: call must recover within configured timeout.
          _failConnection('Connection lost');
        }
      },
    );

    _startIceRecovery();
  }

  // Local network lost — red banner + poll until data returns
  void _enterLocalReconnecting() {
    if (state.isReconnecting || _callTerminated) return;
    _resetReconnectNegotiation();
    _log('Entered local reconnect state (show red banner)');

    emit(state.copyWith(
      isReconnecting: true,
      isPeerReconnecting: false,
      statusMessage: 'Reconnecting…',
    ));

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      const Duration(seconds: AppConstants.callReconnectGraceSeconds),
      () {
        if (state.isReconnecting && !_callTerminated) {
          // Strict grace limit: call must recover within configured timeout.
          _log('Reconnect grace timeout hit -> failing call');
          _failConnection('Connection lost');
        }
      },
    );

    _startIceRecovery();
    _startNetworkPolling();
    _startReconnectRetryLoop();
    // Try immediately — don't wait for first poll tick
    unawaited(_tryReconnectWhenNetworkBack());
  }

  // Poll every 1s — detect network return quickly
  void _startNetworkPolling() {
    _networkPollTimer?.cancel();
    _networkPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!state.isReconnecting || _callTerminated) {
        _networkPollTimer?.cancel();
        return;
      }
      unawaited(_tryReconnectWhenNetworkBack());
    });
  }

  // Retry full SDP renegotiation every 5s until connected or timeout
  void _startReconnectRetryLoop() {
    _reconnectRetryTimer?.cancel();
    _reconnectRetryTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!state.isReconnecting || _callTerminated) {
        _reconnectRetryTimer?.cancel();
        return;
      }
      _log('Reconnect retry tick');
      unawaited(_tryReconnectWhenNetworkBack());
    });
  }

  Future<void> _tryReconnectWhenNetworkBack() async {
    if (!state.isReconnecting || _callTerminated || _reconnectAttemptInFlight) {
      return;
    }
    if (!await _hasLocalNetwork()) {
      _log('Reconnect attempt skipped: network still down');
      return;
    }
    if (_reconnectOfferSent && _lastAppliedReconnectAnswerSdp == null) {
      final waitingSince = _lastReconnectOfferAt;
      final waitingTooLong = waitingSince != null &&
          DateTime.now().difference(waitingSince) > const Duration(seconds: 8);
      if (waitingTooLong) {
        _log('No reconnect answer yet, resending offer');
        _reconnectOfferSent = false;
      } else {
        _log('Reconnect offer already sent, waiting for answer');
        return;
      }
    }

    _reconnectAttemptInFlight = true;
    try {
      _log('Network restored, trying SDP reconnect');
      await _webrtc.reestablish();
      emit(state.copyWith(hasRemoteVideo: _webrtc.remoteStream != null));

      final offer = await _webrtc.createReconnectOffer();
      _reconnectOfferSent = true;
      _lastReconnectOfferAt = DateTime.now();
      _log('Reconnect offer id=${_lastReconnectOfferAt!.millisecondsSinceEpoch}');
      _lastAppliedReconnectAnswerSdp = null;

      await _signallingRepo.sendReconnectOffer(
        callId: _callId!,
        fromUserId: _localUserId,
        offer: offer,
      );
      _log('Reconnect offer sent');
    } catch (e) {
      _reconnectOfferSent = false;
      _log('Reconnect attempt failed: $e');
    } finally {
      _reconnectAttemptInFlight = false;
    }
  }

  Future<void> _handlePeerReconnectOffer(Map<String, dynamic> offer) async {
    if (_callTerminated) return;
    final now = DateTime.now();
    final offerSdp = offer['sdp'] as String? ?? '';
    final lastAt = _lastHandledReconnectOfferAt;
    final isSameOffer = offerSdp.isNotEmpty && offerSdp == _lastHandledReconnectOfferSdp;
    final inCooldown =
        lastAt != null && now.difference(lastAt) < const Duration(seconds: 3);
    if (isSameOffer || inCooldown) {
      _log('Reconnect offer ignored (duplicate/cooldown)');
      return;
    }

    try {
      _log('Received peer reconnect offer');
      _lastHandledReconnectOfferSdp = offerSdp;
      _lastHandledReconnectOfferAt = now;
      await _webrtc.reestablish();
      _handledIceIds.clear();
      await _webrtc.setRemoteDescription(offer);
      final answer = await _webrtc.createAnswer();
      await _signallingRepo.sendReconnectAnswer(
        callId: _callId!,
        answer: answer,
      );
      _log('Reconnect answer sent');
      emit(state.copyWith(hasRemoteVideo: _webrtc.remoteStream != null));
    } catch (e) {
      _lastHandledReconnectOfferSdp = null;
      _log('Failed handling peer reconnect offer: $e');
    }
  }

  Future<void> _applyReconnectAnswer(Map<String, dynamic> answer) async {
    if (_callTerminated) return;
    try {
      await _webrtc.setRemoteDescription(answer);
      _log('answerApplied -> resume');
      if (state.isReconnecting) {
        _onReconnected();
      }
    } catch (e) {
      _lastAppliedReconnectAnswerSdp = null;
      _log('Failed applying reconnect answer: $e');
    }
  }

  Future<void> _handleReconnectSignalling(CallDocumentModel doc) async {
    if (_callTerminated) return;

    final offer = doc.reconnectOffer;
    if (offer != null &&
        doc.reconnectFrom != null &&
        doc.reconnectFrom != _localUserId) {
      final offerSdp = offer['sdp'] as String? ?? '';
      if (offerSdp.isNotEmpty) {
        await _handlePeerReconnectOffer(offer);
      }
    }

    final answer = doc.reconnectAnswer;
    if (answer != null && _reconnectOfferSent) {
      final answerSdp = answer['sdp'] as String? ?? '';
      if (answerSdp.isNotEmpty &&
          answerSdp != _lastAppliedReconnectAnswerSdp) {
        _lastAppliedReconnectAnswerSdp = answerSdp;
        await _applyReconnectAnswer(answer);
      }
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

  // Retry ICE every 3s while reconnecting or waiting for peer
  void _startIceRecovery() {
    _iceRecoveryTimer?.cancel();
    _attemptIceRecovery();
    _iceRecoveryTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!state.isReconnecting && !_waitingForPeer) {
        _iceRecoveryTimer?.cancel();
        return;
      }
      _attemptIceRecovery();
    });
  }

  Future<void> _attemptIceRecovery() async {
    // When local network is back, start SDP renegotiation immediately
    if (state.isReconnecting && await _hasLocalNetwork()) {
      await _tryReconnectWhenNetworkBack();
      return;
    }
    try {
      await _webrtc.restartIce();
    } catch (_) {
      // Network still down — keep retrying until grace timer expires
    }
  }

  // Network restored — resume call on device that lost connection
  void _onReconnected() {
    _ignoreDisconnectUntil = DateTime.now().add(const Duration(seconds: 4));
    _reconnectTimer?.cancel();
    _iceRecoveryTimer?.cancel();
    _reconnectRetryTimer?.cancel();
    _networkPollTimer?.cancel();
    _clearReconnectSession();
    _log('Call resumed after local reconnect');
    emit(state.copyWith(
      isReconnecting: false,
      isPeerReconnecting: false,
      statusMessage: 'Connected',
      call: state.call?.copyWith(status: CallStatus.connected),
    ));
    if (_durationTimer == null || !(_durationTimer?.isActive ?? false)) {
      _startDurationTimer();
    }
  }

  // Peer came back — resume call on user who still had network
  void _onPeerCameBack() {
    _waitingForPeer = false;
    _peerWaitTimer?.cancel();
    _iceRecoveryTimer?.cancel();
    _clearReconnectSession();
    _log('Call resumed after peer reconnect');
    emit(state.copyWith(
      isPeerReconnecting: false,
      statusMessage: 'Connected',
      call: state.call?.copyWith(status: CallStatus.connected),
    ));
    if (_durationTimer == null || !(_durationTimer?.isActive ?? false)) {
      _startDurationTimer();
    }
  }

  void _failConnection(String message) {
    if (_callTerminated) return;
    _log('Failing call: $message');
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

      // SDP renegotiation while peer reconnects after network loss
      if (doc.reconnectOffer != null || doc.reconnectAnswer != null) {
        await _handleReconnectSignalling(doc);
      }

      // Fallback resume path: if Firestore already reached connected,
      // clear reconnect UI even when WebRTC callback is delayed.
      if (doc.status == 'connected') {
        if (state.isReconnecting) {
          _log('Firestore connected -> local reconnect resolved');
          _onReconnected();
        } else if (state.isPeerReconnecting || _waitingForPeer) {
          _log('Firestore connected -> peer reconnect resolved');
          _onPeerCameBack();
        }
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
      try {
        await _webrtc.addIceCandidate(candidate);
        _log('[ICE] applied');
      } catch (e) {
        // Ignore transient ICE races while peer connection is rebuilding.
        _log('[ICE] apply failed: $e');
      }
    });
  }

  void _onConnected() {
    if (_connected) return;
    _connected = true;
    _ignoreDisconnectUntil = DateTime.now().add(const Duration(seconds: 4));
    _log('WebRTC connected');
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
    _disconnectDebounceTimer?.cancel();
    _reconnectTimer?.cancel();
    _iceRecoveryTimer?.cancel();
    _peerWaitTimer?.cancel();
    _networkPollTimer?.cancel();
    _reconnectRetryTimer?.cancel();
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
