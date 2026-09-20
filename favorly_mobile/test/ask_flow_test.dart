// The composer, no network: chips start a phrase without stealing typed
// words, the CTA follows the field, and a dead server is said out loud.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:favorly_mobile/providers/auth_provider.dart';
import 'package:favorly_mobile/screens/ask_screen.dart';
import 'package:favorly_mobile/theme/theme.dart';

class _SeededAuth extends AuthNotifier {
  _SeededAuth() {
    state = AuthState(userId: 'me-1', name: 'Sam Okonkwo', circleId: 'c-1');
  }
}

Widget _harness() {
  return ProviderScope(
    overrides: [authProvider.overrideWith((ref) => _SeededAuth())],
    child: MaterialApp(theme: buildFavorlyTheme(), home: const AskScreen()),
  );
}

void main() {
  testWidgets('CTA sleeps until there are words', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('What do you need a hand with?'), findsOneWidget);
    final cta = find.widgetWithText(FilledButton, 'Find my neighbor');
    expect(tester.widget<FilledButton>(cta).onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, 'Borrow a drill');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(cta).onPressed, isNotNull);
  });

  testWidgets('a category chip starts the phrase, typed words stay',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Borrow'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'Borrow ');

    // Their own words beat a chip.
    await tester.enterText(
        find.byType(TextField).first, 'Walk the dog at noon');
    await tester.tap(find.text('Ride'));
    await tester.pumpAndSettle();
    expect(field.controller!.text, 'Walk the dog at noon');
  });

  testWidgets('an unreachable server is named, not swallowed', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextField).first, 'Borrow a ladder for an hour');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find my neighbor'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Intake failed'), findsOneWidget);
  });
}
