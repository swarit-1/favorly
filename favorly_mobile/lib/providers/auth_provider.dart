import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';

class AuthState {
  final String? userId;
  final String? circleId;
  final String? name;
  final String? accessToken;
  final String? error;
  final bool isLoading;

  AuthState({
    this.userId,
    this.circleId,
    this.name,
    this.accessToken,
    this.error,
    this.isLoading = false,
  });

  AuthState copyWith({
    String? userId,
    String? circleId,
    String? name,
    String? accessToken,
    String? error,
    bool? isLoading,
  }) {
    return AuthState(
      userId: userId ?? this.userId,
      circleId: circleId ?? this.circleId,
      name: name ?? this.name,
      accessToken: accessToken ?? this.accessToken,
      error: error,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthState());

  Future<void> signup({
    required String name,
    required String email,
    required String password,
    required String inviteCode,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await ApiClient.signup(
        name: name,
        email: email,
        password: password,
        inviteCode: inviteCode,
      );

      state = state.copyWith(
        isLoading: false,
        userId: response['user_id'],
        circleId: response['circle_id'],
        name: response['name'],
        accessToken: response['access_token'],
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await ApiClient.login(
        email: email,
        password: password,
      );

      state = state.copyWith(
        isLoading: false,
        userId: response['user_id'],
        circleId: response['circle_id'],
        name: response['name'],
        accessToken: response['access_token'],
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// DEV BYPASS: log in as a name from `users` / `people`, no credentials.
  Future<void> devLogin({required String name}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await ApiClient.devLogin(name: name);

      state = state.copyWith(
        isLoading: false,
        userId: response['user_id'],
        circleId: response['circle_id'],
        name: response['name'],
        accessToken: response['access_token'],
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void logout() {
    state = AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);
