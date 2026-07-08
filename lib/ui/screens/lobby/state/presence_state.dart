import '../../../base/api_render_state.dart';
import '../../../../data/models/user_model.dart';

// Lobby / presence UI state
class PresenceState extends ApiRenderState {
  PresenceState({
    this.users = const [],
    this.isReconnecting = false,
    this.errorMessage,
  });

  final List<UserModel> users;
  final bool isReconnecting;
  final String? errorMessage;

  PresenceState copyWith({
    List<UserModel>? users,
    bool? isReconnecting,
    String? errorMessage,
  }) {
    return PresenceState(
      users: users ?? this.users,
      isReconnecting: isReconnecting ?? this.isReconnecting,
      errorMessage: errorMessage,
    );
  }
}
