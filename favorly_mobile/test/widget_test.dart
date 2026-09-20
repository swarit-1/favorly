import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:favorly_mobile/main.dart';

/// A tall phone viewport so whole screens are built without scrolling.
Future<void> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const ProviderScope(child: FavorlyApp()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('feed shows the active trip and the tabs switch', (tester) async {
    await pumpApp(tester);

    expect(find.text("Trader Joe's"), findsWidgets);
    expect(find.text('Post a trip'), findsOneWidget);

    await tester.tap(find.text('Circle'));
    await tester.pumpAndSettle();
    expect(find.text('Maple St · Building B'), findsWidgets);
    expect(find.text('Ana Delgado (you)'), findsOneWidget);
    expect(find.text('Invite a neighbor'), findsOneWidget);

    await tester.tap(find.text('You'));
    await tester.pumpAndSettle();
    expect(find.text('Ana Delgado'), findsWidgets);
  });

  testWidgets('a neighbor types a list, reviews it, and attaches it', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('You'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chloe Marchetti'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trips'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add my list'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2 lemons\noat milk under \$5');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review list'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    expect(find.text('Lemons'), findsOneWidget);
    expect(find.text('Oat milk'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.text('Attach 2 items'));
    await tester.pumpAndSettle();
    expect(find.text('Your list is with Ana'), findsOneWidget);
  });

  testWidgets('posting a trip returns to the feed with a confirmation', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Post a trip'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Whole Foods');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Post trip'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Trip posted'), findsOneWidget);
    expect(find.text('Whole Foods'), findsWidgets);
  });
}
