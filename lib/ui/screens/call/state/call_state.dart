import '../../../base/api_render_state.dart';
import '../../../../data/models/call_state_model.dart';

// In-call UI state
class CallUiState extends ApiRenderState {
  CallUiState({
    this.call,
    this.isVideoCall = false,
    this.isMuted = false,
    this.isCameraOn = true,
    this.isSpeakerOn = false,
    this.hasRemoteVideo = false,
    this.durationSeconds = 0,
    this.statusMessage,
    this.isReconnecting = false,
  });

  final CallStateModel? call;
  final bool isVideoCall;
  final bool isMuted;
  final bool isCameraOn;
  final bool isSpeakerOn;
  final bool hasRemoteVideo;
  final int durationSeconds;
  final String? statusMessage;
  final bool isReconnecting;

  CallUiState copyWith({
    CallStateModel? call,
    bool? isVideoCall,
    bool? isMuted,
    bool? isCameraOn,
    bool? isSpeakerOn,
    bool? hasRemoteVideo,
    int? durationSeconds,
    String? statusMessage,
    bool? isReconnecting,
  }) {
    return CallUiState(
      call: call ?? this.call,
      isVideoCall: isVideoCall ?? this.isVideoCall,
      isMuted: isMuted ?? this.isMuted,
      isCameraOn: isCameraOn ?? this.isCameraOn,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      hasRemoteVideo: hasRemoteVideo ?? this.hasRemoteVideo,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      // Keep last status text when other fields update (e.g. timer tick)
      statusMessage: statusMessage ?? this.statusMessage,
      isReconnecting: isReconnecting ?? this.isReconnecting,
    );
  }
}
