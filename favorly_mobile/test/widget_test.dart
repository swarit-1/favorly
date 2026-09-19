import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:favorly_mobile/main.dart';

void main() {
  testWidgets('trips tab renders and nav switches', (tester) async {
    await tester.pumpWidget(const FavorlyApp());

    expect(find.text('Favorly'), findsOneWidget);
    expect(find.text("Trader Joe's"), findsOneWidget);
    expect(find.text('Add my list'), findsOneWidget);

    await tester.tap(find.text('Circle'));
    await tester.pumpAndSettle();

    expect(find.text('Not designed yet'), findsOneWidget);
  });

  testWidgets('post a trip pushes through to the voice confirmation',
      (tester) async {
    await tester.pumpWidget(const FavorlyApp());

    await tester.scrollUntilVisible(find.text('Post a trip'), 200);
    await tester.tap(find.text('Post a trip'));
    await tester.pumpAndSettle();
    expect(find.text('Store'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Say the trip'), 200);
    await tester.tap(find.text('Say the trip'));
    await tester.pumpAndSettle();
    expect(find.text('Here’s what we heard'), findsOneWidget);
    expect(find.text('Converted to trip details'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Looks good — post'), 200);
    await tester.tap(find.text('Looks good — post'));
    await tester.pumpAndSettle();
    expect(find.text('Add my list'), findsOneWidget);
  });
}
