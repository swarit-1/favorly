import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/notification_provider.dart';
import '../screens/notifications_sheet.dart';

class NotificationBell extends ConsumerWidget {
  const NotificationBell({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationState = ref.watch(notificationProvider);
    final unreadCount = notificationState.unreadCount;

    return Stack(
      alignment: Alignment.topRight,
      children: [
        GestureDetector(
          onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (context) => const NotificationsSheet(),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              CupertinoIcons.bell,
              size: 24,
              color: Colors.black87,
            ),
          ),
        ),
        if (unreadCount > 0)
          Positioned(
            right: 0,
            top: 0,
            child: AnimatedOpacity(
              opacity: 1.0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  unreadCount > 9 ? '9+' : '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
