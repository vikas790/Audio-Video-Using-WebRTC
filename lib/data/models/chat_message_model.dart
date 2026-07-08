import 'base_model.dart';

// In-call chat message
class ChatMessageModel extends BaseModel {
  ChatMessageModel({
    required this.senderId,
    required this.text,
    required this.timestamp,
  });

  final String senderId;
  final String text;
  final DateTime timestamp;

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    return ChatMessageModel(
      senderId: json['senderId'] as String? ?? '',
      text: json['text'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        json['ts'] as int? ?? json['timestamp'] as int? ?? 0,
      ),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'senderId': senderId,
        'text': text,
        'ts': timestamp.millisecondsSinceEpoch,
      };
}
