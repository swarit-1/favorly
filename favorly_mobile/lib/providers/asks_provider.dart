import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/trellis_client.dart';

/// The asks I have out right now, shared by the home card, the matches
/// screen, and the web view. Widgets own their own polling cadence; this
/// only holds the latest answer and knows how to refresh it.
class AsksState {
  const AsksState({
    this.asks = const [],
    this.isLoading = false,
    this.error,
    this.fetchedAt,
  });

  final List<MyAsk> asks;
  final bool isLoading;
  final String? error;
  final DateTime? fetchedAt;

  /// The ask the home card and the web highlight: the newest one still
  /// moving, or the most recent fulfilled one while it is still fresh.
  MyAsk? get current => asks.isEmpty ? null : asks.first;

  /// Anything still waiting on a neighbor?
  bool get hasOpen => asks.any((a) => !a.isFulfilled);

  AsksState copyWith({
    List<MyAsk>? asks,
    bool? isLoading,
    String? error,
    DateTime? fetchedAt,
  }) {
    return AsksState(
      asks: asks ?? this.asks,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      fetchedAt: fetchedAt ?? this.fetchedAt,
    );
  }
}

class AsksNotifier extends StateNotifier<AsksState> {
  AsksNotifier() : super(const AsksState());

  /// One fetch. Pollers call this on their own clock; a failure keeps the
  /// last good list on screen, because a blinking card is worse than a stale
  /// one for the four seconds until the next tick.
  Future<void> refresh(String personId) async {
    if (state.asks.isEmpty) {
      state = state.copyWith(isLoading: true);
    }
    try {
      final asks = await TrellisClient.myAsks(personId);
      if (!mounted) return;
      state = AsksState(asks: asks, fetchedAt: DateTime.now());
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final asksProvider = StateNotifierProvider<AsksNotifier, AsksState>(
  (ref) => AsksNotifier(),
);
