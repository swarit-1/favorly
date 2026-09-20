import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:favorly_mobile/api_client.dart';
import 'package:favorly_mobile/main.dart';

/// A trip matching the shape backend/app.py's _row_to_trip returns.
Map<String, dynamic> _tripJson({String status = 'open'}) => {
      'id': 'trip-1',
      'shopper_id': 'user-1',
      'circle_id': 'circle-1',
      'store': "Trader Joe's",
      'depart_at': '2026-01-01T15:00:00',
      'caps': {
        'max_requesters': 5,
        'max_dollars_per_person': '40.00',
        'max_items_per_person': 8,
      },
      'status': status,
      'created_at': '2026-01-01T00:00:00',
    };

/// Fakes the backend so widget tests never touch the network -- see
/// backend/app.py for the real shapes this mirrors.
ApiClient _fakeApiClient() {
  final client = MockClient((request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/trips')) {
      return http.Response(jsonEncode({'trips': [_tripJson()]}), 200);
    }
    if (request.method == 'POST' && request.url.path == '/trips') {
      return http.Response(jsonEncode(_tripJson()), 201);
    }
    return http.Response('{}', 404);
  });
  return ApiClient(client: client);
}

void main() {
  testWidgets('trips tab renders and nav switches', (tester) async {
    await tester.pumpWidget(FavorlyApp(apiClient: _fakeApiClient()));
    await tester.pumpAndSettle();

    expect(find.text('Favorly'), findsOneWidget);
    expect(find.text("Trader Joe's"), findsOneWidget);
    expect(find.text('Add my list'), findsOneWidget);

    await tester.tap(find.text('Circle'));
    await tester.pumpAndSettle();

    expect(find.text('Not designed yet'), findsOneWidget);
  });

  testWidgets('post a trip pushes through to the voice confirmation',
      (tester) async {
    await tester.pumpWidget(FavorlyApp(apiClient: _fakeApiClient()));
    await tester.pumpAndSettle();

    // ListView lazily realizes far-off children via SliverList (even the
    // plain, non-builder constructor), so scrollUntilVisible -- which scrolls
    // incrementally and re-checks -- is required; ensureVisible can't scroll
    // to a target that isn't built yet.
    await tester.scrollUntilVisible(find.text('Post a trip'), 200);
    await tester.tap(find.text('Post a trip'));
    await tester.pumpAndSettle();
    expect(find.text('Store'), findsOneWidget);

    // PostTripScreen's store TextField adds its own internal Scrollable, so
    // the default scrollable auto-detection (find.byType(Scrollable).single)
    // is ambiguous there. Anchor on 'Store' rather than 'Say the trip' itself
    // -- the target of an ancestor lookup has to already be built, and 'Say
    // the trip' is the very thing not yet realized.
    await tester.scrollUntilVisible(
      find.text('Say the trip'),
      200,
      scrollable: find.ancestor(
        of: find.text('Store'),
        matching: find.byType(Scrollable),
      ),
    );
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
