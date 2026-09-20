// The Web tab, driven off a fixture shaped like a real /graph response
// (14 people, 17 ties, three communities and three isolates), so the layout
// and the reasoning are exercised at phone width without a server.
//
// No golden images: what matters here is that the direction of a favor
// survives to the screen and that a signal which scored zero is absent
// rather than drawn as an empty bar. Those are assertions, not pixels.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:favorly_mobile/models/favor_category.dart';
import 'package:favorly_mobile/providers/asks_provider.dart';
import 'package:favorly_mobile/providers/auth_provider.dart';
import 'package:favorly_mobile/providers/favors_provider.dart';
import 'package:favorly_mobile/providers/graph_provider.dart';
import 'package:favorly_mobile/screens/web_screen.dart';
import 'package:favorly_mobile/services/trellis_client.dart';
import 'package:favorly_mobile/theme/theme.dart';
import 'package:favorly_mobile/widgets/favor_graph_view.dart';

const _me = 'n13';

const _nodes = <GraphNode>[
      GraphNode(id: 'n0', name: "Bob (Requester 1)", degree: 2, cluster: 0),
      GraphNode(id: 'n1', name: "Dev Patel", degree: 2, cluster: 1),
      GraphNode(id: 'n2', name: "Ana (Shopper)", degree: 5, cluster: 0),
      GraphNode(id: 'n3', name: "Joshua Wu", degree: 2, cluster: 0),
      GraphNode(id: 'n4', name: "Marcus Hill", degree: 0, cluster: 5),
      GraphNode(id: 'n5', name: "Elena Vasquez", degree: 4, cluster: 1),
      GraphNode(id: 'n6', name: "Grace Adebayo", degree: 2, cluster: 2),
      GraphNode(id: 'n7', name: "Joshua Wu", degree: 0, cluster: 4),
      GraphNode(id: 'n8', name: "Jordan Reyes", degree: 1, cluster: 1),
      GraphNode(id: 'n9', name: "Joshua Wu", degree: 0, cluster: 3),
      GraphNode(id: 'n10', name: "Charlie (Requester 2)", degree: 2, cluster: 0),
      GraphNode(id: 'n11', name: "Sam Okonkwo", degree: 5, cluster: 1),
      GraphNode(id: 'n12', name: "Priya Raman", degree: 2, cluster: 2),
      GraphNode(id: 'n13', name: "Maya Chen", degree: 3, cluster: 2),
];

const _edges = <GraphEdge>[

      GraphEdge(src: 'n2', dst: 'n0', kind: 'favor', strength: 0.993),
      GraphEdge(src: 'n0', dst: 'n2', kind: 'favor', strength: 1.638),
      GraphEdge(src: 'n0', dst: 'n10', kind: 'favor', strength: 0.843),
      GraphEdge(src: 'n2', dst: 'n3', kind: 'favor', strength: 0.667),
      GraphEdge(src: 'n10', dst: 'n3', kind: 'favor', strength: 0.815),
      GraphEdge(src: 'n11', dst: 'n2', kind: 'favor', strength: 1.744),
      GraphEdge(src: 'n13', dst: 'n2', kind: 'favor', strength: 1.381),
      GraphEdge(src: 'n11', dst: 'n6', kind: 'favor', strength: 1.632),
      GraphEdge(src: 'n11', dst: 'n1', kind: 'favor', strength: 1.476),
      GraphEdge(src: 'n13', dst: 'n12', kind: 'favor', strength: 1.578),
      GraphEdge(src: 'n2', dst: 'n5', kind: 'favor', strength: 1.292),
      GraphEdge(src: 'n5', dst: 'n13', kind: 'favor', strength: 1.526),
      GraphEdge(src: 'n12', dst: 'n6', kind: 'favor', strength: 1.687),
      GraphEdge(src: 'n1', dst: 'n5', kind: 'favor', strength: 1.428),
      GraphEdge(src: 'n13', dst: 'n5', kind: 'favor', strength: 0.996),
      GraphEdge(src: 'n11', dst: 'n5', kind: 'favor', strength: 0.997),
      GraphEdge(src: 'n11', dst: 'n8', kind: 'favor', strength: 2.996),
];

const _favor = FavorSuggestion(
  needId: 'need-1',
  title: 'Grab a big bag of onions for Elena',
  action: "Pick up onions at Trader Joe's.",
  requesterId: 'n6',
  requesterName: 'Elena Vasquez',
  originalRequest: 'big bag of onions if someone has room?',
  reason: 'Elena picked up groceries for you 2 times recently, and you both '
      'know Ana. Elena needs big bag of onions.',
  effort: 'low',
  score: 0.44,
  signals: {
    'trip': 0.0,
    'reciprocity': 1.0,
    'mutual': 0.5,
    'fit': 0.0,
    'affinity': 0.0,
    'freshness': 0.72,
  },
  why: MatchEvidence(
    weights: {
      'trip': 0.3,
      'reciprocity': 0.25,
      'mutual': 0.15,
      'fit': 0.15,
      'affinity': 0.1,
      'freshness': 0.05,
    },
    mutualNames: ['Ana (Shopper)'],
    favorCount: 2,
  ),
  posted: '4h ago',
);

