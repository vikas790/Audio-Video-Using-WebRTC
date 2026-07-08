import 'dart:async';

import 'package:flutter/material.dart';

import '../../../config/locator.dart';
import '../../../data/models/call_document_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/signalling_repository.dart';
import '../../../utils/constant.dart';
import '../../../utils/permission_helper.dart';
import '../../../utils/permission_ui.dart';
import '../../core/widgets/default_caller_avatar.dart';
import '../call/call_screen.dart';

// Full-screen incoming call UI (banner + accept/decline)
class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({
    super.key,
    required this.incoming,
    required this.onDismiss,
  });

  final CallDocumentModel incoming;
  final VoidCallback onDismiss;

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  late final SignallingRepository _repo;
  StreamSubscription<CallDocumentModel?>? _callSub;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _repo = locator<SignallingRepository>();
    _watchCallStatus();
  }

  void _watchCallStatus() {
    _callSub = _repo.watchCall(widget.incoming.callId).listen((doc) {
      if (_handled || !mounted) return;
      if (doc == null) return;
      if (doc.status != 'ringing') {
        _closeScreen();
      }
    });
  }

  Future<void> _closeScreen() async {
    if (_handled || !mounted) return;
    _handled = true;
    widget.onDismiss();
    Navigator.of(context).pop();
  }

  Future<void> _decline() async {
    if (_handled) return;
    _handled = true;
    await _repo.updateCallStatus(widget.incoming.callId, 'declined');
    widget.onDismiss();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _accept() async {
    if (_handled) return;

    // Mic required for every call
    final micResult = await PermissionHelper.requestMicrophone();
    if (!mounted) return;
    if (micResult != PermissionRequestResult.granted) {
      if (micResult == PermissionRequestResult.permanentlyDenied) {
        await PermissionUi.showSettingsDialog(
          context,
          title: 'Microphone blocked',
          message: 'Enable microphone in Settings to accept the call.',
        );
      } else {
        PermissionUi.showSnackBar(context, 'Microphone permission denied');
      }
      return;
    }

    // Camera required for video calls
    if (widget.incoming.isVideo) {
      final cameraResult = await PermissionHelper.requestCamera();
      if (!mounted) return;
      if (cameraResult != PermissionRequestResult.granted) {
        if (cameraResult == PermissionRequestResult.permanentlyDenied) {
          await PermissionUi.showSettingsDialog(
            context,
            title: 'Camera blocked',
            message: 'Enable camera in Settings to accept the video call.',
          );
        } else {
          PermissionUi.showSnackBar(context, 'Camera permission denied');
        }
        return;
      }
    }

    _handled = true;
    widget.onDismiss();

    final caller = UserModel(
      deviceId: widget.incoming.callerId,
      name: widget.incoming.callerName,
      isOnline: true,
    );

    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          peer: caller,
          isOutgoing: false,
          isVideoCall: widget.incoming.isVideo,
          existingCallId: widget.incoming.callId,
          existingOffer: widget.incoming.offer,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _callSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callerName = widget.incoming.callerName;

    return Scaffold(
      backgroundColor: const Color(AppConstants.appBackgroundValue),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            const DefaultCallerAvatar(size: 170),
            const SizedBox(height: 28),
            Text(
              callerName,
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2B2B2B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.incoming.isVideo ? 'Incoming Video Call' : 'Incoming Call',
              style: const TextStyle(
                fontSize: 22,
                color: Color(0xFF8A8A8A),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ringing…',
              style: TextStyle(
                fontSize: 20,
                color: Color(0xFF8A8A8A),
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(flex: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _CallActionButton(
                    color: const Color(0xFFE84C3D),
                    icon: Icons.call_end,
                    onTap: _decline,
                  ),
                  _CallActionButton(
                    color: const Color(0xFF2ECC71),
                    icon: Icons.call,
                    onTap: _accept,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 74,
          height: 74,
          child: Icon(icon, color: Colors.white, size: 34),
        ),
      ),
    );
  }
}
