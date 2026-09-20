import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';

class Trip {
  final String id;
  final String shopperId;
  final String circleId;
  final String store;
  final DateTime departAt;
  final String status;

  Trip({
    required this.id,
    required this.shopperId,
    required this.circleId,
    required this.store,
    required this.departAt,
    required this.status,
  });

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      id: json['id'] ?? '',
      shopperId: json['shopper_id'] ?? '',
      circleId: json['circle_id'] ?? '',
      store: json['store'] ?? '',
      departAt: DateTime.parse(json['depart_at'] ?? DateTime.now().toIso8601String()),
      status: json['status'] ?? 'open',
    );
  }
}

class TripsState {
  final List<Trip> trips;
  final Trip? currentTrip;
  final bool isLoading;
  final String? error;

  TripsState({
    this.trips = const [],
    this.currentTrip,
    this.isLoading = false,
    this.error,
  });

  TripsState copyWith({
    List<Trip>? trips,
    Trip? currentTrip,
    bool? isLoading,
    String? error,
  }) {
    return TripsState(
      trips: trips ?? this.trips,
      currentTrip: currentTrip ?? this.currentTrip,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class TripsNotifier extends StateNotifier<TripsState> {
  TripsNotifier() : super(TripsState());

  Future<String> createTrip({
    required String store,
    required DateTime departAt,
    required String userId,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await ApiClient.createTrip(
        store: store,
        departAt: departAt,
        userId: userId,
      );

      final trip = Trip.fromJson(response);
      state = state.copyWith(
        isLoading: false,
        currentTrip: trip,
      );
      return trip.id;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> fetchTrip(String tripId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await ApiClient.getTrip(tripId);
      final trip = Trip.fromJson(response);
      state = state.copyWith(
        isLoading: false,
        currentTrip: trip,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> fetchTrips(String circleId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await ApiClient.listTrips(circleId);
      final trips = response.map((t) => Trip.fromJson(t)).toList();
      state = state.copyWith(
        isLoading: false,
        trips: trips,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }
}

final tripsProvider = StateNotifierProvider<TripsNotifier, TripsState>(
  (ref) => TripsNotifier(),
);