class _SeededAuth extends AuthNotifier {
  _SeededAuth() {
    state = AuthState(userId: _me, name: 'Maya Chen', circleId: 'c-1');
  }
}

class _SeededFavors extends FavorsNotifier {
  _SeededFavors() {
    state = const FavorsState(favors: [_favor]);
  }
}

const _thread = FavorThread(
  otherId: 'n8',
  otherName: 'Elena Vasquez',
  given: ThreadDirection(count: 1, strength: 0.9),
  received: ThreadDirection(count: 2, strength: 1.5),
  mutuals: ['Ana (Shopper)', 'Sam Okonkwo'],
  sharedClaims: [SharedClaim(kind: 'dietary', label: 'gluten free')],
);

Widget _harness() => ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _SeededAuth()),
        favorsProvider.overrideWith((ref) => _SeededFavors()),
        favorGraphProvider.overrideWith(
          (ref, id) async => const FavorGraph(nodes: _nodes, edges: _edges),
        ),
        favorThreadProvider.overrideWith((ref, key) async => _thread),
      ],
      child: MaterialApp(theme: buildFavorlyTheme(), home: const WebScreen()),
    );

void main() {
  testWidgets('the whole tab builds at phone width', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1180 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  // Tapping a neighbor opens what ties you to them, stated in the direction
  // it actually happened: "they helped you" must never read as "you owe".
  testWidgets('tapping a neighbor opens the thread, with direction intact',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    final state = tester.state<State<FavorGraphView>>(
      find.byType(FavorGraphView),
    ) as dynamic;
    // Tap a node by driving the same callback the hit test would.
    final elena = _nodes.firstWhere((n) => n.name == 'Elena Vasquez');
    (state.widget as FavorGraphView).onSelect!(elena);
    await tester.pumpAndSettle();

    // Both directions, each stated the way round it happened. Inverting
    // either one would turn a thank-you into a debt.
    expect(find.textContaining('Elena helped you 2 times'), findsOneWidget);
    expect(find.textContaining('You helped Elena 1 time'), findsOneWidget);
    expect(find.textContaining('You both know Ana'), findsOneWidget);
    expect(find.textContaining('gluten free'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // The breakdown is the point of the tab: it has to open, and it has to
  // show the fact behind each signal, not just a bar.
  testWidgets('a recommendation expands into the signals that fired',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('3 signals fired'), findsOneWidget);
    await tester.tap(find.text('3 signals fired'));
    await tester.pumpAndSettle();

    expect(find.text('They helped you'), findsOneWidget);
    expect(find.text('2 favors for you'), findsOneWidget);
    expect(find.text('Shared neighbors'), findsOneWidget);
    expect(find.text('Posted recently'), findsOneWidget);
    // Signals that scored zero are absent, not drawn as empty bars.
    expect(find.text('Already going'), findsNothing);
    expect(find.text('You know this need'), findsNothing);
    expect(tester.takeException(), isNull);

  });

  // v2: the degrees line under the map, and the ask's dashed path over it.
  testWidgets('the web carries the ask path and the degrees line',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final marcus = HelperMatch.fromJson({
      'person': {
        'id': 'n4',
        'display_name': 'Marcus Hill',
        'first_name': 'Marcus',
      },
      'rank': 1,
      'tie': 'friend_of_friend',
      'tie_label': 'Friend of Elena',
      'hops': 2,
      'path': [
        {'id': 'me', 'name': 'You'},
        {'id': 'n5', 'name': 'Elena'},
        {'id': 'n4', 'name': 'Marcus'},
      ],
      'headline': 'Has a 6 ft ladder',
      'where': '3 floors up',
      'reason': 'Has a ladder. You both know Elena.',
      'invite_status': 'pending',
    });
    final ask = MyAsk(
      need: const ParsedNeed(
        id: 'need-1',
        category: FavorCategory.borrow,
        title: 'Borrow a ladder',
        body: 'I need to borrow a ladder for an hour today',
      ),
      status: 'open',
      helpers: [marcus],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _SeededAuth()),
        favorsProvider.overrideWith((ref) => _SeededFavors()),
        favorGraphProvider.overrideWith(
          (ref, id) async => const FavorGraph(nodes: _nodes, edges: _edges),
        ),
        favorThreadProvider.overrideWith((ref, key) async => _thread),
        graphStatsProvider.overrideWith((ref, id) async => const GraphStats(
            people: 16, ties: 23, avgSeparation: 2.61, triangles: 7)),
        asksProvider.overrideWith((ref) => _SeededAsks(ask)),
      ],
      child:
          MaterialApp(theme: buildFavorlyTheme(), home: const WebScreen()),
    ));
    await tester.pumpAndSettle();

    final view =
        tester.widget<FavorGraphView>(find.byType(FavorGraphView));
    // "me" in the wire path resolves to the signed-in node id.
    expect(view.highlightPath, [_me, 'n5', 'n4']);
    expect(view.highlightSolid, isFalse);
    expect(find.textContaining('dashed blue path is your ask'), findsOneWidget);
    expect(
        find.text('Your building: 2.6 degrees apart'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _SeededAsks extends AsksNotifier {
  _SeededAsks(MyAsk ask) {
    state = AsksState(asks: [ask]);
  }
}
