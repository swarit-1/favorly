/// Real-time data models for messaging, notifications, and locations.
library;

/// A chat message in a trip.
class ChatMessage {
  final String id;
  final String tripId;
  final String senderId;
  final String senderName;
  final String body;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.tripId,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      tripId: json['trip_id'] as String,
      senderId: json['sender_id'] as String,
      senderName: json['sender_name'] as String? ?? 'Unknown',
      body: json['body'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'trip_id': tripId,
      'sender_id': senderId,
      'sender_name': senderName,
      'body': body,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// A user notification for trip events.
class AppNotification {
  final String id;
  final String userId;
  final String? tripId;
  final String kind; // new_message, trip_departed, request_accepted, item_substituted
  final String title;
  final String body;
  final bool read;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.userId,
    this.tripId,
    required this.kind,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      tripId: json['trip_id'] as String?,
      kind: json['kind'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      read: json['read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'trip_id': tripId,
      'kind': kind,
      'title': title,
      'body': body,
      'read': read,
      'created_at': createdAt.toIso8601String(),
    };
  }

  AppNotification copyWith({
    bool? read,
  }) {
    return AppNotification(
      id: id,
      userId: userId,
      tripId: tripId,
      kind: kind,
      title: title,
      body: body,
      read: read ?? this.read,
      createdAt: createdAt,
    );
  }
}

/// A user's GPS location for map display.
class UserLocation {
  final String userId;
  final double lat;
  final double lng;
  final String? tripId;
  final DateTime updatedAt;

  UserLocation({
    required this.userId,
    required this.lat,
    required this.lng,
    this.tripId,
    required this.updatedAt,
  });

  factory UserLocation.fromJson(Map<String, dynamic> json) {
    return UserLocation(
      userId: json['user_id'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      tripId: json['trip_id'] as String?,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'lat': lat,
      'lng': lng,
      'trip_id': tripId,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
