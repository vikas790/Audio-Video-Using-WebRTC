import 'package:flutter/material.dart';

import '../../../../config/locator.dart';
import '../../../../data/models/user_model.dart';
import '../../../../data/repositories/presence_repository.dart';
import '../../../../utils/constant.dart';
import '../../../../utils/permission_helper.dart';
import '../../../../utils/permission_ui.dart';
import '../../core/widgets/default_caller_avatar.dart';
import '../call/call_screen.dart';

// Pre-join: mic/camera permission check before call
class PreJoinScreen extends StatefulWidget {
  const PreJoinScreen({
    super.key,
    required this.peer,
    this.isVideoCall = false,
  });

  final UserModel peer;
  final bool isVideoCall;

  @override
  State<PreJoinScreen> createState() => _PreJoinScreenState();
}

class _PreJoinScreenState extends State<PreJoinScreen> {
  bool _micEnabled = false;
  bool _cameraEnabled = false;
  bool _micGranted = false;
  bool _cameraGranted = false;
  bool _isLoading = false;

  static const _textPrimary = Color(0xFF2B2B2B);
  static const _textSecondary = Color(0xFF8A8A8A);
  static const _background = Color(AppConstants.appBackgroundValue);
  static const _borderColor = Color(0xFFE0E0E0);

  @override
  void initState() {
    super.initState();
    _initPermissions();
  }

  // Sync toggles with existing permission state
  Future<void> _initPermissions() async {
    _micGranted = await PermissionHelper.isMicrophoneGranted();
    _cameraGranted = await PermissionHelper.isCameraGranted();
    _micEnabled = _micGranted;
    _cameraEnabled = widget.isVideoCall && _cameraGranted;
    if (mounted) setState(() {});
  }

  Future<void> _toggleMic() async {
    if (_isLoading) return;

    // Turning off — no permission needed
    if (_micEnabled) {
      setState(() => _micEnabled = false);
      return;
    }

    final result = await PermissionHelper.requestMicrophone();
    if (!mounted) return;

    switch (result) {
      case PermissionRequestResult.granted:
        setState(() {
          _micEnabled = true;
          _micGranted = true;
        });
      case PermissionRequestResult.denied:
        await _showPermissionSnackBar('Microphone permission denied');
      case PermissionRequestResult.permanentlyDenied:
        await _showSettingsDialog(
          title: 'Microphone blocked',
          message: 'Enable microphone access in Settings to join with audio.',
        );
    }
  }

  Future<void> _toggleCamera() async {
    if (_isLoading || !widget.isVideoCall) return;

    if (_cameraEnabled) {
      setState(() => _cameraEnabled = false);
      return;
    }

    final result = await PermissionHelper.requestCamera();
    if (!mounted) return;

    switch (result) {
      case PermissionRequestResult.granted:
        setState(() {
          _cameraEnabled = true;
          _cameraGranted = true;
        });
      case PermissionRequestResult.denied:
        await _showPermissionSnackBar('Camera permission denied');
      case PermissionRequestResult.permanentlyDenied:
        await _showSettingsDialog(
          title: 'Camera blocked',
          message: 'Enable camera access in Settings to join with video.',
        );
    }
  }

