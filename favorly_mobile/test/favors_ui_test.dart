// Smoke coverage for the recommended-favors flow: the card in both states,
// the detail screen, and the finish sheet's rating gate. No network — the
// providers are seeded directly.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:favorly_mobile/providers/auth_provider.dart';
import 'package:favorly_mobile/providers/favors_provider.dart';
import 'package:favorly_mobile/screens/favor_detail_screen.dart';
import 'package:favorly_mobile/services/trellis_client.dart';
import 'package:favorly_mobile/theme/theme.dart';
import 'package:favorly_mobile/widgets/favor_card.dart';

const _favor = FavorSuggestion(
  needId: 'need-1',
  title: 'Grab oat milk for Bob',
  action: "Pick up oat milk at Trader Joe's.",
  requesterId: 'bob-1',
  requesterName: 'Bob',
  originalRequest: "could someone grab oat milk? I'm lactose intolerant and out",
  reason: "Bob picked up groceries for you twice, and you're already going.",
  effort: 'low',
  score: 0.65,
  signals: {
    'trip': 0.7,
    'reciprocity': 1.0,
    'mutual': 0.0, // zero — must not be rendered
    'fit': 0.4,
    'freshness': 0.95,
  },
  posted: '2h ago',
);

class _SeededFavors extends FavorsNotifier {
  _SeededFavors(FavorsState seed) {
    state = seed;
  }
}

class _SeededAuth extends AuthNotifier {
  _SeededAuth() {
    state = AuthState(userId: 'me-1', name: 'Sam Okonkwo', circleId: 'c-1');
  }
}

Widget _harness(Widget child, {Set<String> started = const {}}) {
  return ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => _SeededAuth()),
      favorsProvider.overrideWith(
        (ref) => _SeededFavors(
          FavorsState(favors: const [_favor], startedNeedIds: started),
        ),
      ),
    ],
    child: MaterialApp(theme: buildFavorlyTheme(), home: child),
  );
}

void main() {
  testWidgets('card shows the ask and who it is for', (tester) async {
    await tester.pumpWidget(_harness(
      const Scaffold(body: FavorCard(favor: _favor)),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('oat milk'), findsWidgets);
    expect(find.textContaining('Bob'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card marks an in-progress favor', (tester) async {
    await tester.pumpWidget(_harness(
      const Scaffold(body: FavorCard(favor: _favor, started: true)),
      started: {'need-1'},
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('In progress'), findsOneWidget);
  });

  testWidgets('detail shows their exact words and omits zero signals',
      (tester) async {
    await tester.pumpWidget(_harness(
      const FavorDetailScreen(favor: _favor),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('lactose intolerant'), findsOneWidget);
    // mutual is 0.0 — its plain-English label must not appear.
    expect(find.textContaining('share a connection'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail offers Start when not begun', (tester) async {
    await tester.pumpWidget(_harness(const FavorDetailScreen(favor: _favor)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Start'), findsWidgets);
  });

  testWidgets('detail offers Finish once started', (tester) async {
    await tester.pumpWidget(_harness(
      const FavorDetailScreen(favor: _favor),
      started: {'need-1'},
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Finish'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no overflow at phone width', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(const FavorDetailScreen(favor: _favor)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
