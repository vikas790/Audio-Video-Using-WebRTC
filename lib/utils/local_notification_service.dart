import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Local notifications for incoming calls when app is backgrounded.
class LocalNotificationService {
  LocalNotificationService._();

  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    try {
      await _plugin.initialize(settings: settings);
      final androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();

      final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);
      _initialized = true;
    } catch (_) {
      // Ignore plugin setup issues in unsupported environments.
    }
  }

  Future<void> showIncomingCall({
    required String callerName,
    required bool isVideo,
    required int id,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    const androidDetails = AndroidNotificationDetails(
      'incoming_calls',
      'Incoming Calls',
      channelDescription: 'Notifications for incoming calls',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.call,
      ticker: 'Incoming call',
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _plugin.show(
        id: id,
        title: isVideo ? 'Incoming video call' : 'Incoming call',
        body: '$callerName is calling…',
        notificationDetails: details,
      );
    } catch (_) {
      // Ignore notification errors in debug/test runners.
      if (kDebugMode) {
        // no-op
      }
    }
  }
}
