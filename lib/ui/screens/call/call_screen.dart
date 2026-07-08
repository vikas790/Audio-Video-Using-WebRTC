import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../data/models/call_state_model.dart';
import '../../../../data/models/user_model.dart';
import '../../../../utils/constant.dart';
import '../../core/widgets/default_caller_avatar.dart';
import 'state/call_state.dart';
import 'view_model/call_cubit.dart';

// Map call lifecycle to visible UI label
String callStatusLabel(CallUiState state) {
  final message = state.statusMessage;
  if (message != null && message.isNotEmpty) return message;

  switch (state.call?.status) {
    case CallStatus.ringing:
      return 'Ringing…';
    case CallStatus.connecting:
      return 'Connecting…';
    case CallStatus.connected:
      return 'Connected';
    case CallStatus.ended:
      return 'Call ended';
    case CallStatus.declined:
      return 'Call declined';
    case CallStatus.failed:
      return 'Call failed';
    default:
      return '';
  }
}

bool _isTerminalCallStatus(CallStatus? status) {
  return status == CallStatus.declined ||
      status == CallStatus.ended ||
      status == CallStatus.failed;
}

// Active call screen — audio or video
class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.peer,
    required this.isOutgoing,
    this.isVideoCall = false,
    this.existingCallId,
    this.existingOffer,
  });

  final UserModel peer;
  final bool isOutgoing;
  final bool isVideoCall;
  final String? existingCallId;
  final Map<String, dynamic>? existingOffer;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => CallCubit(
        peer: widget.peer,
        isOutgoing: widget.isOutgoing,
        isVideoCall: widget.isVideoCall,
        existingCallId: widget.existingCallId,
        existingOffer: widget.existingOffer,
      )..start(),
      child: _CallView(isVideoCall: widget.isVideoCall),
    );
  }
}

class _CallView extends StatefulWidget {
  const _CallView({required this.isVideoCall});

  final bool isVideoCall;

  @override
  State<_CallView> createState() => _CallViewState();
}

