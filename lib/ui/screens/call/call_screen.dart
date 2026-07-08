import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../data/models/call_state_model.dart';
import '../../../../data/models/user_model.dart';
import '../../../../utils/constant.dart';
import '../../../../utils/local_storage.dart';
import '../../core/widgets/default_caller_avatar.dart';
import 'state/call_state.dart';
import 'state/chat_state.dart';
import 'view_model/call_cubit.dart';
import 'view_model/chat_cubit.dart';

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
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => CallCubit(
            peer: widget.peer,
            isOutgoing: widget.isOutgoing,
            isVideoCall: widget.isVideoCall,
            existingCallId: widget.existingCallId,
            existingOffer: widget.existingOffer,
          )..start(),
        ),
        // Separate cubit for in-call chat — keeps call logic untouched
        BlocProvider(create: (_) => ChatCubit()),
      ],
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

  // Open chat as a bottom sheet, reusing the existing ChatCubit instance
  void _openChat(BuildContext context) {
    final chatCubit = context.read<ChatCubit>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlocProvider.value(
        value: chatCubit,
        child: const _ChatPanel(),
      ),
    );
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
          // Attach chat once signalling assigns the call id (guards duplicates)
          final callId = state.call?.callId;
          if (callId != null && callId.isNotEmpty) {
            context.read<ChatCubit>().attachCall(callId);
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
                  // Show banner only when this device loses network
                  if (state.isReconnecting)
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _ReconnectBanner(),
                    ),
                  // Chat only when call is fully connected — hide during ringing/reconnecting/ended
                  if (state.call?.status == CallStatus.connected)
                    Positioned(
                      left: 12,
                      bottom: 96,
                      child: _ChatButton(
                        onTap: () => _openChat(context),
                      ),
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
                color: _statusColorForState(state),
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

Color _statusColorForState(CallUiState state) {
  if (state.isReconnecting || state.isPeerReconnecting) {
    return const Color(0xFF8A8A8A);
  }
  return _statusColor(state.call?.status);
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

// Red banner shown during mid-call network drop
class _ReconnectBanner extends StatelessWidget {
  const _ReconnectBanner();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFE84C3D),
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
                  color: _statusColorForState(state).withValues(alpha: 0.9),
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
            color: _statusColorForState(state).withValues(alpha: 0.9),
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
        return SafeArea(
          top: false,
          // Keep controls above Android system navigation buttons.
          child: Container(
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
          ),
        );
      },
    );
  }
}

// Left-side floating chat button — solid primary color (matches join buttons)
class _ChatButton extends StatelessWidget {
  const _ChatButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Same blue/primary as pre-join "Join call" button
    final chatColor = Theme.of(context).colorScheme.primary;

    return BlocBuilder<ChatCubit, ChatState>(
      builder: (context, state) {
        final hasMessages = state.messages.isNotEmpty;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              elevation: 4,
              shadowColor: Colors.black54,
              shape: const CircleBorder(),
              color: chatColor,
              child: InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    Icons.chat_bubble_outline,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
            // Small dot hints that messages exist
            if (hasMessages)
              Positioned(
                right: -1,
                top: -1,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2ECC71),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// In-call chat panel shown as a bottom sheet
class _ChatPanel extends StatefulWidget {
  const _ChatPanel();

  @override
  State<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<_ChatPanel> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    context.read<ChatCubit>().sendMessage(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final myId = LocalStorage.deviceId;
    // Lift the sheet above the keyboard
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: Color(AppConstants.appBackgroundValue),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  const Text(
                    'Chat',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2B2B2B),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Message list
            Expanded(
              child: BlocBuilder<ChatCubit, ChatState>(
                builder: (context, state) {
                  final messages = state.messages;
                  if (messages.isEmpty) {
                    return const Center(
                      child: Text(
                        'No messages yet',
                        style: TextStyle(color: Color(0xFF8A8A8A)),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isMine = message.senderId == myId;
                      return _ChatBubble(text: message.text, isMine: isMine);
                    },
                  );
                },
              ),
            ),
            // Input row
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: 'Type a message…',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _send,
                      icon: const Icon(Icons.send, color: Color(0xFF2B2B2B)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Single chat message bubble — right for me, left for peer
class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.text, required this.isMine});

  final String text;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: isMine ? const Color(0xFF2ECC71) : const Color(0xFFECECEC),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isMine ? Colors.white : const Color(0xFF2B2B2B),
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
