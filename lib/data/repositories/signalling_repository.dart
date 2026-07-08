import '../models/call_document_model.dart';
import '../models/signalling_message_model.dart';
import '../services/firestore_signalling_service.dart';
import 'base_repository.dart';

// Signalling data access layer
class SignallingRepository extends BaseRepository {
  SignallingRepository(this._service);

  final FirestoreSignallingService _service;

  Future<String> createCall({
    required String callerId,
    required String calleeId,
    required String callerName,
    required Map<String, dynamic> offer,
    bool isVideo = false,
  }) =>
      _service.createCall(
        callerId: callerId,
        calleeId: calleeId,
        callerName: callerName,
        offer: offer,
        isVideo: isVideo,
      );

  Future<void> sendAnswer({
    required String callId,
    required Map<String, dynamic> answer,
  }) =>
      _service.sendAnswer(callId: callId, answer: answer);

  Future<void> sendIceCandidate({
    required String callId,
    required SignallingMessageModel candidate,
  }) =>
      _service.sendIceCandidate(callId: callId, candidate: candidate);

  Stream<CallDocumentModel?> watchCall(String callId) =>
      _service.watchCall(callId);

  Stream<CallDocumentModel?> watchIncomingCalls(String calleeId) =>
      _service.watchIncomingCalls(calleeId);

  Stream<SignallingMessageModel> watchIceCandidates({
    required String callId,
    required String localUserId,
  }) =>
      _service.watchIceCandidates(
        callId: callId,
        localUserId: localUserId,
      );

  Future<void> updateCallStatus(String callId, String status) =>
      _service.updateCallStatus(callId, status);

  Future<CallDocumentModel?> getCall(String callId) => _service.getCall(callId);
}
