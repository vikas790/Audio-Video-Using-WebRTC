import 'dart:async';

import 'package:flutter/material.dart';

import 'config/locator.dart';
import 'data/models/call_document_model.dart';
import 'data/repositories/presence_repository.dart';
import 'data/repositories/signalling_repository.dart';
import 'routing/navigation_service.dart';
import 'ui/core/themes/app_theme.dart';
import 'ui/screens/lobby/lobby_screen.dart';
import 'ui/screens/name_entry/name_entry_screen.dart';
import 'utils/constant.dart';
import 'utils/local_storage.dart';
import 'utils/local_notification_service.dart';

// Root widget — separated from main.dart so tests can run without Firebase init
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  Timer? _presenceHeartbeat;
  Timer? _incomingListenerBootstrapTimer;
  StreamSubscription<CallDocumentModel?>? _incomingCallSubscription;
  bool _isInForeground = true;
  String? _lastNotifiedCallId;
  CallDocumentModel? _latestIncomingCall;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPresenceHeartbeat();
    _startIncomingListenerBootstrap();
    LocalNotificationService.instance.initialize();
    _startIncomingCallListenerIfReady();
  }

  @override
  void dispose() {
    _presenceHeartbeat?.cancel();
    _incomingListenerBootstrapTimer?.cancel();
    _incomingCallSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _startIncomingListenerBootstrap() {
    _incomingListenerBootstrapTimer?.cancel();
    _incomingListenerBootstrapTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) {
        // Handles first-login case where identity is set after app init.
        _startIncomingCallListenerIfReady();
        if (_incomingCallSubscription != null) {
          _incomingListenerBootstrapTimer?.cancel();
        }
      },
    );
  }

  void _startIncomingCallListenerIfReady() {
    if (!LocalStorage.hasIdentity) return;
    _incomingCallSubscription ??= locator<SignallingRepository>()
        .watchIncomingCalls(LocalStorage.deviceId)
        .listen((incomingCall) {
          if (incomingCall == null) {
            _latestIncomingCall = null;
            _lastNotifiedCallId = null;
            return;
          }
          _latestIncomingCall = incomingCall;
          _tryNotifyIncoming(incomingCall);
        });
  }

  void _tryNotifyIncoming(CallDocumentModel incomingCall) {
    if (_isInForeground) return;
    if (_lastNotifiedCallId == incomingCall.callId) return;
    _lastNotifiedCallId = incomingCall.callId;

    LocalNotificationService.instance.showIncomingCall(
      callerName: incomingCall.callerName,
      isVideo: incomingCall.isVideo,
      id: incomingCall.callId.hashCode,
    );
  }

  void _startPresenceHeartbeat() {
    _presenceHeartbeat?.cancel();
    _presenceHeartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!LocalStorage.hasIdentity) return;
      final name = LocalStorage.displayName;
      if (name == null || name.trim().isEmpty) return;
      final repo = locator<PresenceRepository>();
      repo.setOnline(deviceId: LocalStorage.deviceId, name: name);
    });
  }

  // Keep user online in background; mark offline only on detach.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isInForeground = state == AppLifecycleState.resumed;
    if (!_isInForeground && _latestIncomingCall != null) {
      // If call arrived moments before home button, notify on background entry.
      _tryNotifyIncoming(_latestIncomingCall!);
    }
    if (!LocalStorage.hasIdentity) return;
    final repo = locator<PresenceRepository>();
    final name = LocalStorage.displayName;
    if (name == null || name.trim().isEmpty) return;

    if (state == AppLifecycleState.resumed) {
      _startIncomingCallListenerIfReady();
      repo.setOnline(
        deviceId: LocalStorage.deviceId,
        name: name,
      );
    } else if (state == AppLifecycleState.detached) {
      repo.setOffline(deviceId: LocalStorage.deviceId);
    }
  }

  @override
  Widget build(BuildContext context) {
    _startIncomingCallListenerIfReady();
    final navigationService = locator<NavigationService>();
    final initialScreen =
        LocalStorage.hasIdentity ? const LobbyScreen() : const NameEntryScreen();

    return MaterialApp(
      title: AppConstants.appName,
      theme: AppTheme.lightTheme,
      themeMode: ThemeMode.light,
      navigatorKey: navigationService.navigatorKey,
      home: initialScreen,
      debugShowCheckedModeBanner: false,
    );
  }
}
