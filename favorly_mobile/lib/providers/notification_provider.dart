import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/realtime_models.dart';
import '../services/api_client.dart';

class NotificationState {
  final List<AppNotification> notifications;
  final int unreadCount;
  final bool isLoading;
  final String? error;

  NotificationState({
    this.notifications = const [],
    this.unreadCount = 0,
    this.isLoading = false,
    this.error,
  });

  NotificationState copyWith({
    List<AppNotification>? notifications,
    int? unreadCount,
    bool? isLoading,
    String? error,
  }) {
    return NotificationState(
      notifications: notifications ?? this.notifications,
      unreadCount: unreadCount ?? this.unreadCount,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class NotificationNotifier extends StateNotifier<NotificationState> {
  NotificationNotifier() : super(NotificationState());

  Future<void> load(String accessToken) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final rawNotifications = await ApiClient.getNotifications(accessToken: accessToken);
      final notifications = (rawNotifications as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((json) => AppNotification.fromJson(json))
          .toList();
      final unreadCount = notifications.where((n) => !n.read).length;
      state = state.copyWith(
        notifications: notifications,
        unreadCount: unreadCount,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> markRead(String notificationId, String accessToken) async {
    try {
      await ApiClient.markNotificationRead(
        notificationId: notificationId,
        accessToken: accessToken,
      );
      final updated = state.notifications
          .map((n) => n.id == notificationId ? n.copyWith(read: true) : n)
          .toList();
      final unreadCount = updated.where((n) => !n.read).length;
      state = state.copyWith(
        notifications: updated,
        unreadCount: unreadCount,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> markAllRead(String accessToken) async {
    try {
      await ApiClient.markAllNotificationsRead(accessToken: accessToken);
      final updated = state.notifications
          .map((n) => n.copyWith(read: true))
          .toList();
      state = state.copyWith(
        notifications: updated,
        unreadCount: 0,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  void receiveNotification(AppNotification notification) {
    state = state.copyWith(
      notifications: [notification, ...state.notifications],
      unreadCount: state.unreadCount + 1,
    );
  }
}

final notificationProvider = StateNotifierProvider<NotificationNotifier, NotificationState>(
  (ref) => NotificationNotifier(),
);
