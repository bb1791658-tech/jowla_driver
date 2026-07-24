class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.clientMessageId,
    required this.senderType,
    required this.senderId,
    required this.type,
    required this.createdAt,
    this.body,
    this.readAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id']?.toString() ?? '',
    clientMessageId: json['clientMessageId']?.toString() ?? '',
    senderType: json['senderType']?.toString().toUpperCase() ?? '',
    senderId: json['senderId']?.toString() ?? '',
    type: json['type']?.toString().toUpperCase() ?? 'TEXT',
    body: json['body']?.toString(),
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal() ??
        DateTime.now(),
    readAt: DateTime.tryParse(json['readAt']?.toString() ?? '')?.toLocal(),
  );

  final String id;
  final String clientMessageId;
  final String senderType;
  final String senderId;
  final String type;
  final String? body;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get sentByDriver => senderType == 'DRIVER';
}
