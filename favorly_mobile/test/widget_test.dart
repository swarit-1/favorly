import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:favorly_mobile/main.dart';

void main() {
  testWidgets('app bar is branded Favorly on every tab', (tester) async {
    await tester.pumpWidget(const FavorlyApp());

    expect(find.widgetWithText(AppBar, 'Favorly'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));

    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Favorly'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
  });
}
