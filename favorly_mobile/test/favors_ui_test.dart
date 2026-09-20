// Smoke coverage for the favors flow: the card, the detail screen in both of
// its moods, the one-at-a-time rule, and the home screen's blue box. No
// network, the providers are seeded directly.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:favorly_mobile/models/favor_category.dart';
import 'package:favorly_mobile/providers/auth_provider.dart';
import 'package:favorly_mobile/providers/favors_provider.dart';
import 'package:favorly_mobile/screens/favor_detail_screen.dart';
import 'package:favorly_mobile/screens/trips_screen.dart';
import 'package:favorly_mobile/services/trellis_client.dart';
import 'package:favorly_mobile/theme/theme.dart';
import 'package:favorly_mobile/widgets/favor_card.dart';
import 'package:favorly_mobile/widgets/favor_hero.dart';
import 'package:favorly_mobile/widgets/trip_hero.dart';

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
    'mutual': 0.0, // zero, must not be rendered
    'fit': 0.4,
    'freshness': 0.95,
  },
  posted: '2h ago',
);

/// A second favor, so "one at a time" has something to refuse.
const _other = FavorSuggestion(
  needId: 'need-2',
  title: 'Walk Dana’s dog',
  action: 'Take Pepper round the block.',
  requesterId: 'dana-1',
  requesterName: 'Dana',
  originalRequest: 'stuck at work, could anyone walk Pepper?',
  reason: 'You live on the same block.',
  effort: 'medium',
  score: 0.4,
  signals: {'mutual': 0.5},
  posted: '20m ago',
);

/// v2: a borrow they asked *you* for, by name.
const _invited = FavorSuggestion(
  needId: 'need-3',
  title: 'Borrow a ladder for an hour',
  action: 'Lend your ladder for about an hour today.',
  requesterId: 'swarit-1',
  requesterName: 'Swarit Rao',
  originalRequest: 'I need to borrow a ladder for an hour today',
  reason: 'You have a 6 ft ladder, and you both know Nora.',
  effort: 'low',
  score: 0,
  signals: {'capability': 1.0, 'tie': 0.6},
  posted: 'just now',
  category: FavorCategory.borrow,
  whenText: 'today',
  invited: true,
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

Widget _harness(Widget child, {FavorsState? seed}) {
  return ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => _SeededAuth()),
      favorsProvider.overrideWith(
        (ref) =>
            _SeededFavors(seed ?? const FavorsState(favors: [_favor])),
      ),
    ],
    child: MaterialApp(theme: buildFavorlyTheme(), home: child),
  );
}