  Future<void> _showPermissionSnackBar(String message) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showSettingsDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              PermissionHelper.openSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _onJoinCall() async {
    if (!_micEnabled || _isLoading) return;
    if (widget.isVideoCall && !_cameraEnabled) return;

    setState(() => _isLoading = true);

    final micResult = await PermissionHelper.requestMicrophone();
    if (!mounted) return;
    if (micResult != PermissionRequestResult.granted) {
      setState(() => _isLoading = false);
      if (micResult == PermissionRequestResult.permanentlyDenied) {
        await _showSettingsDialog(
          title: 'Microphone required',
          message: 'Enable microphone in Settings to join the call.',
        );
      } else {
        await _showPermissionSnackBar('Microphone permission is required');
      }
      return;
    }

    var joinAsVideo = widget.isVideoCall;
    if (widget.isVideoCall) {
      final cameraResult = await PermissionHelper.requestCamera();
      if (!mounted) return;
      if (cameraResult != PermissionRequestResult.granted) {
        setState(() => _isLoading = false);
        if (cameraResult == PermissionRequestResult.permanentlyDenied) {
          final continueAsAudio = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Camera blocked'),
              content: const Text(
                'Camera is disabled in Settings. Continue as audio call?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Continue audio'),
                ),
              ],
            ),
          );
          if (continueAsAudio == true) {
            joinAsVideo = false;
            setState(() => _isLoading = true);
          } else {
            return;
          }
        } else {
          final continueAsAudio = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Camera permission denied'),
              content: const Text(
                'You can continue as an audio call or enable camera in settings.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Continue audio'),
                ),
              ],
            ),
          );
          if (continueAsAudio == true) {
            joinAsVideo = false;
            setState(() => _isLoading = true);
          } else {
            return;
          }
        }
      }
    }

    // Re-check callee is still online before placing call
    final presenceRepo = locator<PresenceRepository>();
    final peer = await presenceRepo.getUser(widget.peer.deviceId);
    if (!mounted) return;
    if (peer == null || !presenceRepo.isUserCurrentlyOnline(peer)) {
      setState(() => _isLoading = false);
      PermissionUi.showSnackBar(context, 'User is offline');
      return;
    }

    await _openCall(isVideoCall: joinAsVideo);
  }

  Future<void> _openCall({required bool isVideoCall}) async {
    if (!mounted) return;
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          peer: widget.peer,
          isOutgoing: true,
          isVideoCall: isVideoCall,
        ),
      ),
    );
    if (!mounted) return;
    // Pass terminal message back to lobby
    Navigator.of(context).pop(result);
  }

  bool get _canJoin =>
      _micEnabled && (!_isLoading) && (!widget.isVideoCall || _cameraEnabled);

  String _micStatusLabel() {
    if (!_micEnabled) return 'Off';
    if (!_micGranted) return 'Permission needed';
    return 'On';
  }

  String _cameraStatusLabel() {
    if (!_cameraEnabled) return 'Off';
    if (!_cameraGranted) return 'Permission needed';
    return 'On';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final callLabel = widget.isVideoCall ? 'Video call' : 'Audio call';

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Text(
                      callLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const Spacer(flex: 1),
                    // Static banner always visible
                    _PreviewAvatar(
                      primary: primary,
                      micActive: _micEnabled && _micGranted,
                      cameraActive: widget.isVideoCall &&
                          _cameraEnabled &&
                          _cameraGranted,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      widget.peer.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.isVideoCall
                                ? Icons.videocam_rounded
                                : Icons.call_rounded,
                            size: 16,
                            color: primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            callLabel,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.isVideoCall
                          ? 'Check your mic and camera before joining'
                          : 'Check your microphone before joining',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: _textSecondary,
                      ),
                    ),
                    const SizedBox(height: 36),
                    _MediaToggleTile(
                      label: 'Microphone',
                      enabled: _micEnabled,
                      statusLabel: _micStatusLabel(),
                      enabledIcon: Icons.mic_rounded,
                      disabledIcon: Icons.mic_off_rounded,
                      activeColor: primary,
                      borderColor: _borderColor,
                      onTap: _isLoading ? null : _toggleMic,
                    ),
                    if (widget.isVideoCall) ...[
                      const SizedBox(height: 12),
                      _MediaToggleTile(
                        label: 'Camera',
                        enabled: _cameraEnabled,
                        statusLabel: _cameraStatusLabel(),
                        enabledIcon: Icons.videocam_rounded,
                        disabledIcon: Icons.videocam_off_rounded,
                        activeColor: primary,
                        borderColor: _borderColor,
                        onTap: _isLoading ? null : _toggleCamera,
                      ),
                    ],
                    const Spacer(flex: 2),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        onPressed: _canJoin ? _onJoinCall : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: primary,
                          disabledBackgroundColor:
                              primary.withValues(alpha: 0.35),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ).copyWith(
                          elevation: WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.disabled)) {
                              return 0;
                            }
                            return 4;
                          }),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    widget.isVideoCall
                                        ? Icons.videocam_rounded
                                        : Icons.call_rounded,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    widget.isVideoCall
                                        ? 'Join video call'
                                        : 'Join call',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
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

// Static banner avatar + mic/camera status badges
class _PreviewAvatar extends StatelessWidget {
  const _PreviewAvatar({
    required this.primary,
    required this.micActive,
    required this.cameraActive,
  });

  final Color primary;
  final bool micActive;
  final bool cameraActive;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: primary.withValues(alpha: 0.25),
              width: 3,
            ),
          ),
          child: const DefaultCallerAvatar(size: 110),
        ),
        // Mic status badge
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: micActive ? const Color(0xFF2ECC71) : const Color(0xFF8A8A8A),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Icon(
              micActive ? Icons.mic_rounded : Icons.mic_off_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
        ),
        // Camera status badge (video calls only)
        if (cameraActive)
          Positioned(
            bottom: 0,
            left: 0,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF2ECC71),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(
                Icons.videocam_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
      ],
    );
  }
}

// Toggle row for mic / camera
class _MediaToggleTile extends StatelessWidget {
  const _MediaToggleTile({
    required this.label,
    required this.enabled,
    required this.statusLabel,
    required this.enabledIcon,
    required this.disabledIcon,
    required this.activeColor,
    required this.borderColor,
    this.onTap,
  });

  final String label;
  final bool enabled;
  final String statusLabel;
  final IconData enabledIcon;
  final IconData disabledIcon;
  final Color activeColor;
  final Color borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final icon = enabled ? enabledIcon : disabledIcon;
    final isOn = statusLabel == 'On';
    final needsPermission = statusLabel == 'Permission needed';
    final statusColor = isOn
        ? const Color(0xFF2ECC71)
        : needsPermission
            ? const Color(0xFFE67E22)
            : const Color(0xFF8A8A8A);

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor, width: 1.2),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Icon(
                  icon,
                  color: enabled ? activeColor : const Color(0xFF8A8A8A),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2B2B2B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 13,
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48,
                height: 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: enabled ? activeColor : const Color(0xFFD0D0D0),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  alignment:
                      enabled ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
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
