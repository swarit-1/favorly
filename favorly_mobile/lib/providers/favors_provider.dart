import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/trellis_client.dart';
import '../util/format.dart';

/// How long a cached list is trusted before it counts as stale. Stale data is
/// still shown instantly, staleness only tells the UI it is looking at
/// yesterday's news while the refresh lands.
const Duration kFavorsStaleAfter = Duration(minutes: 10);

/// Cache key for one person's last successful recommendation list.
String favorsCacheKey(String personId) => 'favors_cache_$personId';

/// What you get back for trying to take a second favor on.
const String kOneAtATime =
    'One favor at a time. Wrap up the one you are on first.';

class FavorsState {
  /// Open favors waiting for someone, best first.
  final List<FavorSuggestion> favors;

  /// The one favor you are on the hook for right now, if any.
  ///
  /// One at a time on purpose: a favor is a thread between two people, and
  /// two half-finished threads are worth less than one you actually follow
  /// through on.
  final FavorSuggestion? active;

  /// When you took [active] on, when this device is the one that took it.
  /// Null after a fresh install that found the claim on the server instead.
  final DateTime? activeStartedAt;

  /// True only when there is nothing to show yet: a cached list means no spinner.
  final bool isLoading;

  /// A refresh running underneath a list that is already on screen.
  final bool isRefreshing;
  final String? error;

  /// When [favors] was last known good, from the network or from the cache.
  final DateTime? fetchedAt;

  const FavorsState({
    this.favors = const [],
    this.active,
    this.activeStartedAt,
    this.isLoading = false,
    this.isRefreshing = false,
    this.error,
    this.fetchedAt,
  });

  bool get hasActive => active != null;

  /// Is this the favor you are currently on?
  bool isActive(String needId) => active?.needId == needId;

  /// Can this favor be taken on, or is your plate full?
  bool canStart(String needId) => active == null || isActive(needId);

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

  /// [error] follows the app's copyWith convention: pass it to set it, leave
  /// it out to clear it. [active] is nullable in its own right, so it takes
  /// [clearActive] rather than reading a missing argument as "set to null".
  FavorsState copyWith({
    List<FavorSuggestion>? favors,
    FavorSuggestion? active,
    DateTime? activeStartedAt,
    bool clearActive = false,
    bool? isLoading,
    bool? isRefreshing,
    String? error,
    DateTime? fetchedAt,
  }) {
    return FavorsState(
      favors: favors ?? this.favors,
      active: clearActive ? null : (active ?? this.active),
      activeStartedAt:
          clearActive ? null : (activeStartedAt ?? this.activeStartedAt),
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      error: error,
      fetchedAt: fetchedAt ?? this.fetchedAt,
    );
  }
}

/// What a cache read produced: empty when there was nothing to read, or
/// storage itself was unavailable.
class _CachedFavors {
  const _CachedFavors(this.favors, this.fetchedAt,
      {this.active, this.activeStartedAt});

  final List<FavorSuggestion> favors;
  final DateTime? fetchedAt;
  final FavorSuggestion? active;
  final DateTime? activeStartedAt;

  static const empty = _CachedFavors([], null);

  bool get isEmpty => favors.isEmpty && active == null;
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
          active: cached.active,
          activeStartedAt: cached.activeStartedAt,
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
      // A failure here shouldn't sink the recommendations: the list is the
      // point, and the favor you are on is drawn from the cache anyway.
      List<ClaimedFavor>? claimed;
      try {
        claimed = await TrellisClient.claimedBy(personId);
      } catch (_) {
        claimed = null;
      }

      final fetchedAt = DateTime.now();
      if (!mounted) return;

      final active = claimed == null
          ? state.active
          : _reconcileActive(claimed, favors);
      final startedAt =
          active?.needId == state.active?.needId ? state.activeStartedAt : null;

      state = FavorsState(
        // The favor you are on lives in the hero, never twice on one screen.
        // The server already leaves claimed needs out of recommendations; this
        // is only here so a stale list cannot put it back.
        favors: favors.where((f) => f.needId != active?.needId).toList(),
        active: active,
        activeStartedAt: startedAt,
        fetchedAt: fetchedAt,
      );
      await _writeCache(personId);
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

  /// The server says which need you are on; this picks the best description of
  /// it. The recommendation that first surfaced the favor carries the model's
  /// framing and their exact words, so it wins over the bare need row, which
  /// is only a fallback for a device that never saw the recommendation.
  FavorSuggestion? _reconcileActive(
    List<ClaimedFavor> claimed,
    List<FavorSuggestion> fresh,
  ) {
    if (claimed.isEmpty) return null;
    final need = claimed.first;

    for (final known in [
      if (state.active != null) state.active!,
      ...state.favors,
      ...fresh,
    ]) {
      if (known.needId == need.needId) return known;
    }
    return need.toSuggestion(posted: agoLabel(need.createdAt));
  }

  /// Take the favor on. Shows as yours right away and rolls back if the
  /// server disagrees.
  ///
  /// Refused outright while another favor is open: [FavorsState.active] is
  /// one favor, not a queue.
  Future<void> start(FavorSuggestion favor, String personId) async {
    if (state.isActive(favor.needId)) return;
    if (state.hasActive) {
      state = state.copyWith(error: kOneAtATime);
      return;
    }

    state = state.copyWith(
      active: favor,
      activeStartedAt: DateTime.now(),
      // Taking it on pulls it out of the open list: it is no longer waiting
      // for someone, it is waiting on you.
      favors: state.favors.where((f) => f.needId != favor.needId).toList(),
    );

    try {
      await TrellisClient.claim(needId: favor.needId, personId: personId);
      await _writeCache(personId);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        clearActive: true,
        favors: [favor, ...state.favors],
        error: e.toString(),
      );
    }
  }

  /// Mark the favor done. Your plate is clear again on success.
  Future<void> finish(String needId, {String? personId}) async {
    final before = state.active;
    final beforeStartedAt = state.activeStartedAt;
    if (before?.needId == needId) state = state.copyWith(clearActive: true);

    try {
      await TrellisClient.fulfill(needId: needId);
      if (personId != null) await _writeCache(personId);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        active: before,
        activeStartedAt: beforeStartedAt,
        error: e.toString(),
      );
    }
  }

  /// Say how it went with the person you helped. Nothing to roll back, only
  /// the error surfaces.
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
      if (raw == null || raw.isEmpty) return _CachedFavors.empty;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return _CachedFavors.empty;
      final list = decoded['favors'];
      final favors = list is List
          ? list
              .whereType<Map>()
              .map((f) => FavorSuggestion.fromJson(Map<String, dynamic>.from(f)))
              .toList()
          : <FavorSuggestion>[];

      final rawActive = decoded['active'];
      final active = rawActive is Map
          ? FavorSuggestion.fromJson(Map<String, dynamic>.from(rawActive))
          : null;

      return _CachedFavors(
        favors,
        DateTime.tryParse('${decoded['fetched_at']}'),
        active: active,
        activeStartedAt: DateTime.tryParse('${decoded['active_started_at']}'),
      );
    } catch (_) {
      // No storage, or a cache written by an older shape: refetch instead.
      return _CachedFavors.empty;
    }
  }

  Future<void> _writeCache(String personId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        favorsCacheKey(personId),
        jsonEncode({
          'favors': state.favors.map((f) => f.toJson()).toList(),
          'fetched_at':
              (state.fetchedAt ?? DateTime.now()).toIso8601String(),
          'active': state.active?.toJson(),
          'active_started_at': state.activeStartedAt?.toIso8601String(),
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
