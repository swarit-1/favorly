import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/realtime_models.dart';
import '../services/api_client.dart';

class MessageState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final String? error;

  MessageState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
  });

  MessageState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    String? error,
  }) {
    return MessageState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class MessageNotifier extends StateNotifier<MessageState> {
  final String tripId;

  MessageNotifier(this.tripId) : super(MessageState());

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final rawMessages = await ApiClient.getMessages(tripId: tripId);
      final messages = (rawMessages as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((json) => ChatMessage.fromJson(json))
          .toList();
      state = state.copyWith(
        messages: messages,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> send(String body, String accessToken) async {
    try {
      final rawMessage = await ApiClient.postMessage(
        tripId: tripId,
        body: body,
        accessToken: accessToken,
      );
      final message = ChatMessage.fromJson(rawMessage);
      state = state.copyWith(
        messages: [message, ...state.messages],
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  void receiveMessage(ChatMessage message) {
    state = state.copyWith(
      messages: [message, ...state.messages],
    );
  }
}

final messageProvider = StateNotifierProvider.family<MessageNotifier, MessageState, String>(
  (ref, tripId) => MessageNotifier(tripId),
);
