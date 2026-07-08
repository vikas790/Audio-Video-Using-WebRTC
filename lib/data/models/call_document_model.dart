import 'call_state_model.dart';

// Firestore call document snapshot
class CallDocumentModel {
  CallDocumentModel({
    required this.callId,
    required this.callerId,
    required this.calleeId,
    required this.callerName,
    required this.status,
    this.isVideo = false,
    this.offer,
    this.answer,
  });

  final String callId;
  final String callerId;
  final String calleeId;
  final String callerName;
  final String status;
  final bool isVideo;
  final Map<String, dynamic>? offer;
  final Map<String, dynamic>? answer;

  CallStatus get callStatus => CallStatus.values.firstWhere(
        (e) => e.name == status,
        orElse: () => CallStatus.idle,
      );

  factory CallDocumentModel.fromFirestore(String callId, Map<String, dynamic> data) {
    return CallDocumentModel(
      callId: callId,
      callerId: data['callerId'] as String? ?? '',
      calleeId: data['calleeId'] as String? ?? '',
      callerName: data['callerName'] as String? ?? '',
      status: data['status'] as String? ?? 'idle',
      isVideo: data['isVideo'] as bool? ?? false,
      offer: data['offer'] as Map<String, dynamic>?,
      answer: data['answer'] as Map<String, dynamic>?,
    );
  }
}
