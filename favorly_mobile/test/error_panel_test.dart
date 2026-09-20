import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:favorly_mobile/theme/theme.dart';
import 'package:favorly_mobile/widgets/error_panel.dart';

const _long = "Exception: Can't reach the API at http://localhost:8000.\n"
    'Is the backend running, and is this the right host for this device?\n'
    '(SocketException: Connection refused (OS Error: Connection refused, '
    'errno = 61), address = localhost, port = 51234)';

Widget _wrap(Widget child, {double width = 400}) => MaterialApp(
      theme: buildFavorlyTheme(),
      home: Scaffold(
        body: Center(child: SizedBox(width: width, child: child)),
      ),
    );

void main() {
  testWidgets('renders the whole message, not one ellipsized line',
      (tester) async {
    await tester.pumpWidget(_wrap(const ErrorPanel(_long)));

    final text = tester.widget<SelectableText>(find.byType(SelectableText));
    final shown = text.data!;

    // Every line survives — the URL and the reason are the useful parts.
    expect(shown, contains('http://localhost:8000'));
    expect(shown, contains('is this the right host for this device?'));
    expect(shown, contains('errno = 61'));
    expect(text.maxLines, isNull, reason: 'must be allowed to wrap');
  });

  testWidgets('drops the Exception: prefix', (tester) async {
    await tester.pumpWidget(_wrap(const ErrorPanel(_long)));
    final shown = tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(shown, startsWith("Can't reach"));
  });

  testWidgets('wraps to several lines at phone width', (tester) async {
    await tester.pumpWidget(_wrap(const ErrorPanel(_long), width: 320));
    final box = tester.renderObject<RenderBox>(find.byType(SelectableText));
    expect(box.size.height, greaterThan(60),
        reason: 'a single clipped line would be ~20px tall');
  });

  testWidgets('renders nothing when there is no error', (tester) async {
    await tester.pumpWidget(_wrap(const ErrorPanel(null)));
    expect(find.byType(SelectableText), findsNothing);
  });
}
