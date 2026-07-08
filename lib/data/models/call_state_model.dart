import 'base_model.dart';

// Call lifecycle states
enum CallStatus {
  idle,
  ringing,
  connecting,
  connected,
  ended,
  declined,
  failed,
}

// Active call metadata
class CallStateModel extends BaseModel {
  CallStateModel({
    required this.callId,
    required this.callerId,
    required this.calleeId,
    this.status = CallStatus.idle,
    this.peerName = '',
  });

  final String callId;
  final String callerId;
  final String calleeId;
  final CallStatus status;
  final String peerName;

  CallStateModel copyWith({
    String? callId,
    String? callerId,
    String? calleeId,
    CallStatus? status,
    String? peerName,
  }) {
    return CallStateModel(
      callId: callId ?? this.callId,
      callerId: callerId ?? this.callerId,
      calleeId: calleeId ?? this.calleeId,
      status: status ?? this.status,
      peerName: peerName ?? this.peerName,
    );
  }

  factory CallStateModel.fromJson(Map<String, dynamic> json) {
    return CallStateModel(
      callId: json['callId'] as String? ?? '',
      callerId: json['callerId'] as String? ?? '',
      calleeId: json['calleeId'] as String? ?? '',
      status: CallStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => CallStatus.idle,
      ),
      peerName: json['peerName'] as String? ?? '',
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'callId': callId,
        'callerId': callerId,
        'calleeId': calleeId,
        'status': status.name,
        'peerName': peerName,
      };
}
