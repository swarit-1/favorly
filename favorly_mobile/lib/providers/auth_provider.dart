import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';

class AuthState {
  final String? userId;
  final String? circleId;
  final String? name;
  final String? accessToken;
  final String? refreshToken;
  final String? bio;
  final String? photoUrl;
  final String? role;
  final String? addressUnit;
  final String? addressFloor;
  final String? addressBuzzer;
  final String? addressNotes;
  final List<String> dietary;
  final List<String> preferredStores;
  final List<String> availability;
  final String? error;
  final bool isLoading;

  AuthState({
    this.userId,
    this.circleId,
    this.name,
    this.accessToken,
    this.refreshToken,
    this.bio,
    this.photoUrl,
    this.role,
    this.addressUnit,
    this.addressFloor,
    this.addressBuzzer,
    this.addressNotes,
    this.dietary = const [],
    this.preferredStores = const [],
    this.availability = const [],
    this.error,
    this.isLoading = false,
  });

  AuthState copyWith({
    String? userId,
    String? circleId,
    String? name,
    String? accessToken,
    String? refreshToken,
    String? bio,
    String? photoUrl,
    String? role,
    String? addressUnit,
    String? addressFloor,
    String? addressBuzzer,
    String? addressNotes,
    List<String>? dietary,
    List<String>? preferredStores,
    List<String>? availability,
    String? error,
    bool? isLoading,
  }) {
    return AuthState(
      userId: userId ?? this.userId,
      circleId: circleId ?? this.circleId,
      name: name ?? this.name,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      bio: bio ?? this.bio,
      photoUrl: photoUrl ?? this.photoUrl,
      role: role ?? this.role,
      addressUnit: addressUnit ?? this.addressUnit,
      addressFloor: addressFloor ?? this.addressFloor,
      addressBuzzer: addressBuzzer ?? this.addressBuzzer,
      addressNotes: addressNotes ?? this.addressNotes,
      dietary: dietary ?? this.dietary,
      preferredStores: preferredStores ?? this.preferredStores,
      availability: availability ?? this.availability,
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

      final accessToken = response['access_token'] as String;
      final refreshToken = response['refresh_token'] as String;

      state = state.copyWith(
        isLoading: false,
        userId: response['user_id'],
        circleId: response['circle_id'],
        name: response['name'],
        accessToken: accessToken,
        refreshToken: refreshToken,
        bio: response['bio'] as String?,
        photoUrl: response['photo_url'] as String?,
        role: response['role'] as String?,
        addressUnit: response['address_unit'] as String?,
        addressFloor: response['address_floor'] as String?,
        addressBuzzer: response['address_buzzer'] as String?,
        addressNotes: response['address_notes'] as String?,
        dietary: List<String>.from(response['dietary'] as List? ?? []),
        preferredStores: List<String>.from(response['preferred_stores'] as List? ?? []),
        availability: List<String>.from(response['availability'] as List? ?? []),
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

      final accessToken = response['access_token'] as String;
      final refreshToken = response['refresh_token'] as String;

      state = state.copyWith(
        isLoading: false,
        userId: response['user_id'],
        circleId: response['circle_id'],
        name: response['name'],
        accessToken: accessToken,
        refreshToken: refreshToken,
        bio: response['bio'] as String?,
        photoUrl: response['photo_url'] as String?,
        role: response['role'] as String?,
        addressUnit: response['address_unit'] as String?,
        addressFloor: response['address_floor'] as String?,
        addressBuzzer: response['address_buzzer'] as String?,
        addressNotes: response['address_notes'] as String?,
        dietary: List<String>.from(response['dietary'] as List? ?? []),
        preferredStores: List<String>.from(response['preferred_stores'] as List? ?? []),
        availability: List<String>.from(response['availability'] as List? ?? []),
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

      final accessToken = response['access_token'] as String;
      final refreshToken = response['refresh_token'] as String;

      state = state.copyWith(
        isLoading: false,
        userId: response['user_id'],
        circleId: response['circle_id'],
        name: response['name'],
        accessToken: accessToken,
        refreshToken: refreshToken,
        bio: response['bio'] as String?,
        photoUrl: response['photo_url'] as String?,
        role: response['role'] as String?,
        addressUnit: response['address_unit'] as String?,
        addressFloor: response['address_floor'] as String?,
        addressBuzzer: response['address_buzzer'] as String?,
        addressNotes: response['address_notes'] as String?,
        dietary: List<String>.from(response['dietary'] as List? ?? []),
        preferredStores: List<String>.from(response['preferred_stores'] as List? ?? []),
        availability: List<String>.from(response['availability'] as List? ?? []),
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
