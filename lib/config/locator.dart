import 'package:get_it/get_it.dart';

import 'common_di.dart';

// Global service locator instance
final GetIt locator = GetIt.instance;

// Register all app dependencies
Future<void> setupLocator() async {
  await registerCommonDependencies(locator);
}
