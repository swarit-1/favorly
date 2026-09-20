import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import 'package:favorly_mobile/main.dart';
import 'package:favorly_mobile/providers/auth_provider.dart';
import 'package:favorly_mobile/providers/location_provider.dart';
import 'package:favorly_mobile/screens/circle_screen.dart';

/// The app is auth-gated now; these flows are about everything behind the
/// gate, so the tests walk in already signed in as the demo store's "me".
class _SeededAuth extends AuthNotifier {
  _SeededAuth() {
    state = AuthState(userId: 'me-ana', name: 'Ana Delgado', circleId: 'c-demo');
  }
}

/// The map tab subscribes to Supabase realtime the moment the shell builds;
/// the socket cannot connect under flutter_test and its retry timers would
/// fail the strict teardown, so the subscription is a no-op here.
class _StubLocation extends LocationNotifier {
  _StubLocation(super.userId, super.circleId);

  @override
  Future<void> requestPermission() async {}

  @override
  void subscribe() {}
}

bool _supabaseReady = false;

/// The map tab's tile loader leaves one-shot retry timers behind; walk fake
/// time forward so they fire before the strict teardown looks for them.
Future<void> flushTimers(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(seconds: 30));
  }
}

/// A tall phone viewport so whole screens are built without scrolling.
Future<void> pumpApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  // The map tab touches Supabase.instance the moment the shell builds, so the
  // test process needs an initialized (never contacted) client.
  if (!_supabaseReady) {
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'sb_publishable_test_key_never_contacted',
    );
    _supabaseReady = true;
  }
  // GoTrue starts a periodic session-refresh timer on init; there is no
  // session here and a periodic timer fails the strict teardown.
  Supabase.instance.client.auth.stopAutoRefresh();
  tester.view.physicalSize = const Size(430, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => _SeededAuth()),
      locationProvider.overrideWith(
          (ref, args) => _StubLocation(args.$1, args.$2)),
    ],
    child: const FavorlyApp(),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('feed shows the active trip and the tabs switch', (tester) async {
    await pumpApp(tester);

    expect(find.text("Trader Joe's"), findsWidgets);
    expect(find.text('Post a trip'), findsOneWidget);

    await tester.tap(find.text('Circle'));
    await tester.pumpAndSettle();
    expect(find.text('Demo Building'), findsWidgets);
    // The invite panel sits below the unlock, referral, and ledger panels,
    // off the first viewport, so pull the circle tab's list up until it shows.
    for (var i = 0; i < 12; i++) {
      if (find.text('MAPLE7').evaluate().isNotEmpty) break;
      await tester.drag(find.byType(CircleScreen), const Offset(0, -600));
      await tester.pumpAndSettle();
    }
    expect(find.text('Invite a neighbor'), findsOneWidget);
    expect(find.text('MAPLE7'), findsOneWidget);

    await tester.tap(find.text('You'));
    await tester.pumpAndSettle();
    expect(find.text('Ana Delgado'), findsWidgets);
    await flushTimers(tester);
  });

  testWidgets('a neighbor types a list, reviews it, and attaches it', (tester) async {
    await pumpApp(tester);

    // v2: the grocery list flow lives inside the composer now.
    await tester.tap(find.text('Ask for anything'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Have a grocery list? Snap it'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField).first, '2 lemons\noat milk under \$5');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review list'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    expect(find.text('Lemons'), findsOneWidget);
    expect(find.text('Oat milk'), findsOneWidget);

    await tester.tap(find.text('Attach 2 items'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your list is with'), findsOneWidget);
    await flushTimers(tester);
  });

  // Posting now goes through the live API, which a widget test cannot reach,
  // so this covers the composer itself: it opens, validates, and holds the
  // typed store name.
  testWidgets('the trip composer opens and validates', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Post a trip'));
    await tester.pumpAndSettle();

    // Empty store name is refused before anything is sent.
    await tester.tap(find.text('Post trip'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Add the store'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Whole Foods');
    await tester.pumpAndSettle();
    expect(find.text('Whole Foods'), findsWidgets);
    await flushTimers(tester);
  });
}
