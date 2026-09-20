import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/realtime_models.dart';

class LocationState {
  final Map<String, UserLocation> locations;
  final bool permissionDenied;
  final bool isSharing;
  final String? error;

  LocationState({
    this.locations = const {},
    this.permissionDenied = false,
    this.isSharing = false,
    this.error,
  });

  LocationState copyWith({
    Map<String, UserLocation>? locations,
    bool? permissionDenied,
    bool? isSharing,
    String? error,
  }) {
    return LocationState(
      locations: locations ?? this.locations,
      permissionDenied: permissionDenied ?? this.permissionDenied,
      isSharing: isSharing ?? this.isSharing,
      error: error,
    );
  }
}

class LocationNotifier extends StateNotifier<LocationState> {
  final String userId;
  final String circleId;
  Timer? _updateTimer;
  RealtimeChannel? _channel;

  LocationNotifier(this.userId, this.circleId) : super(LocationState());

  Future<void> requestPermission() async {
    try {
      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        state = state.copyWith(permissionDenied: true);
      } else if (permission == LocationPermission.deniedForever) {
        state = state.copyWith(permissionDenied: true);
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  void subscribe() {
    _channel = Supabase.instance.client
        .channel('user_locations:circle_id=eq.$circleId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'user_locations',
          callback: (payload) {
            final data = payload.newRecord;
            final location = UserLocation.fromJson(data);
            receiveLocation(location);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'user_locations',
          callback: (payload) {
            final data = payload.newRecord;
            final location = UserLocation.fromJson(data);
            receiveLocation(location);
          },
        )
        .subscribe();
  }

  void startSharing(String tripId) {
    if (state.permissionDenied) return;

    state = state.copyWith(isSharing: true);

    _updateTimer = Timer.periodic(Duration(seconds: 15), (_) async {
      try {
        final position = await Geolocator.getCurrentPosition();

        final now = DateTime.now();
        await Supabase.instance.client.from('user_locations').upsert(
          {
            'user_id': userId,
            'circle_id': circleId,
            'trip_id': tripId,
            'lat': position.latitude,
            'lng': position.longitude,
            'updated_at': now.toIso8601String(),
          },
          onConflict: 'user_id',
        );
      } catch (e) {
        state = state.copyWith(error: e.toString());
      }
    });
  }

  void stopSharing() {
    _updateTimer?.cancel();
    _updateTimer = null;
    state = state.copyWith(isSharing: false);
  }

  void receiveLocation(UserLocation location) {
    final updated = {...state.locations};
    updated[location.userId] = location;
    state = state.copyWith(locations: updated);
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }
}

final locationProvider = StateNotifierProvider.family<LocationNotifier, LocationState, (String, String)>(
  (ref, args) => LocationNotifier(args.$1, args.$2),
);
