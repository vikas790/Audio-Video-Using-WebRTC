import 'base_model.dart';

// SDP offer/answer or ICE candidate from Firestore
enum SignallingType { offer, answer, ice }

class SignallingMessageModel extends BaseModel {
  SignallingMessageModel({
    required this.type,
    this.sdp,
    this.sdpType,
    this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
    this.fromUserId,
  });

  final SignallingType type;
  final String? sdp;
  final String? sdpType;
  final String? candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;
  final String? fromUserId;

  factory SignallingMessageModel.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? '';
    return SignallingMessageModel(
      type: SignallingType.values.firstWhere(
        (e) => e.name == typeStr,
        orElse: () => SignallingType.ice,
      ),
      sdp: json['sdp'] as String?,
      sdpType: json['sdpType'] as String?,
      candidate: json['candidate'] as String?,
      sdpMid: json['sdpMid'] as String?,
      sdpMLineIndex: json['sdpMLineIndex'] as int?,
      fromUserId: json['fromUserId'] as String?,
    );
  }

  // Parse Firestore offer/answer map: { sdp, type }
  factory SignallingMessageModel.fromSdpMap(
    Map<String, dynamic> map, {
    required SignallingType type,
    String? fromUserId,
  }) {
    return SignallingMessageModel(
      type: type,
      sdp: map['sdp'] as String?,
      sdpType: map['type'] as String?,
      fromUserId: fromUserId,
    );
  }

  // Parse Firestore ICE subcollection doc
  factory SignallingMessageModel.fromIceMap(Map<String, dynamic> json) {
    return SignallingMessageModel(
      type: SignallingType.ice,
      candidate: json['candidate'] as String?,
      sdpMid: json['sdpMid'] as String?,
      sdpMLineIndex: json['sdpMLineIndex'] as int?,
      fromUserId: json['fromUserId'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type.name,
        if (sdp != null) 'sdp': sdp,
        if (sdpType != null) 'sdpType': sdpType,
        if (candidate != null) 'candidate': candidate,
        if (sdpMid != null) 'sdpMid': sdpMid,
        if (sdpMLineIndex != null) 'sdpMLineIndex': sdpMLineIndex,
        if (fromUserId != null) 'fromUserId': fromUserId,
      };
}
