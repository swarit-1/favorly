// The hero journey on fixtures, no server: type the ladder ask, watch the
// three steps, land on three people, invite Marcus, see the wait begin. Also
// the scope bounce: "build a deck" comes back right-sized.
//
// Skipped in a normal run; execute with
//
//   flutter test test/fixtures_journey_test.dart --dart-define=FIXTURES=true
//
// which is exactly the configuration the demo phones run until Trellis is
// live, so this is the rehearsal of the app half of the run of show.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:favorly_mobile/dev/fixtures.dart';
import 'package:favorly_mobile/providers/auth_provider.dart';
import 'package:favorly_mobile/screens/ask_screen.dart';
import 'package:favorly_mobile/screens/matches_screen.dart';
import 'package:favorly_mobile/theme/theme.dart';

class _SeededAuth extends AuthNotifier {
  _SeededAuth() {
    state = AuthState(userId: 'me-1', name: 'Sam Okonkwo', circleId: 'c-1');
  }
}

Widget _harness() => ProviderScope(
      overrides: [authProvider.overrideWith((ref) => _SeededAuth())],
      child: MaterialApp(theme: buildFavorlyTheme(), home: const AskScreen()),
    );

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_harness());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'ladder ask: three steps, three people, invite, waiting',
    skip: !kUseFixtures,
    (tester) async {
      FixtureWorld.reset();
      await _pump(tester);

      await tester.enterText(find.byType(TextField).first,
          'I need to borrow a ladder for an hour today');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find my neighbor'));
      await tester.pump(const Duration(milliseconds: 100));

      // The three honest steps show while the calls run.
      expect(find.text('Reading your ask'), findsOneWidget);
      expect(find.text('Looking around your circle'), findsOneWidget);
      expect(find.text('Picking three people'), findsOneWidget);

      // Let intake (600 ms) + helpers (450 ms) + the beat (350 ms) land.
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      expect(find.byType(MatchesScreen), findsOneWidget);
      expect(find.text('Borrow a ladder'), findsOneWidget);
      expect(find.text('Marcus Hill'), findsOneWidget);
      expect(find.text('Elena Vasquez'), findsOneWidget);
      expect(find.text('Jordan Reyes'), findsOneWidget);
      expect(find.text('You · Nora · Marcus'), findsOneWidget);

      await tester.tap(find.text('Ask Marcus'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Waiting on Marcus'), findsOneWidget);
      // Nobody else can be asked while the invite is out.
      final elena = find.widgetWithText(FilledButton, 'Ask Elena');
      expect(tester.widget<FilledButton>(elena).onPressed, isNull);

      FixtureWorld.reset();
    },
  );

  testWidgets(
    'a whole project bounces with a neighbor-sized rewrite',
    skip: !kUseFixtures,
    (tester) async {
      FixtureWorld.reset();
      await _pump(tester);

      await tester.enterText(
          find.byType(TextField).first, 'help me build a deck this month');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find my neighbor'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      expect(
          find.textContaining('more than one favor'), findsOneWidget);
      expect(find.textContaining('frame and raise one wall'), findsOneWidget);
      expect(find.text('Use that'), findsOneWidget);
      expect(find.text('Reword it'), findsOneWidget);

      // "Use that" re-submits with confirm_right_sized and sails through.
      await tester.tap(find.text('Use that'));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.byType(MatchesScreen), findsOneWidget);

      FixtureWorld.reset();
    },
  );
}
