import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:favorly_mobile/providers/favors_provider.dart';
import 'package:favorly_mobile/services/trellis_client.dart';

/// One favor exactly as Trellis sends it, copied from
/// `GET /people/{personId}/recommendations`.
Map<String, dynamic> sampleFavorJson() => {
      'need_id': 'need_7c21',
      'title': 'Grab oat milk on your Trader Joe\'s run',
      'action': 'Pick up 1 carton of oat milk',
      'requested_by': {'id': 'per_maya', 'display_name': 'Maya Chen'},
      'original_request':
          'out of oat milk and the baby drinks it by the gallon, anyone heading out?',
      'reason': "You're already going to Trader Joe's this afternoon.",
      'effort': 'low',
      'score': 0.87,
      'signals': {
        'trip': 0.95,
        'reciprocity': 0.6,
        'mutual': 0.4,
        'fit': 0.8,
        'freshness': 0.72,
      },
      'posted': '2h ago',
    };

void main() {
  group('FavorSuggestion.fromJson', () {
    test('parses the recommendations payload shape', () {
      final favor = FavorSuggestion.fromJson(sampleFavorJson());

      expect(favor.needId, 'need_7c21');
      expect(favor.title, "Grab oat milk on your Trader Joe's run");
      expect(favor.action, 'Pick up 1 carton of oat milk');
      expect(favor.requesterId, 'per_maya');
      expect(favor.requesterName, 'Maya Chen');
      expect(favor.originalRequest, contains('out of oat milk'));
      expect(favor.reason, "You're already going to Trader Joe's this afternoon.");
      expect(favor.effort, 'low');
      expect(favor.score, 0.87);
      expect(favor.posted, '2h ago');
      expect(favor.signals, {
        'trip': 0.95,
        'reciprocity': 0.6,
        'mutual': 0.4,
        'fit': 0.8,
        'freshness': 0.72,
      });
    });

    test('reads a whole favors envelope', () {
      final envelope = {
        'person_id': 'per_nivan',
        'decided_by': 'trellis-v1',
        'favors': [sampleFavorJson()],
      };

      final favors = (envelope['favors'] as List)
          .map((f) => FavorSuggestion.fromJson(f as Map<String, dynamic>))
          .toList();

      expect(favors, hasLength(1));
      expect(favors.single.needId, 'need_7c21');
    });

    test('survives integer-valued scores and signals', () {
      final json = sampleFavorJson()
        ..['score'] = 1
        ..['signals'] = {'trip': 1, 'reciprocity': 0};

      final favor = FavorSuggestion.fromJson(json);

      expect(favor.score, 1.0);
      expect(favor.signals['trip'], 1.0);
      expect(favor.signals['reciprocity'], 0.0);
    });

    test('tolerates missing fields rather than throwing', () {
      final favor = FavorSuggestion.fromJson({'need_id': 'need_bare'});

      expect(favor.needId, 'need_bare');
      expect(favor.title, '');
      expect(favor.requesterId, '');
      expect(favor.score, 0.0);
      expect(favor.signals, isEmpty);
    });
  });

  group('FavorSuggestion round-trip', () {
    // Equality against the sample would break every time the server adds a
    // field (`why` did exactly that). What the cache actually needs is that
    // encoding and decoding is lossless, so assert the fixed point.
    test('toJson is the shape fromJson reads back unchanged', () {
      final favor = FavorSuggestion.fromJson(sampleFavorJson());
      final encoded = favor.toJson();

      for (final entry in sampleFavorJson().entries) {
        expect(encoded[entry.key], entry.value, reason: entry.key);
      }
      expect(FavorSuggestion.fromJson(encoded).toJson(), encoded);
    });

    test('survives a trip through the cache encoding losslessly', () {
      final original = FavorSuggestion.fromJson(sampleFavorJson());

      final encoded = jsonEncode({
        'favors': [original.toJson()],
        'fetched_at': DateTime.now().toIso8601String(),
      });
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final restored = FavorSuggestion.fromJson(
        (decoded['favors'] as List).first as Map<String, dynamic>,
      );

      expect(restored.needId, original.needId);
      expect(restored.title, original.title);
      expect(restored.action, original.action);
      expect(restored.requesterId, original.requesterId);
      expect(restored.requesterName, original.requesterName);
      expect(restored.originalRequest, original.originalRequest);
      expect(restored.reason, original.reason);
      expect(restored.effort, original.effort);
      expect(restored.score, original.score);
      expect(restored.signals, original.signals);
      expect(restored.posted, original.posted);
      expect(restored.toJson(), original.toJson());
    });
  });

  group('FavorsState.isStale', () {
    test('is false just after a fetch', () {
      final state = FavorsState(fetchedAt: DateTime.now());

      expect(state.isStale, isFalse);
    });

    test('is false at nine minutes old', () {
      final state = FavorsState(
        fetchedAt: DateTime.now().subtract(const Duration(minutes: 9)),
      );

      expect(state.isStale, isFalse);
    });

    test('is true at ten minutes old', () {
      final state = FavorsState(
        fetchedAt: DateTime.now().subtract(const Duration(minutes: 10, seconds: 1)),
      );

      expect(state.isStale, isTrue);
    });

    test('is true well past the window', () {
      final state = FavorsState(
        fetchedAt: DateTime.now().subtract(const Duration(hours: 3)),
      );

      expect(state.isStale, isTrue);
    });

    // Documented choice: nothing fetched is not the same as out of date. With
    // no fetchedAt there is no old data to distrust, so isStale is false and
    // the UI reads isLoading instead.
    test('is false when nothing has been fetched yet', () {
      expect(const FavorsState().isStale, isFalse);
      expect(const FavorsState().fetchedAt, isNull);
    });
  });

  group('ClaimedFavor', () {
    Map<String, dynamic> claimedJson() => {
          'id': 'need_7c21',
          'body': 'out of oat milk, anyone heading out?',
          'status': 'claimed',
          'posted_by': {'id': 'per_maya', 'display_name': 'Maya Chen'},
          'claimed_by': 'per_nivan',
          'created_at': '2026-09-20T09:00:00.000Z',
        };

    test('reads the needs list shape', () {
      final claimed = ClaimedFavor.fromJson(claimedJson());

      expect(claimed.needId, 'need_7c21');
      expect(claimed.requesterId, 'per_maya');
      expect(claimed.requesterName, 'Maya Chen');
      expect(claimed.createdAt, DateTime.parse('2026-09-20T09:00:00.000Z'));
    });

    // The hero has to render something for a favor claimed on another device,
    // where the model's framing was never cached. Their own words stand in.
    test('stands in for a recommendation the device never saw', () {
      final favor = ClaimedFavor.fromJson(claimedJson()).toSuggestion(
        posted: '3h ago',
      );

      expect(favor.needId, 'need_7c21');
      expect(favor.title, 'out of oat milk, anyone heading out?');
      expect(favor.originalRequest, 'out of oat milk, anyone heading out?');
      expect(favor.requesterName, 'Maya Chen');
      expect(favor.posted, '3h ago');
      expect(favor.effort, isEmpty, reason: 'no effort was ever scored');
      expect(favor.signals, isEmpty);
    });
  });

  group('one favor at a time', () {
    final favor = FavorSuggestion.fromJson(sampleFavorJson());

    test('an empty plate can take anything on', () {
      const state = FavorsState();

      expect(state.hasActive, isFalse);
      expect(state.isActive('need_7c21'), isFalse);
      expect(state.canStart('need_7c21'), isTrue);
    });

    test('a full plate only allows the favor already on it', () {
      final state = FavorsState(active: favor);

      expect(state.hasActive, isTrue);
      expect(state.isActive('need_7c21'), isTrue);
      expect(state.canStart('need_7c21'), isTrue,
          reason: 'reopening the one you are on is not a second favor');
      expect(state.canStart('need_other'), isFalse);
    });

    test('finishing clears the plate, and only through clearActive', () {
      final state = FavorsState(active: favor, activeStartedAt: DateTime.now());

      // copyWith treats a missing argument as "keep", so null alone cannot
      // clear it; that is what clearActive is for.
      expect(state.copyWith(isRefreshing: true).active, favor);
      expect(state.copyWith(clearActive: true).active, isNull);
      expect(state.copyWith(clearActive: true).activeStartedAt, isNull);
      expect(state.copyWith(clearActive: true).canStart('need_other'), isTrue);
    });
  });

  group('FavorsState defaults and copyWith', () {
    test('a fresh state shows nothing and is idle', () {
      const state = FavorsState();

      expect(state.favors, isEmpty);
      expect(state.active, isNull);
      expect(state.activeStartedAt, isNull);
      expect(state.isLoading, isFalse);
      expect(state.isRefreshing, isFalse);
      expect(state.error, isNull);
    });

    test('copyWith keeps untouched fields and clears error when omitted', () {
      final favor = FavorSuggestion.fromJson(sampleFavorJson());
      final fetchedAt = DateTime.now();
      final startedAt = DateTime.now();
      final state = FavorsState(
        favors: [favor],
        active: favor,
        activeStartedAt: startedAt,
        error: 'boom',
        fetchedAt: fetchedAt,
      );

      final next = state.copyWith(isRefreshing: true);

      expect(next.favors, [favor]);
      expect(next.active, favor);
      expect(next.activeStartedAt, startedAt);
      expect(next.fetchedAt, fetchedAt);
      expect(next.isRefreshing, isTrue);
      expect(next.error, isNull, reason: 'error is per-update, not sticky');
    });

    test('copyWith carries a new error over a kept list', () {
      final favor = FavorSuggestion.fromJson(sampleFavorJson());
      final state = FavorsState(favors: [favor], fetchedAt: DateTime.now());

      final next = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        error: 'refresh failed',
      );

      expect(next.favors, hasLength(1), reason: 'cache survives a failed refresh');
      expect(next.error, 'refresh failed');
    });
  });

  group('favorsCacheKey', () {
    test('is namespaced per person', () {
      expect(favorsCacheKey('per_nivan'), 'favors_cache_per_nivan');
      expect(favorsCacheKey('per_maya'), isNot(favorsCacheKey('per_nivan')));
    });
  });

  group('kFavorsStaleAfter', () {
    test('is ten minutes', () {
      expect(kFavorsStaleAfter, const Duration(minutes: 10));
    });
  });
}
