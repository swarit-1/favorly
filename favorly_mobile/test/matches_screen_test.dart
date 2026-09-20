// MatchesScreen on the Appendix C helpers: three kinds of tie, the path
// strips, the reasons, and not a score in sight.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:favorly_mobile/dev/fixtures.dart';
import 'package:favorly_mobile/providers/auth_provider.dart';
import 'package:favorly_mobile/screens/matches_screen.dart';
import 'package:favorly_mobile/services/trellis_client.dart';
import 'package:favorly_mobile/theme/theme.dart';

class _SeededAuth extends AuthNotifier {
  _SeededAuth() {
    state = AuthState(userId: 'me-1', name: 'Sam Okonkwo', circleId: 'c-1');
  }
}

List<HelperMatch> _fixture({String? marcusStatus}) => [
      for (final raw in (fixtureHelpers['helpers'] as List).cast<Map>())
        () {
          final h = HelperMatch.fromJson(Map<String, dynamic>.from(raw));
          return h.personId == 'p-marcus'
              ? h.withInviteStatus(marcusStatus)
              : h;
        }(),
    ];

Widget _harness(List<HelperMatch> helpers) {
  return ProviderScope(
    overrides: [authProvider.overrideWith((ref) => _SeededAuth())],
    child: MaterialApp(
      theme: buildFavorlyTheme(),
      home: MatchesScreen(
        needId: 'need-1',
        title: 'Borrow a ladder',
        whenText: 'today',
        initialHelpers: helpers,
      ),
    ),
  );
}

Future<void> _pump(WidgetTester tester, List<HelperMatch> helpers) async {
  tester.view.physicalSize = const Size(430, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_harness(helpers));
  // Not pumpAndSettle: the waiting state pulses forever by design.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('three people, three ties, reasons, no numbers', (tester) async {
    await _pump(tester, _fixture());

    expect(find.text('Borrow a ladder'), findsOneWidget);
    expect(find.text('Marcus Hill'), findsOneWidget);
    expect(find.text('Elena Vasquez'), findsOneWidget);
    expect(find.text('Jordan Reyes'), findsOneWidget);

    expect(find.text('Friend of Nora'), findsOneWidget);
    expect(find.text('You know each other'), findsOneWidget);
    expect(find.text('New to the building'), findsOneWidget);

    // The path strip is the six-degrees idea, per card.
    expect(find.text('You · Nora · Marcus'), findsOneWidget);
    expect(find.text('You · Elena'), findsOneWidget);
    // A new face draws only the endpoints.
    expect(find.text('You · Jordan'), findsOneWidget);

    expect(find.text('Ask Marcus'), findsOneWidget);
    expect(find.text('Ask everyone instead'), findsOneWidget);

    // Never a score, a percentage, or a rank about a person.
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('0.'), findsNothing);
    expect(find.textContaining('rank'), findsNothing);
  });

  testWidgets('a pending invite pulses and the others step back',
      (tester) async {
    await _pump(tester, _fixture(marcusStatus: 'pending'));

    expect(find.text('Waiting on Marcus'), findsOneWidget);
    // No second invite while one is out.
    expect(find.text('Ask Elena'), findsOneWidget);
    final elenaButton =
        find.widgetWithText(FilledButton, 'Ask Elena');
    expect(tester.widget<FilledButton>(elenaButton).onPressed, isNull);
  });

  testWidgets('acceptance shows the spark, the unit, and Message',
      (tester) async {
    final helpers = _fixture(marcusStatus: 'accepted');
    await _pump(tester, helpers);

    expect(find.text('Marcus is in'), findsOneWidget);
    expect(find.text('You both follow F1.'), findsOneWidget);
    expect(find.text('Message Marcus'), findsOneWidget);
  });
}
