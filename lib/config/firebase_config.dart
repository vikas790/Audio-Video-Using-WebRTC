import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';

// Initialize Firebase with FlutterFire-generated platform options
Future<void> initializeFirebase() async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}
