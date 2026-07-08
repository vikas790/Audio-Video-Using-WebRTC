import 'package:cloud_firestore/cloud_firestore.dart';

import 'base_model.dart';

// Online user in the lobby
class UserModel extends BaseModel {
  UserModel({
    required this.deviceId,
    required this.name,
    required this.isOnline,
    this.lastSeen,
  });

  final String deviceId;
  final String name;
  final bool isOnline;
  final DateTime? lastSeen;

  factory UserModel.fromFirestore(Map<String, dynamic> json, String docId) {
    return UserModel(
      deviceId: json['deviceId'] as String? ?? docId,
      name: json['name'] as String? ?? '',
      isOnline: json['isOnline'] as bool? ?? false,
      lastSeen: _parseTimestamp(json['lastSeen']),
    );
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      deviceId: json['deviceId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      isOnline: json['isOnline'] as bool? ?? false,
      lastSeen: _parseTimestamp(json['lastSeen']),
    );
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    return DateTime.tryParse(value.toString());
  }

  @override
  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'name': name,
        'isOnline': isOnline,
        'lastSeen': lastSeen?.toIso8601String(),
      };
}