void main() {
  testWidgets('card leads with the person, then the ask', (tester) async {
    await tester.pumpWidget(_harness(
      const Scaffold(body: FavorCard(favor: _favor)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Bob'), findsOneWidget);
    expect(find.textContaining('oat milk'), findsWidgets);
    // Why the two of you, on the row itself. The chevron is the whole call to
    // action: a blue "Take it on" on every row was five CTAs in a list.
    expect(find.textContaining('picked up groceries for you'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // The card never shows the favor you are on, so a full plate reads as
  // "later", not as "in progress".
  testWidgets('card says later while another favor is open', (tester) async {
    await tester.pumpWidget(_harness(
      const Scaffold(body: FavorCard(favor: _other, waiting: true)),
      seed: const FavorsState(favors: [_other], active: _favor),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Later'), findsOneWidget);
  });

  // v2: they asked for you by name. The card wears the eyebrow and the
  // category badge; the detail offers the quiet way to say no.
  testWidgets('invited favor pins the eyebrow and the category badge',
      (tester) async {
    await tester.pumpWidget(_harness(
      const Scaffold(body: FavorCard(favor: _invited)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('ASKED FOR YOU'), findsOneWidget);
    expect(find.byType(CategoryBadge), findsOneWidget);
    expect(find.byIcon(FavorCategory.borrow.icon), findsOneWidget);
  });

  testWidgets('invited detail offers Not this time', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(
      const FavorDetailScreen(favor: _invited),
      seed: const FavorsState(favors: [_invited]),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Not this time'), findsOneWidget);
    // The server's sentence carries the why; the raw signal map never renders.
    expect(find.textContaining('6 ft ladder'), findsWidgets);
  });

  testWidgets('borrow in progress says to close it out when it is back',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(
      const FavorDetailScreen(favor: _invited),
      seed: FavorsState(active: _invited, activeStartedAt: DateTime.now()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('back with you'), findsOneWidget);
  });

  testWidgets('detail shows their exact words and omits zero signals',
      (tester) async {
    await tester.pumpWidget(_harness(
      const FavorDetailScreen(favor: _favor),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('lactose intolerant'), findsOneWidget);
    // mutual is 0.0, so its plain-English label must not appear.
    expect(find.textContaining('share a connection'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail offers Start when not begun', (tester) async {
    await tester.pumpWidget(_harness(const FavorDetailScreen(favor: _favor)));
    await tester.pumpAndSettle();

    expect(find.text('Start this favor'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
      isNotNull,
    );
  });

  // The whole point of one at a time: a second favor cannot be started, and
  // the screen says whose turn it is instead of failing silently.
  testWidgets('detail refuses a second favor and names the first',
      (tester) async {
    await tester.pumpWidget(_harness(
      const FavorDetailScreen(favor: _other),
      seed: const FavorsState(favors: [_other], active: _favor),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('You are helping Bob'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
      isNull,
      reason: 'Start is disabled while another favor is open',
    );
  });

  testWidgets('detail turns into the person once it is yours', (tester) async {
    // Tall enough that the whole page is laid out: a ListView only builds
    // elements for what is on screen, and the connection block sits low.
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(
      const FavorDetailScreen(favor: _favor),
      seed: FavorsState(active: _favor, activeStartedAt: DateTime.now()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('You and Bob'), findsOneWidget);
    expect(find.textContaining('Wrap up with Bob'), findsOneWidget);
    // The ranking argument is over once you have said yes.
    expect(find.text('Why you'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no overflow at phone width, in either mood', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(const FavorDetailScreen(favor: _favor)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_harness(
      const FavorDetailScreen(favor: _favor),
      seed: FavorsState(active: _favor, activeStartedAt: DateTime.now()),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // The home screen is where the section actually lives. Rendering only the
  // card and the detail screen missed a layout crash here: SectionHeader has
  // an Expanded inside, so nesting it in another Row left it unbounded.
  group('home screen', () {
    Future<void> pumpHome(WidgetTester tester, FavorsState seed) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _SeededAuth()),
          favorsProvider.overrideWith((ref) => _SeededFavors(seed)),
        ],
        child: MaterialApp(
          theme: buildFavorlyTheme(),
          home: const TripsScreen(),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('renders with favors', (tester) async {
      await pumpHome(tester, const FavorsState(favors: [_favor]));
      expect(tester.takeException(), isNull);
      expect(find.text('Who needs you'), findsOneWidget);
      expect(find.byType(FavorHero), findsNothing);
    });

    // The ask: the blue box is the favor you are on, with the details you
    // need while you are out.
    testWidgets('the blue box is the favor in progress', (tester) async {
      await pumpHome(
        tester,
        FavorsState(
          favors: const [_other],
          active: _favor,
          activeStartedAt: DateTime.now(),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(FavorHero), findsOneWidget);
      expect(find.text('Bob'), findsWidgets);
      expect(find.textContaining('Wrap up with Bob'), findsOneWidget);
      // Their own ask, on the home screen, without another tap. The demo
      // store's trip names the same store, so this looks inside the hero.
      expect(
        find.descendant(
          of: find.byType(FavorHero),
          matching: find.textContaining('Trader Joe'),
        ),
        findsOneWidget,
      );
      // And the rest of the list steps back.
      expect(find.text('After this one'), findsOneWidget);
    });

    testWidgets('renders while refreshing', (tester) async {
      await pumpHome(
          tester, const FavorsState(favors: [_favor], isRefreshing: true));
      expect(tester.takeException(), isNull);
    });

    testWidgets('with no favor on your plate the trip keeps the blue box',
        (tester) async {
      await pumpHome(tester, const FavorsState());
      expect(tester.takeException(), isNull);
      expect(find.byType(FavorHero), findsNothing);
      expect(find.byType(TripHero), findsOneWidget);
      expect(find.text('Nobody needs a hand right now'), findsOneWidget);
    });

    testWidgets('shows an API failure instead of hiding it', (tester) async {
      await pumpHome(
        tester,
        const FavorsState(
          error: 'Recommendations failed: https://favorly-agents.vercel.app '
              'returned 500.',
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('favorly-agents.vercel.app'), findsOneWidget);
    });
  });
}
