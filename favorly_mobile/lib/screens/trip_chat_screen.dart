import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/realtime_models.dart';
import '../providers/message_provider.dart';
import '../providers/auth_provider.dart';

class TripChatScreen extends ConsumerStatefulWidget {
  final String tripId;
  final String? senderName;

  const TripChatScreen({
    Key? key,
    required this.tripId,
    this.senderName,
  }) : super(key: key);

  @override
  ConsumerState<TripChatScreen> createState() => _TripChatScreenState();
}

class _TripChatScreenState extends ConsumerState<TripChatScreen> {
  final _messageController = TextEditingController();
  late final messageNotifier =
      ref.read(messageProvider(widget.tripId).notifier);

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(messageProvider(widget.tripId).notifier).load();
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final authState = ref.read(authProvider);
    if (authState.accessToken == null) return;

    _messageController.clear();
    await messageNotifier.send(text, authState.accessToken!);
  }

  @override
  Widget build(BuildContext context) {
    final messageState = ref.watch(messageProvider(widget.tripId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Chat'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: messageState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : messageState.messages.isEmpty
                    ? Center(
                        child: Text(
                          'No messages yet',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      )
                    : ListView.builder(
                        reverse: true,
                        itemCount: messageState.messages.length,
                        itemBuilder: (context, index) {
                          final message = messageState.messages[index];
                          final isOwn = message.senderId ==
                              ref.read(authProvider).userId;

                          return _MessageBubble(
                            message: message,
                            isOwn: isOwn,
                          );
                        },
                      ),
          ),
          if (messageState.error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                messageState.error!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          _MessageInput(
            controller: _messageController,
            onSend: _sendMessage,
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isOwn;

  const _MessageBubble({
    required this.message,
    required this.isOwn,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment:
            isOwn ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isOwn)
            CircleAvatar(
              radius: 16,
              child: Text(
                message.senderName[0].toUpperCase(),
              ),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isOwn)
                  Text(
                    message.senderName,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isOwn
                        ? Colors.blue[500]
                        : Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    message.body,
                    style: TextStyle(
                      color: isOwn ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _formatTime(message.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isOwn)
            CircleAvatar(
              radius: 16,
              child: Text(
                message.senderName[0].toUpperCase(),
              ),
            ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) {
      return 'now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${dateTime.month}/${dateTime.day}';
    }
  }
}

class _MessageInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const _MessageInput({
    required this.controller,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                maxLines: null,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton(
              onPressed: onSend,
              mini: true,
              child: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
