// App-wide constants
class AppConstants {
  AppConstants._();

  static const String appName = 'AudioVideo Task';
  static const int apiTimeoutSeconds = 30;
  static const int presenceStaleSeconds = 75;
  // Grace period before ending call on network drop
  static const int callReconnectGraceSeconds = 30;

  // Firestore collections
  static const String usersCollection = 'Audio Video Call';
  static const String callsCollection = 'calls';

  // Default avatar for caller UI
  static const String defaultCallerBanner = 'assets/images/default_banner.png';

  // App-wide white background
  static const int appBackgroundValue = 0xFFFFFFFF;
}
