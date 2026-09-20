// Covers the dev bypass on the login screen: in debug builds an email alone
// is enough. Delete alongside the bypass once real auth lands.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:favorly_mobile/screens/login_screen.dart';
import 'package:favorly_mobile/theme/theme.dart';
import 'package:favorly_mobile/widgets/buttons.dart';

Widget _harness() => ProviderScope(
      child: MaterialApp(theme: buildFavorlyTheme(), home: const LoginScreen()),
    );

FButton _loginButton(WidgetTester tester) => tester
    .widgetList<FButton>(find.byType(FButton))
    .firstWhere((b) => b.label.startsWith('Log in'));

void main() {
  testWidgets('email alone enables login and labels it as the dev bypass',
      (tester) async {
    await tester.pumpWidget(_harness());

    // Nothing typed: disabled.
    expect(_loginButton(tester).onPressed, isNull);

    await tester.enterText(
        find.byType(TextField).first, 'jordan.reyes@favorly.test');
    await tester.pump();

    final button = _loginButton(tester);
    expect(button.onPressed, isNotNull,
        reason: 'an email with no password should be enough in debug');
    expect(button.label, 'Log in (dev, no password)');
  });

  testWidgets('typing a password switches back to the real login',
      (tester) async {
    await tester.pumpWidget(_harness());

    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'jordan.reyes@favorly.test');
    await tester.enterText(fields.last, 'favorly-dev-2024');
    await tester.pump();

    final button = _loginButton(tester);
    expect(button.onPressed, isNotNull);
    expect(button.label, 'Log in',
        reason: 'a password means the normal auth path, not the bypass');
  });

  testWidgets('password alone is not enough', (tester) async {
    await tester.pumpWidget(_harness());

    await tester.enterText(find.byType(TextField).last, 'favorly-dev-2024');
    await tester.pump();

    expect(_loginButton(tester).onPressed, isNull);
  });
}
