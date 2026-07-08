import 'package:cloud_firestore/cloud_firestore.dart';

import '../../utils/constant.dart';
import '../models/chat_message_model.dart';
import 'base_repository.dart';

// In-call chat — messages stored under calls/{callId}/messages (reuses signalling channel)
class ChatRepository extends BaseRepository {
  ChatRepository({FirebaseFirestore? firestore}) : _injectedFirestore = firestore;

  final FirebaseFirestore? _injectedFirestore;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  // Message subcollection for a specific call
  CollectionReference<Map<String, dynamic>> _messages(String callId) =>
      _firestore
          .collection(AppConstants.callsCollection)
          .doc(callId)
          .collection('messages');

  // Live ordered messages for this call
  Stream<List<ChatMessageModel>> watchMessages(String callId) {
    return _messages(callId).orderBy('ts').snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => ChatMessageModel.fromJson(doc.data()))
              .toList(),
        );
  }

  // Persist one message — other peer receives it via the stream above
  Future<void> sendMessage(String callId, ChatMessageModel message) async {
    await _messages(callId).add(message.toJson());
  }
}
