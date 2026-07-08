import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/models/call_document_model.dart';
import '../../../../data/models/user_model.dart';
import '../../../../utils/local_storage.dart';
import '../../../../utils/permission_helper.dart';
import '../../core/widgets/default_caller_avatar.dart';
import '../incoming_call/incoming_call_screen.dart';
import '../pre_join/pre_join_screen.dart';
import 'state/presence_state.dart';
import 'view_model/incoming_call_cubit.dart';
import 'view_model/presence_cubit.dart';

// Lobby — online users + incoming call overlay
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  String? _shownIncomingCallId;

  @override
  void initState() {
    super.initState();
    // Notification only on Online screen — mic/camera handled in pre-join
    PermissionHelper.requestNotificationPermission();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => PresenceCubit()..startWatching()),
        BlocProvider(
          create: (_) => IncomingCallCubit(
            localUserId: LocalStorage.deviceId,
          )..startListening(),
        ),
      ],
      child: _LobbyView(
        shownIncomingCallId: _shownIncomingCallId,
        onIncomingShown: (callId) =>
            setState(() => _shownIncomingCallId = callId),
        onIncomingCleared: () => setState(() => _shownIncomingCallId = null),
      ),
    );
  }
}

class _LobbyView extends StatelessWidget {
  const _LobbyView({
    required this.shownIncomingCallId,
    required this.onIncomingShown,
    required this.onIncomingCleared,
  });

  final String? shownIncomingCallId;
  final ValueChanged<String> onIncomingShown;
  final VoidCallback onIncomingCleared;

  @override
  Widget build(BuildContext context) {
    return BlocListener<IncomingCallCubit, CallDocumentModel?>(
      listenWhen: (prev, next) {
        if (next == null) return false;
        return next.callId != shownIncomingCallId;
      },
      listener: (context, incoming) {
        if (incoming == null) return;
        _openIncomingCallScreen(context, incoming);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Online')),
        body: BlocBuilder<PresenceCubit, PresenceState>(
          builder: (context, state) {
            if (state.isReconnecting) {
              return const Column(
                children: [
                  LinearProgressIndicator(),
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Reconnecting…'),
                  ),
                ],
              );
            }

            if (state.errorMessage != null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Connection error.\nCheck Firestore rules.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            if (state.users.isEmpty) {
              return const Center(child: Text('No one online yet'));
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: state.users.length,
              // 16px gap between bordered cards
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final user = state.users[index];
                return _UserRow(
                  user: user,
                  onAudioCall: user.isOnline
                      ? () => _startCall(context, user)
                      : null,
                  onVideoCall: user.isOnline
                      ? () => _startCall(context, user, isVideoCall: true)
                      : null,
                );
              },
            );
          },
        ),
      ),
    );
  }

  // Navigate to pre-join and show SnackBar when call ends with a message
  Future<void> _startCall(
    BuildContext context,
    UserModel user, {
    bool isVideoCall = false,
  }) async {
    if (!user.isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User is offline')),
      );
      return;
    }

    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => PreJoinScreen(peer: user, isVideoCall: isVideoCall),
      ),
    );

    if (result != null && result.isNotEmpty && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result)),
      );
    }
  }

  Future<void> _openIncomingCallScreen(
    BuildContext context,
    CallDocumentModel incoming,
  ) async {
    onIncomingShown(incoming.callId);
    final incomingCubit = context.read<IncomingCallCubit>();

    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => IncomingCallScreen(
          incoming: incoming,
          onDismiss: () {
            incomingCubit.clear();
            onIncomingCleared();
          },
        ),
      ),
    );

    // Safety reset if screen closed without callback.
    incomingCubit.clear();
    onIncomingCleared();
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    this.onAudioCall,
    this.onVideoCall,
  });

  final UserModel user;
  final VoidCallback? onAudioCall;
  final VoidCallback? onVideoCall;

  @override
  Widget build(BuildContext context) {
    // Bordered card row — matches reference list design
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0), width: 1.2),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              const DefaultCallerAvatar(size: 48),
              // Online indicator pinned on avatar corner.
              Positioned(
                top: -1,
                left: -1,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: user.isOnline ? Colors.green : Colors.grey,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              user.name,
              style: const TextStyle(fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Audio call',
            onPressed: onAudioCall,
            icon: const Icon(Icons.call),
          ),
          IconButton(
            tooltip: 'Video call',
            onPressed: onVideoCall,
            icon: const Icon(Icons.videocam),
          ),
        ],
      ),
    );
  }
}
