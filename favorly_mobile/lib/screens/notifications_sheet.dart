import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/notification_provider.dart';
import '../providers/auth_provider.dart';

class NotificationsSheet extends ConsumerWidget {
  const NotificationsSheet({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationState = ref.watch(notificationProvider);
    final authState = ref.watch(authProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.5,
      builder: (context, scrollController) {
        return Material(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (notificationState.unreadCount > 0)
                      TextButton(
                        onPressed: () {
                          if (authState.accessToken != null) {
                            ref
                                .read(notificationProvider.notifier)
                                .markAllRead(authState.accessToken!);
                          }
                        },
                        child: const Text('Mark all read'),
                      ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: notificationState.notifications.isEmpty
                    ? Center(
                        child: Text(
                          'No notifications',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: notificationState.notifications.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final notification =
                              notificationState.notifications[index];
                          return ListTile(
                            title: Text(notification.title),
                            subtitle: Text(notification.body),
                            trailing: notification.read
                                ? null
                                : Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Colors.blue,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                            onTap: () async {
                              if (!notification.read &&
                                  authState.accessToken != null) {
                                await ref
                                    .read(notificationProvider.notifier)
                                    .markRead(
                                      notification.id,
                                      authState.accessToken!,
                                    );
                              }
                              if (notification.tripId != null) {
                                Navigator.pop(context);
                                context.push(
                                  '/trips/${notification.tripId}',
                                );
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
