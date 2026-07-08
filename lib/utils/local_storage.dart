import 'dart:math';

// Local identity storage (in-memory MVP; swap for SharedPreferences later)
class LocalStorage {
  LocalStorage._();

  static String? _deviceId;
  static String? _displayName;

  static String get deviceId {
    _deviceId ??= _generateId();
    return _deviceId!;
  }

  static String? get displayName => _displayName;

  static bool get hasIdentity =>
      _displayName != null && _displayName!.trim().isNotEmpty;

  static Future<void> saveIdentity(String name) async {
    _displayName = name.trim();
  }

  static Future<void> clear() async {
    _displayName = null;
  }

  static String _generateId() {
    final random = Random();
    return List.generate(16, (_) => random.nextInt(16).toRadixString(16))
        .join();
  }
}
