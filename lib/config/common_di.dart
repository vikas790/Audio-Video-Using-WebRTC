import 'package:get_it/get_it.dart';

import '../data/repositories/chat_repository.dart';
import '../data/repositories/presence_repository.dart';
import '../data/repositories/signalling_repository.dart';
import '../data/services/firestore_signalling_service.dart';
import '../data/services/presence_service.dart';
import '../routing/navigation_service.dart';

// Register shared app-wide dependencies
Future<void> registerCommonDependencies(GetIt locator) async {
  locator.registerLazySingleton<NavigationService>(() => NavigationService());

  // Services — WebRTC / Firestore logic stays here, not in widgets
  locator.registerLazySingleton<PresenceService>(() => PresenceService());
  locator.registerLazySingleton<FirestoreSignallingService>(
    () => FirestoreSignallingService(),
  );

  // Repositories
  locator.registerLazySingleton<PresenceRepository>(
    () => PresenceRepository(locator<PresenceService>()),
  );
  locator.registerLazySingleton<SignallingRepository>(
    () => SignallingRepository(locator<FirestoreSignallingService>()),
  );
  locator.registerLazySingleton<ChatRepository>(() => ChatRepository());
}
