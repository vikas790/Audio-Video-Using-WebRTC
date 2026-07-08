import 'package:cloud_firestore/cloud_firestore.dart';

import '../../utils/constant.dart';
import '../models/call_document_model.dart';
import '../models/signalling_message_model.dart';

// Firestore signalling: offer/answer/ICE exchange
class FirestoreSignallingService {
  FirestoreSignallingService({FirebaseFirestore? firestore})
      : _injectedFirestore = firestore;

  final FirebaseFirestore? _injectedFirestore;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _calls =>
      _firestore.collection(AppConstants.callsCollection);

  Future<String> createCall({
    required String callerId,
    required String calleeId,
    required String callerName,
    required Map<String, dynamic> offer,
    bool isVideo = false,
  }) async {
    final doc = await _calls.add({
      'callerId': callerId,
      'calleeId': calleeId,
      'callerName': callerName,
      'offer': offer,
      'isVideo': isVideo,
      'status': 'ringing',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> sendAnswer({
    required String callId,
    required Map<String, dynamic> answer,
  }) async {
    await _calls.doc(callId).update({
      'answer': answer,
      'status': 'connecting',
    });
  }

  Future<void> sendIceCandidate({
    required String callId,
    required SignallingMessageModel candidate,
  }) async {
    await _calls.doc(callId).collection('ice').add({
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
      'fromUserId': candidate.fromUserId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateCallStatus(String callId, String status) async {
    await _calls.doc(callId).update({'status': status});
  }

  // User who lost network sends new SDP when data returns
  Future<void> sendReconnectOffer({
    required String callId,
    required String fromUserId,
    required Map<String, dynamic> offer,
  }) async {
    await _calls.doc(callId).update({
      'status': 'reconnecting',
      'reconnectFrom': fromUserId,
      'reconnectOffer': offer,
      'reconnectAnswer': FieldValue.delete(),
    });
  }

  Future<void> sendReconnectAnswer({
    required String callId,
    required Map<String, dynamic> answer,
  }) async {
    await _calls.doc(callId).update({
      'reconnectAnswer': answer,
      'status': 'reconnecting',
    });
  }

  // Clear reconnect fields after call resumes
  Future<void> markCallConnected(String callId) async {
    await _calls.doc(callId).update({
      'status': 'connected',
      'reconnectFrom': FieldValue.delete(),
      'reconnectOffer': FieldValue.delete(),
      'reconnectAnswer': FieldValue.delete(),
    });
  }

  // One-shot read — used to detect remote hang-up before showing reconnect UI
  Future<CallDocumentModel?> getCall(String callId) async {
    final snap = await _calls.doc(callId).get();
    if (!snap.exists || snap.data() == null) return null;
    return CallDocumentModel.fromFirestore(snap.id, snap.data()!);
  }

  Stream<CallDocumentModel?> watchCall(String callId) {
    return _calls.doc(callId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return CallDocumentModel.fromFirestore(snap.id, snap.data()!);
    });
  }

  Stream<CallDocumentModel?> watchIncomingCalls(String calleeId) {
    return _calls.where('calleeId', isEqualTo: calleeId).snapshots().map(
      (snapshot) {
        for (final doc in snapshot.docs) {
          final data = doc.data();
          if (data['status'] == 'ringing') {
            return CallDocumentModel.fromFirestore(doc.id, data);
          }
        }
        return null;
      },
    );
  }

  Stream<SignallingMessageModel> watchIceCandidates({
    required String callId,
    required String localUserId,
  }) {
    return _calls.doc(callId).collection('ice').snapshots().expand(
      (snapshot) {
        return snapshot.docChanges
            .where((change) => change.type == DocumentChangeType.added)
            .map((change) => change.doc.data())
            .where((data) => data != null && data['fromUserId'] != localUserId)
            .map((data) => SignallingMessageModel.fromIceMap(data!));
      },
    );
  }
}