class _CallViewState extends State<_CallView> {
  RTCVideoRenderer? _localRenderer;
  RTCVideoRenderer? _remoteRenderer;
  bool _renderersReady = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideoCall) {
      _initRenderers();
    }
  }

  Future<void> _initRenderers() async {
    final local = RTCVideoRenderer();
    final remote = RTCVideoRenderer();
    await local.initialize();
    await remote.initialize();
    if (!mounted) return;
    setState(() {
      _localRenderer = local;
      _remoteRenderer = remote;
      _renderersReady = true;
    });
    // Bind streams after renderers ready — outside build phase
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bindStreams(context.read<CallCubit>());
    });
  }

  void _bindStreams(CallCubit cubit) {
    if (!_renderersReady) return;
    var streamBound = false;
    final localStream = cubit.webrtc.localStream;
    final remoteStream = cubit.webrtc.remoteStream;
    if (localStream != null && _localRenderer!.srcObject != localStream) {
      _localRenderer!.srcObject = localStream;
      streamBound = true;
    }
    if (remoteStream != null && _remoteRenderer!.srcObject != remoteStream) {
      _remoteRenderer!.srcObject = remoteStream;
      streamBound = true;
    }
    // Rebuild so RTCVideoView picks up new stream bindings
    if (streamBound && mounted) setState(() {});
  }

  @override
  void dispose() {
    _localRenderer?.dispose();
    _remoteRenderer?.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<CallCubit, CallUiState>(
      listenWhen: (prev, next) =>
          _isTerminalCallStatus(next.call?.status) &&
          !_isTerminalCallStatus(prev.call?.status),
      listener: (context, state) async {
        // Brief pause so user sees ended/declined/failed text
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        if (!context.mounted) return;
        final message = state.statusMessage;
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(message);
        }
      },
      child: BlocListener<CallCubit, CallUiState>(
        // Bind WebRTC streams on state change — not during build
        listener: (context, state) {
          if (widget.isVideoCall) {
            _bindStreams(context.read<CallCubit>());
          }
        },
        child: Scaffold(
          backgroundColor: widget.isVideoCall
              ? Colors.black
              : const Color(AppConstants.appBackgroundValue),
          appBar: AppBar(
            title: Text(widget.isVideoCall ? 'Video call' : 'In call'),
            backgroundColor:
                widget.isVideoCall ? Colors.black87 : null,
            foregroundColor: widget.isVideoCall ? Colors.white : null,
          ),
          body: BlocBuilder<CallCubit, CallUiState>(
            builder: (context, state) {
              return Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: widget.isVideoCall
                            ? _VideoCallBody(
                                state: state,
                                localRenderer: _localRenderer,
                                remoteRenderer: _remoteRenderer,
                                renderersReady: _renderersReady,
                                formatDuration: _formatDuration,
                              )
                            : _AudioCallBody(
                                state: state,
                                formatDuration: _formatDuration,
                              ),
                      ),
                      _CallControls(isVideoCall: widget.isVideoCall),
                    ],
                  ),
                  // Network drop — visible reconnect banner
                  if (state.isReconnecting)
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _ReconnectBanner(),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AudioCallBody extends StatelessWidget {
  const _AudioCallBody({
    required this.state,
    required this.formatDuration,
  });

  final CallUiState state;
  final String Function(int) formatDuration;

  @override
  Widget build(BuildContext context) {
    final statusText = callStatusLabel(state);
    final isConnected = state.call?.status == CallStatus.connected;
    final peerName = state.call?.peerName ?? 'Unknown';

    return Container(
      width: double.infinity,
      color: const Color(AppConstants.appBackgroundValue),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DefaultCallerAvatar(size: 88),
            const SizedBox(height: 18),
            Text(
              peerName,
              style: const TextStyle(
                color: Color(0xFF2B2B2B),
                fontSize: 30,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              statusText,
              style: TextStyle(
                color: _statusColor(state.call?.status),
                fontSize: 22,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (isConnected) ...[
              const SizedBox(height: 8),
              Text(
                formatDuration(state.durationSeconds),
                style: const TextStyle(color: Color(0xFF8A8A8A), fontSize: 22),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Color _statusColor(CallStatus? status) {
  switch (status) {
    case CallStatus.connected:
      return const Color(0xFF2ECC71);
    case CallStatus.failed:
    case CallStatus.declined:
      return const Color(0xFFE84C3D);
    case CallStatus.ended:
      return const Color(0xFF8A8A8A);
    default:
      return const Color(0xFF8A8A8A);
  }
}

// Orange banner shown during mid-call network drop
class _ReconnectBanner extends StatelessWidget {
  const _ReconnectBanner();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFE67E22),
      elevation: 4,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Reconnecting…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
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

class _VideoCallBody extends StatelessWidget {
  const _VideoCallBody({
    required this.state,
    required this.localRenderer,
    required this.remoteRenderer,
    required this.renderersReady,
    required this.formatDuration,
  });

  final CallUiState state;
  final RTCVideoRenderer? localRenderer;
  final RTCVideoRenderer? remoteRenderer;
  final bool renderersReady;
  final String Function(int) formatDuration;

  @override
  Widget build(BuildContext context) {
    final hasRemoteStream =
        remoteRenderer != null && remoteRenderer!.srcObject != null;
    final hasLocalStream =
        localRenderer != null && localRenderer!.srcObject != null;
    final statusText = callStatusLabel(state);
    final isConnected = state.call?.status == CallStatus.connected;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Remote video — dark surface required for WebRTC on Android
        if (renderersReady && (hasRemoteStream || state.hasRemoteVideo))
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black,
              child: RTCVideoView(
                remoteRenderer!,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            ),
          )
        else
          ColoredBox(
            color: Colors.black,
            child: Center(child: _VideoWaitingContent(state: state)),
          ),

        // Top info bar — name, status, and timer
        Positioned(
          top: 8,
          left: 16,
          right: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state.call?.peerName ?? '',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              Text(
                statusText,
                style: TextStyle(
                  color: _statusColor(state.call?.status).withValues(alpha: 0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (isConnected)
                Text(
                  formatDuration(state.durationSeconds),
                  style: const TextStyle(color: Colors.white70),
                ),
            ],
          ),
        ),

        // Local PIP
        if (renderersReady && state.isCameraOn && hasLocalStream)
          Positioned(
            right: 16,
            bottom: 16,
            width: 110,
            height: 150,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white70, width: 1.2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: ColoredBox(
                  color: Colors.black,
                  child: RTCVideoView(
                    localRenderer!,
                    mirror: true,
                    objectFit:
                        RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// Shown on black screen while remote video loads
class _VideoWaitingContent extends StatelessWidget {
  const _VideoWaitingContent({required this.state});

  final CallUiState state;

  @override
  Widget build(BuildContext context) {
    final statusText = callStatusLabel(state);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          state.call?.peerName ?? '',
          style: const TextStyle(color: Colors.white, fontSize: 22),
        ),
        const SizedBox(height: 8),
        Text(
          statusText,
          style: TextStyle(
            color: _statusColor(state.call?.status).withValues(alpha: 0.9),
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _CallControls extends StatelessWidget {
  const _CallControls({required this.isVideoCall});

  final bool isVideoCall;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CallCubit, CallUiState>(
      builder: (context, state) {
        final cubit = context.read<CallCubit>();
        final videoTheme = isVideoCall;
        return Container(
          color: videoTheme
              ? Colors.black87
              : const Color(AppConstants.appBackgroundValue),
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: cubit.toggleMute,
                icon: Icon(
                  state.isMuted ? Icons.mic_off : Icons.mic,
                  color: videoTheme
                      ? Colors.white
                      : const Color(0xFF2B2B2B),
                ),
              ),
              if (isVideoCall) ...[
                IconButton(
                  onPressed: cubit.toggleCamera,
                  icon: Icon(
                    state.isCameraOn ? Icons.videocam : Icons.videocam_off,
                    color: videoTheme
                        ? Colors.white
                        : const Color(0xFF2B2B2B),
                  ),
                ),
                IconButton(
                  onPressed: cubit.switchCamera,
                  icon: Icon(
                    Icons.cameraswitch,
                    color: videoTheme
                        ? Colors.white
                        : const Color(0xFF2B2B2B),
                  ),
                ),
              ],
              IconButton(
                onPressed: cubit.toggleSpeaker,
                icon: Icon(
                  state.isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                  color: videoTheme
                      ? Colors.white
                      : const Color(0xFF2B2B2B),
                ),
              ),
              IconButton(
                onPressed: () => cubit.endCall(),
                icon: const Icon(Icons.call_end, color: Colors.red),
              ),
            ],
          ),
        );
      },
    );
  }
}
