import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/trellis_client.dart';

/// How long a cached list is trusted before it counts as stale. Stale data is
/// still shown instantly — staleness only tells the UI it is looking at
/// yesterday's news while the refresh lands.
const Duration kFavorsStaleAfter = Duration(minutes: 10);

/// Cache key for one person's last successful recommendation list.
String favorsCacheKey(String personId) => 'favors_cache_$personId';

class FavorsState {
  final List<FavorSuggestion> favors;

  /// Needs I have claimed and not yet finished.
  final Set<String> startedNeedIds;

  /// True only when there is nothing to show yet — a cached list means no spinner.
  final bool isLoading;

  /// A refresh running underneath a list that is already on screen.
  final bool isRefreshing;
  final String? error;

  /// When [favors] was last known good, from the network or from the cache.
  final DateTime? fetchedAt;

  const FavorsState({
    this.favors = const [],
    this.startedNeedIds = const {},
    this.isLoading = false,
    this.isRefreshing = false,
    this.error,
    this.fetchedAt,
  });

  /// Older than [kFavorsStaleAfter].
  ///
  /// A null [fetchedAt] is *not* stale: nothing has been fetched, so there is
  /// no old data to distrust. "Empty" and "out of date" are different states,
  /// and the UI should read [isLoading] for the first one.
  bool get isStale {
    final at = fetchedAt;
    if (at == null) return false;
    return DateTime.now().difference(at) >= kFavorsStaleAfter;
  }

  /// [error] and [fetchedAt] follow the app's copyWith convention: pass them to
  /// set them, leave them out to clear [error]; [fetchedAt] is kept when omitted.
  FavorsState copyWith({
    List<FavorSuggestion>? favors,
    Set<String>? startedNeedIds,
    bool? isLoading,
    bool? isRefreshing,
    String? error,
    DateTime? fetchedAt,
  }) {
    return FavorsState(
      favors: favors ?? this.favors,
      startedNeedIds: startedNeedIds ?? this.startedNeedIds,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      error: error,
      fetchedAt: fetchedAt ?? this.fetchedAt,
    );
  }
}

/// What a cache read produced: an empty list and a null timestamp when there
/// was nothing to read, or storage itself was unavailable.
class _CachedFavors {
  const _CachedFavors(this.favors, this.fetchedAt);

  final List<FavorSuggestion> favors;
  final DateTime? fetchedAt;

  bool get isEmpty => favors.isEmpty;
}

class FavorsNotifier extends StateNotifier<FavorsState> {
  FavorsNotifier() : super(const FavorsState());

  /// Show the cached list immediately, then refresh underneath it.
  ///
  /// With [force] the cache is skipped and the network is always hit.
  Future<void> load(String personId, {bool force = false}) async {
    var hasSomethingToShow = state.favors.isNotEmpty;

    if (!force) {
      final cached = await _readCache(personId);
      if (!cached.isEmpty) {
        hasSomethingToShow = true;
        state = state.copyWith(
          favors: cached.favors,
          isLoading: false,
          isRefreshing: true,
          fetchedAt: cached.fetchedAt,
        );
      }
    }

    if (!hasSomethingToShow) {
      state = state.copyWith(isLoading: true, isRefreshing: false);
    } else if (!state.isRefreshing) {
      state = state.copyWith(isLoading: false, isRefreshing: true);
    }

    try {
      final favors = await TrellisClient.recommendations(personId);
      // A failure here shouldn't sink the recommendations — the list is the
      // point, "already started" is a decoration on it.
      Set<String> started;
      try {
        started = await TrellisClient.needIdsClaimedBy(personId);
      } catch (_) {
        started = state.startedNeedIds;
      }

      final fetchedAt = DateTime.now();
      if (!mounted) return;
      state = state.copyWith(
        favors: favors,
        startedNeedIds: started,
        isLoading: false,
        isRefreshing: false,
        fetchedAt: fetchedAt,
      );
      await _writeCache(personId, favors, fetchedAt);
    } catch (e) {
      if (!mounted) return;
      // Keep whatever is on screen. A stale list plus a warning beats a blank one.
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        error: e.toString(),
      );
    }
  }

  /// Claim the favor. Shows as started right away and rolls back if the
  /// server disagrees.
  Future<void> start(String needId, String personId) async {
    if (state.startedNeedIds.contains(needId)) return;
    final before = state.startedNeedIds;
    state = state.copyWith(startedNeedIds: {...before, needId});

    try {
      await TrellisClient.claim(needId: needId, personId: personId);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(startedNeedIds: before, error: e.toString());
    }
  }

  /// Mark the favor done. It leaves [FavorsState.startedNeedIds] on success.
  Future<void> finish(String needId) async {
    final before = state.startedNeedIds;
    state = state.copyWith(
      startedNeedIds: before.where((id) => id != needId).toSet(),
    );

    try {
      await TrellisClient.fulfill(needId: needId);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(startedNeedIds: before, error: e.toString());
    }
  }

  /// Rate a finished favor. Nothing to roll back — only the error surfaces.
  Future<void> submitReview({
    required String needId,
    required String reviewerId,
    required int rating,
    String? comment,
  }) async {
    state = state.copyWith(error: null);
    try {
      await TrellisClient.review(
        needId: needId,
        reviewerId: reviewerId,
        rating: rating,
        comment: comment,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(error: e.toString());
    }
  }

  /// Drop a message the UI has already shown.
  void clearError() {
    state = state.copyWith(error: null);
  }

  Future<_CachedFavors> _readCache(String personId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(favorsCacheKey(personId));
      if (raw == null || raw.isEmpty) return const _CachedFavors([], null);

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const _CachedFavors([], null);
      final list = decoded['favors'];
      if (list is! List) return const _CachedFavors([], null);

      final favors = list
          .whereType<Map>()
          .map((f) => FavorSuggestion.fromJson(Map<String, dynamic>.from(f)))
          .toList();
      final fetchedAt = DateTime.tryParse('${decoded['fetched_at']}');
      return _CachedFavors(favors, fetchedAt);
    } catch (_) {
      // No storage, or a cache written by an older shape — refetch instead.
      return const _CachedFavors([], null);
    }
  }

  Future<void> _writeCache(
    String personId,
    List<FavorSuggestion> favors,
    DateTime fetchedAt,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        favorsCacheKey(personId),
        jsonEncode({
          'favors': favors.map((f) => f.toJson()).toList(),
          'fetched_at': fetchedAt.toIso8601String(),
        }),
      );
    } catch (_) {
      // Storage is a nicety here; the list is already in state.
    }
  }
}

final favorsProvider = StateNotifierProvider<FavorsNotifier, FavorsState>(
  (ref) => FavorsNotifier(),
);
