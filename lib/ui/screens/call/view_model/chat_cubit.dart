import 'dart:async';

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
  StreamSubscription<List<ChatMessageModel>>? _sub;
  String? _callId;

  // Bind to a call once its id is known — starts live message stream
  void attachCall(String callId) {
    if (callId.isEmpty || _callId == callId) return;
    _callId = callId;
    _sub?.cancel();
    _sub = _repo.watchMessages(callId).listen((messages) {
      emit(state.copyWith(messages: messages));
    });
  }

  Future<void> sendMessage(String text) async {
    final callId = _callId;
    if (callId == null || text.trim().isEmpty) return;
    final message = ChatMessageModel(
      senderId: LocalStorage.deviceId,
      text: text.trim(),
      timestamp: DateTime.now(),
    );
    // No local echo — Firestore stream will deliver it back to us
    await _repo.sendMessage(callId, message);
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
