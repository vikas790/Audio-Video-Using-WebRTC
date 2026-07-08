import 'package:permission_handler/permission_handler.dart';

// Permission outcomes for toggle / join flows
enum PermissionRequestResult {
  granted,
  denied,
  permanentlyDenied,
}

// Mic, camera (pre-join) + notification (lobby)
class PermissionHelper {
  PermissionHelper._();

  static Future<bool> isMicrophoneGranted() =>
      _isGranted(Permission.microphone);

  static Future<bool> isCameraGranted() => _isGranted(Permission.camera);

  static Future<bool> ensureMicrophone() async {
    return (await requestMicrophone()) == PermissionRequestResult.granted;
  }

  static Future<bool> ensureCamera() async {
    return (await requestCamera()) == PermissionRequestResult.granted;
  }

  // Both required for video calls (incoming accept flow)
  static Future<bool> ensureCallPermissions({required bool video}) async {
    final mic = await ensureMicrophone();
    if (!mic) return false;
    if (!video) return true;
    return ensureCamera();
  }

  // Notification only — requested on Online (lobby) screen
  static Future<void> requestNotificationPermission() async {
    await Permission.notification.request();
  }

  static Future<PermissionRequestResult> requestMicrophone() async {
    return _request(Permission.microphone);
  }

  static Future<PermissionRequestResult> requestCamera() async {
    return _request(Permission.camera);
  }

  static Future<bool> _isGranted(Permission permission) async {
    final status = await permission.status;
    return status.isGranted;
  }

  static Future<PermissionRequestResult> _request(Permission permission) async {
    var status = await permission.status;
    if (status.isGranted) return PermissionRequestResult.granted;

    status = await permission.request();
    if (status.isGranted) return PermissionRequestResult.granted;
    if (status.isPermanentlyDenied) {
      return PermissionRequestResult.permanentlyDenied;
    }
    return PermissionRequestResult.denied;
  }

  static Future<void> openSettings() => openAppSettings();
}
