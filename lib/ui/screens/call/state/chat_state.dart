import '../../../base/api_render_state.dart';
import '../../../../data/models/chat_message_model.dart';

// In-call chat UI state
class ChatState extends ApiRenderState {
  ChatState({this.messages = const []});

  final List<ChatMessageModel> messages;

  ChatState copyWith({List<ChatMessageModel>? messages}) {
    return ChatState(messages: messages ?? this.messages);
  }
}
