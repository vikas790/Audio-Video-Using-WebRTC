import 'dart:async';

import '../../../../config/locator.dart';
import '../../../../data/models/user_model.dart';
import '../../../../data/repositories/presence_repository.dart';
import '../../../../utils/local_storage.dart';
import '../../../base/base_cubit.dart';
import '../state/presence_state.dart';

// Online users list logic
class PresenceCubit extends BaseCubit<PresenceState> {
  PresenceCubit() : super(PresenceState()) {
    _repo = locator<PresenceRepository>();
  }

  late final PresenceRepository _repo;
  StreamSubscription<List<UserModel>>? _subscription;

  void startWatching() {
    _subscription?.cancel();
    refreshPresence();
    _subscription = _repo.watchUsers().listen(
      (users) {
        // Exclude self from lobby list
        final filtered = users
            .where((u) => u.deviceId != LocalStorage.deviceId)
            .toList();
        emit(state.copyWith(
          users: filtered,
          isReconnecting: false,
          errorMessage: null,
        ));
      },
      onError: (error) {
        emit(state.copyWith(
          isReconnecting: false,
          errorMessage: error.toString(),
        ));
      },
    );
  }

  Future<void> refreshPresence() async {
    final name = LocalStorage.displayName;
    if (name == null) return;
    await _repo.setOnline(deviceId: LocalStorage.deviceId, name: name);
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
