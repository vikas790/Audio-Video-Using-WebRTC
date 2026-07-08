import 'package:flutter/material.dart';

import 'app.dart';
import 'config/firebase_config.dart';
import 'config/locator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeFirebase();
  await setupLocator();
  runApp(const MyApp());
}
