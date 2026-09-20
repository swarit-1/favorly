@Tags(['golden'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:favorly_mobile/main.dart';
import 'package:favorly_mobile/screens/shopping_screen.dart';
import 'package:favorly_mobile/screens/you_screen.dart';

/// Walks the full demo loop on an iPhone-sized surface and captures one
/// image per screen into test/goldens. Regenerate with
/// `flutter test --run-skipped -t golden --update-goldens`.
Future<void> loadFonts() async {
  final figtree = FontLoader('Figtree');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    figtree.addFont(rootBundle.load('assets/fonts/Figtree-$weight.ttf'));
  }
  await figtree.load();
  final caveat = FontLoader('Caveat')
    ..addFont(rootBundle.load('assets/fonts/Caveat-Medium.ttf'));
  await caveat.load();
  final icons = FontLoader('packages/cupertino_icons/CupertinoIcons')
    ..addFont(rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'));
  await icons.load();
}

void main() {
  setUpAll(loadFonts);

  testWidgets('demo loop screenshots', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    var shot = 0;
    Future<void> snap(String name) async {
      shot++;
      final file = 'goldens/${shot.toString().padLeft(2, '0')}-$name.png';
      await expectLater(find.byType(MaterialApp), matchesGoldenFile(file));
    }

    // Transitions without waiting for repeating animations to stop.
    Future<void> settleRoute() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> tapText(String text, {bool settle = true}) async {
      await tester.tap(find.text(text).first);
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await settleRoute();
      }
    }

    Future<void> scrollTo(Finder finder, Type screen) async {
      final scrollable = find
          .descendant(of: find.byType(screen), matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(finder, 200, scrollable: scrollable);
      await tester.pumpAndSettle();
    }

    Future<void> dismissToasts() async {
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
          .clearSnackBars();
      await tester.pumpAndSettle();
    }

    Future<void> goBack() async {
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
    }

    Future<void> viewAs(String name) async {
      await tapText('You');
      await tapText(name);
      await tapText('Trips');
    }

    await tester.pumpWidget(const ProviderScope(child: FavorlyApp()));
    await tester.pumpAndSettle();
    await snap('feed-shopper');

    await tester.tap(find.text('Review 2 lists'));
    await tester.pumpAndSettle();
    await snap('trip-detail-shopper');
    await goBack();

    await tapText('Post a trip');
    await snap('post-trip');
    await tapText('Say it instead', settle: false);
    await tester.pump(const Duration(milliseconds: 2600));
    await tester.pumpAndSettle();
    await snap('post-trip-voice');
    await tapText('Use this');
    await snap('post-trip-filled');
    await goBack();

    await tapText('You');
    await snap('you');
    await tapText('Chloe Marchetti');
    await tapText('Trips');
    await snap('feed-requester');

    await tapText('Add my list');
    await snap('add-list-type');
    await tapText('Photo');
    await snap('add-list-photo');
    await tapText('Take photo');
    await tapText('Use this photo', settle: false);
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    await snap('review-list');
    await tapText('Looks right');
    await tapText('Attach 5 items');
    await snap('attached');
    await tapText('Done');

    await viewAs('Ana Delgado');
    await tapText('Review 3 lists');
    await tapText('Start shopping');
    await snap('shopping');
    await tester.tap(find.bySemanticsLabel('Got Bananas'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Got Oat milk').first);
    await tester.pumpAndSettle();
    await scrollTo(find.bySemanticsLabel('Not here, Unsalted butter'), ShoppingScreen);
    await tester.tap(find.bySemanticsLabel('Not here, Unsalted butter'));
    await tester.pumpAndSettle();
    await snap('substitute-capture');
    await tapText('Scan shelf', settle: false);
    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pump();
    await snap('substitute-waiting');
    await tapText('Answer as Chloe', settle: false);
    await snap('substitute-choice');
    await tapText('Choose this', settle: false);
    await tester.pump(const Duration(milliseconds: 600));
    await snap('shopping-after-swap');
    await dismissToasts();

    await tapText('Scan receipt');
    await tapText('Skip them and scan');
    await snap('receipt-capture');
    await tapText('Scan receipt', settle: false);
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();
    await snap('receipt-review');
    await tapText('Chloe');
    await tapText('Confirm split');
    await snap('trip-settling-shopper');
    await dismissToasts();
    await goBack();

    await viewAs('Chloe Marchetti');
    await tester.tap(find.textContaining('Pay \$'));
    await tester.pumpAndSettle();
    await snap('settlement');
    await tapText('Mark as paid');
    await snap('settlement-paid');
    await dismissToasts();
    await goBack();

    await viewAs('Ana Delgado');
    await tapText('Finish up');
    await tapText('Confirm handoff');
    await snap('handoff');
    await tapText('Mark delivered');
    await tapText('Circle');
    await snap('circle');
    await dismissToasts();

    await tapText('You');
    await scrollTo(find.text('Leave circle'), YouScreen);
    await tapText('Leave circle');
    await snap('join');

    debugDefaultTargetPlatformOverride = null;
  });
}
