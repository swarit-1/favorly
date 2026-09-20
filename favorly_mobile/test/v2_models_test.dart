// v2 model coverage: the new wire shapes parse, and, the one that really
// matters, a favors cache written before v2 still decodes.

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:favorly_mobile/dev/fixtures.dart';
import 'package:favorly_mobile/models/favor_category.dart';
import 'package:favorly_mobile/services/trellis_client.dart';

/// A favor exactly as a pre-v2 build cached it in shared_preferences: no
/// category, no when_text, no invited.
Map<String, dynamic> preV2FavorJson() => {
      'need_id': 'need_7c21',
      'title': "Grab oat milk on your Trader Joe's run",
      'action': 'Pick up 1 carton of oat milk',
      'requested_by': {'id': 'per_maya', 'display_name': 'Maya Chen'},
      'original_request': 'out of oat milk, anyone heading out?',
      'reason': "You're already going this afternoon.",
      'effort': 'low',
      'score': 0.87,
      'signals': {'trip': 0.95},
      'posted': '2h ago',
      'why': {
        'weights': {'trip': 0.3},
        'mutual_names': ['Nora Chen'],
        'favor_count': 2,
      },
    };

void main() {
  group('FavorCategory', () {
    test('every wire value maps to its own case', () {
      expect(FavorCategory.fromWire('errand'), FavorCategory.errand);
      expect(FavorCategory.fromWire('borrow'), FavorCategory.borrow);
      expect(FavorCategory.fromWire('hands'), FavorCategory.hands);
      expect(FavorCategory.fromWire('skill'), FavorCategory.skill);
      expect(FavorCategory.fromWire('company'), FavorCategory.company);
      expect(FavorCategory.fromWire('ride'), FavorCategory.ride);
      expect(FavorCategory.fromWire('care'), FavorCategory.care);
      expect(FavorCategory.fromWire('other'), FavorCategory.other);
    });

    test('unknown and missing decode as errand', () {
      expect(FavorCategory.fromWire('petting_zoo'), FavorCategory.errand);
      expect(FavorCategory.fromWire(null), FavorCategory.errand);
      expect(FavorCategory.fromWire(''), FavorCategory.errand);
    });

    test('labels and icons are the documented ones', () {
      expect(FavorCategory.borrow.label, 'Borrow');
      expect(FavorCategory.care.label, 'Look after');
      expect(FavorCategory.other.label, 'Favor');
      expect(FavorCategory.errand.icon, CupertinoIcons.cart);
      expect(FavorCategory.skill.icon, CupertinoIcons.wrench);
    });
  });

  group('FavorSuggestion v2 fields', () {
    test('a pre-v2 cached map still decodes, with safe defaults', () {
      final favor = FavorSuggestion.fromJson(preV2FavorJson());

      expect(favor.needId, 'need_7c21');
      expect(favor.requesterName, 'Maya Chen');
      expect(favor.category, FavorCategory.errand);
      expect(favor.whenText, '');
      expect(favor.invited, isFalse);
      expect(favor.why.mutualNames, ['Nora Chen']);
    });

    test('v2 fields round-trip through toJson', () {
      final favor = FavorSuggestion.fromJson({
        ...preV2FavorJson(),
        'category': 'borrow',
        'when_text': 'today',
        'invited': true,
      });
      expect(favor.category, FavorCategory.borrow);
      expect(favor.whenText, 'today');
      expect(favor.invited, isTrue);

      final again = FavorSuggestion.fromJson(favor.toJson());
      expect(again.category, FavorCategory.borrow);
      expect(again.whenText, 'today');
      expect(again.invited, isTrue);
    });
  });

  group('HelperMatch', () {
    test('parses the Appendix C helper', () {
      final marcus = HelperMatch.fromJson(Map<String, dynamic>.from(
          (fixtureHelpers['helpers'] as List).first as Map));

      expect(marcus.personId, 'p-marcus');
      expect(marcus.displayName, 'Marcus Hill');
      expect(marcus.firstName, 'Marcus');
      expect(marcus.rank, 1);
      expect(marcus.tie, 'friend_of_friend');
      expect(marcus.tieLabel, 'Friend of Nora');
      expect(marcus.hops, 2);
      expect(marcus.path.map((p) => p.name), ['You', 'Nora', 'Marcus']);
      expect(marcus.headline, 'Has a 6 ft ladder');
      expect(marcus.where, '3 floors up');
      expect(marcus.spark, 'You both follow F1.');
      expect(marcus.inviteStatus, isNull);
      expect(marcus.isPending, isFalse);
    });

    test('falls back to the display name for a missing first name', () {
      final h = HelperMatch.fromJson({
        'person': {'id': 'x', 'display_name': 'Elena Vasquez'},
      });
      expect(h.firstName, 'Elena');
    });
  });

  group('IntakeResult', () {
    test('parses the in-scope fixture', () {
      final result = IntakeResult.fromJson(fixtureIntake);
      expect(result.isOk, isTrue);
      expect(result.need!.category, FavorCategory.borrow);
      expect(result.need!.title, 'Borrow a ladder');
      expect(result.need!.requires, ['ladder']);
      expect(result.need!.durationMinutes, 60);
      expect(result.scopeReply, isNull);
    });

    test('parses the too_big fixture', () {
      final result = IntakeResult.fromJson(fixtureIntakeTooBig);
      expect(result.isOk, isFalse);
      expect(result.scope, 'too_big');
      expect(result.need, isNull);
      expect(result.scopeReply, contains('more than one favor'));
      expect(result.rightSized, contains('one wall'));
    });
  });

  group('GraphStats and FulfillResult', () {
    test('parse the documented shapes', () {
      final stats = GraphStats.fromJson(
          {'people': 16, 'ties': 23, 'avg_separation': 2.61, 'triangles': 7});
      expect(stats.people, 16);
      expect(stats.avgSeparation, closeTo(2.61, 1e-9));

      final done = FulfillResult.fromJson({
        'first_favor_together': true,
        'separation': {'before': 2.61, 'after': 2.51},
      });
      expect(done.firstFavorTogether, isTrue);
      expect(done.separationAfter, closeTo(2.51, 1e-9));

      // An older server sends neither field.
      final old = FulfillResult.fromJson({'status': 'ok'});
      expect(old.firstFavorTogether, isFalse);
      expect(old.separationBefore, isNull);
    });
  });

  group('MyAsk via the fixture world', () {
    test('open, then pending after an invite', () {
      FixtureWorld.reset();
      expect(FixtureWorld.myAsks()['asks'], isEmpty);

      FixtureWorld.intake('I need to borrow a ladder for an hour today');
      var asks = (FixtureWorld.myAsks()['asks'] as List)
          .map((a) => MyAsk.fromJson(Map<String, dynamic>.from(a as Map)))
          .toList();
      expect(asks, hasLength(1));
      expect(asks.first.status, 'open');
      expect(asks.first.pending, isNull);
      expect(asks.first.helpers, hasLength(3));

      FixtureWorld.invite('p-marcus');
      asks = (FixtureWorld.myAsks()['asks'] as List)
          .map((a) => MyAsk.fromJson(Map<String, dynamic>.from(a as Map)))
          .toList();
      expect(asks.first.pending?.firstName, 'Marcus');
      // Pre-acceptance the location stays relative: never a unit number.
      expect(asks.first.pending?.where, isNot(contains('Unit')));
      FixtureWorld.reset();
    });

    test('a scripted too_big ask bounces with the rewrite', () {
      FixtureWorld.reset();
      final result = IntakeResult.fromJson(
          FixtureWorld.intake('help me build a deck this month'));
      expect(result.scope, 'too_big');
      expect(result.rightSized, isNotNull);

      // Confirming the rewrite skips the scope check.
      final again = IntakeResult.fromJson(FixtureWorld.intake(
        result.rightSized!,
        confirmRightSized: true,
      ));
      expect(again.isOk, isTrue);
      FixtureWorld.reset();
    });
  });
}
