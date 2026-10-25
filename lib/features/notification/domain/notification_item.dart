class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    this.scheduleId,
    this.motorcycleId,
    this.readAt,
  });

  final String id;
  final String title;
  final String body;
  final String type;
  final DateTime createdAt;
  final String? scheduleId;
  final String? motorcycleId;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  factory NotificationItem.fromJson(Map<String, dynamic> json) =>
      NotificationItem(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        type: json['notification_type'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        scheduleId: json['schedule_id'] as String?,
        motorcycleId: json['motorcycle_id'] as String?,
        readAt: json['read_at'] == null
            ? null
            : DateTime.parse(json['read_at'] as String).toLocal(),
      );
}
