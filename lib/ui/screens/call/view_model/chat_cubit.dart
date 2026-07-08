import '../../../../config/locator.dart';
import '../../../../data/models/chat_message_model.dart';
import '../../../../data/repositories/chat_repository.dart';
import '../../../../utils/local_storage.dart';
import '../../../base/base_cubit.dart';
import '../state/chat_state.dart';

// In-call text chat logic
class ChatCubit extends BaseCubit<ChatState> {
  ChatCubit() : super(ChatState()) {
    _repo = locator<ChatRepository>();
  }

  late final ChatRepository _repo;

  void startWatching() {
    _repo.watchMessages().listen((message) {
      emit(state.copyWith(messages: [...state.messages, message]));
    });
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    final message = ChatMessageModel(
      senderId: LocalStorage.deviceId,
      text: text.trim(),
      timestamp: DateTime.now(),
    );
    await _repo.sendMessage(message);
    emit(state.copyWith(messages: [...state.messages, message]));
  }
}
