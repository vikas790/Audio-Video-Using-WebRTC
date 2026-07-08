// App-wide constants
class AppConstants {
  AppConstants._();

  static const String appName = 'AudioVideo Task';
  static const int apiTimeoutSeconds = 30;
  static const int presenceStaleSeconds = 75;
  // Keep call alive up to 60s while network recovers.
  static const int callReconnectGraceSeconds = 60;

  // Firestore collections
  static const String usersCollection = 'Audio Video Call';
  static const String callsCollection = 'calls';

  // Default avatar for caller UI
  static const String defaultCallerBanner = 'assets/images/default_banner.png';

  // App-wide white background
  static const int appBackgroundValue = 0xFFFFFFFF;
}
