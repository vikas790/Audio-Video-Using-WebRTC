import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:audiovideo_task/app.dart';
import 'package:audiovideo_task/config/locator.dart';
import 'package:audiovideo_task/data/models/call_document_model.dart';
import 'package:audiovideo_task/data/models/signalling_message_model.dart';
import 'package:audiovideo_task/data/models/user_model.dart';
import 'package:audiovideo_task/data/repositories/presence_repository.dart';
import 'package:audiovideo_task/data/repositories/signalling_repository.dart';
import 'package:audiovideo_task/data/services/firestore_signalling_service.dart';
import 'package:audiovideo_task/data/services/presence_service.dart';
import 'package:audiovideo_task/utils/local_storage.dart';

class _FakePresenceService extends PresenceService {
  _FakePresenceService() : super(firestore: null);

  @override
  Stream<List<UserModel>> watchUsers() async* {
    yield [];
  }

  @override
  Future<void> setOnline({
    required String deviceId,
    required String name,
  }) async {}

  @override
  Future<void> setOffline({required String deviceId}) async {}
}

class _FakeSignallingService extends FirestoreSignallingService {
  _FakeSignallingService() : super(firestore: null);

  @override
  Stream<CallDocumentModel?> watchIncomingCalls(String calleeId) async* {
    yield null;
  }

  @override
  Stream<CallDocumentModel?> watchCall(String callId) async* {}

  @override
  Stream<SignallingMessageModel> watchIceCandidates({
    required String callId,
    required String localUserId,
  }) async* {}
}

void main() {
  setUp(() async {
    await LocalStorage.saveIdentity('Test User');
    await setupLocator();
    final getIt = GetIt.instance;

    if (getIt.isRegistered<PresenceService>()) {
      await getIt.unregister<PresenceService>();
    }
    if (getIt.isRegistered<PresenceRepository>()) {
      await getIt.unregister<PresenceRepository>();
    }
    if (getIt.isRegistered<FirestoreSignallingService>()) {
      await getIt.unregister<FirestoreSignallingService>();
    }
    if (getIt.isRegistered<SignallingRepository>()) {
      await getIt.unregister<SignallingRepository>();
    }

    getIt.registerLazySingleton<PresenceService>(_FakePresenceService.new);
    getIt.registerLazySingleton<PresenceRepository>(
      () => PresenceRepository(getIt<PresenceService>()),
    );
    getIt.registerLazySingleton<FirestoreSignallingService>(
      _FakeSignallingService.new,
    );
    getIt.registerLazySingleton<SignallingRepository>(
      () => SignallingRepository(getIt<FirestoreSignallingService>()),
    );
  });

  testWidgets('Lobby screen loads after identity is set', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Online'), findsOneWidget);
  });
}
