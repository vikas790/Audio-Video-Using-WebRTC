import 'dart:async';

import '../../../../config/locator.dart';
import '../../../../data/models/call_document_model.dart';
import '../../../../data/repositories/signalling_repository.dart';
import '../../../base/base_cubit.dart';

// Listens for incoming ringing calls
class IncomingCallCubit extends BaseCubit<CallDocumentModel?> {
  IncomingCallCubit({required this.localUserId}) : super(null) {
    _repo = locator<SignallingRepository>();
  }

  final String localUserId;
  late final SignallingRepository _repo;
  StreamSubscription<CallDocumentModel?>? _subscription;

  void startListening() {
    _subscription?.cancel();
    _subscription = _repo.watchIncomingCalls(localUserId).listen(
      (incoming) {
        // Emit null when call ends so popup does not reopen for same call.
        emit(incoming);
      },
      onError: (_) => emit(null),
    );
  }

  Future<void> decline(String callId) async {
    await _repo.updateCallStatus(callId, 'declined');
    emit(null);
  }

  void clear() => emit(null);

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
