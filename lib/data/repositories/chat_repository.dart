import '../models/chat_message_model.dart';
import 'base_repository.dart';

// In-call chat — data channel primary, Firestore fallback later
class ChatRepository extends BaseRepository {
  ChatRepository();

  // TODO: wire to WebRTC data channel stream
  Stream<ChatMessageModel> watchMessages() async* {}

  Future<void> sendMessage(ChatMessageModel message) async {}
}
