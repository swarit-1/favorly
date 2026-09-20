// RouteScreen on the route-plan fixture: the computed distance line, the
// three ordered stops, explained suggestions, Add re-planning through
// extra_items, Skip removing from view, and the over-cap warning.
//
// The screen takes its planner as a parameter, so this runs through the same
// fixture data the FIXTURES=true demo build uses without needing the
// dart-define.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:favorly_mobile/dev/fixtures.dart';
import 'package:favorly_mobile/models/route_models.dart';
import 'package:favorly_mobile/screens/route_screen.dart';
import 'package:favorly_mobile/theme/theme.dart';
import 'package:favorly_mobile/widgets/buttons.dart';

/// The calls the screen made, so re-planning can be asserted on the wire
/// shape and not just the pixels.
final List<List<Map<String, dynamic>>> plannerCalls = [];

Future<RoutePlan> _fixturePlanner(
  String tripId, {
  List<Map<String, dynamic>>? extraItems,
}) async {
  plannerCalls.add(extraItems ?? const []);
  return RoutePlan.fromJson(fixtureRoutePlan(tripId, extraItems ?? const []));
}

Future<void> _pump(WidgetTester tester) async {
  plannerCalls.clear();
  tester.view.physicalSize = const Size(430, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildFavorlyTheme(),
      home: const RouteScreen(tripId: 'trip-1', planner: _fixturePlanner),
    ),
  );
  await tester.pumpAndSettle();
}

double _dy(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void main() {
  testWidgets('distance line, three stops in order, suggestions, caps',
      (tester) async {
    await _pump(tester);

    // Computed from the response, worded exactly, no dash.
    expect(find.text('212 m instead of 480 m'), findsOneWidget);

    // The three stops, top to bottom in visit order.
    expect(find.text('Produce'), findsOneWidget);
    expect(find.text('Dairy'), findsOneWidget);
    expect(find.text('Pantry'), findsOneWidget);
    expect(_dy(tester, 'Produce'), lessThan(_dy(tester, 'Dairy')));
    expect(_dy(tester, 'Dairy'), lessThan(_dy(tester, 'Pantry')));

    // Person first on every item.
    expect(find.textContaining('Bananas x2 for Grace'), findsOneWidget);
    expect(find.textContaining('Pasta x2 for Dev'), findsOneWidget);

    // Each suggestion shows its reason; a real detour says what it adds.
    expect(find.text('Milk for Grace'), findsOneWidget);
    expect(
      find.text('Grace needs milk. Dairy is already on your route. Adds 0 m.'),
      findsOneWidget,
    );
    expect(find.text('Adds 12 m'), findsOneWidget);

    // Caps: person, running total, their limit.
    expect(find.text('Grace · \$12.50 of \$40'), findsOneWidget);
    expect(find.text('Dev · \$26.75 of \$25'), findsOneWidget);
  });

  testWidgets('Add re-plans with the item in extra_items and the card goes',
      (tester) async {
    await _pump(tester);
    expect(plannerCalls, hasLength(1));

    // The first Add belongs to the first suggestion, the milk.
    await tester.tap(find.widgetWithText(FButton, 'Add').first);
    await tester.pumpAndSettle();

    // The re-plan carried the accepted item in the frozen extra_items shape.
    expect(plannerCalls, hasLength(2));
    expect(plannerCalls.last, [
      {'name': 'milk', 'qty': 1, 'section': 'dairy'},
    ]);

    // The suggestion card is gone; the milk now rides the dairy stop.
    expect(find.text('Milk for Grace'), findsNothing);
    expect(
      find.text('Grace needs milk. Dairy is already on your route. Adds 0 m.'),
      findsNothing,
    );
    expect(find.textContaining('Milk for Grace'), findsOneWidget);

    // Dairy was already on the route, so the walk did not grow.
    expect(find.text('212 m instead of 480 m'), findsOneWidget);

    // Grace's running total moved with the accepted item.
    expect(find.text('Grace · \$17.00 of \$40'), findsOneWidget);
  });

  testWidgets('Skip removes the card from view without a re-plan',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.widgetWithText(FButton, 'Skip').first);
    await tester.pumpAndSettle();

    expect(find.text('Milk for Grace'), findsNothing);
    expect(find.textContaining('Milk'), findsNothing);
    expect(plannerCalls, hasLength(1));
  });

  testWidgets('an over cap renders the warning', (tester) async {
    await _pump(tester);

    expect(find.text("Over Dev's cap"), findsOneWidget);
    expect(find.text('Over cap'), findsOneWidget);
  });
}
