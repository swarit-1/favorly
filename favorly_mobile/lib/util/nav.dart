import 'package:flutter/material.dart';

Future<T?> push<T>(BuildContext context, Widget page, {String? name}) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(
      builder: (_) => page,
      settings: RouteSettings(name: name),
    ),
  );
}

/// Pops back to the trip detail if it is on the stack, otherwise to the feed.
void popToTrip(BuildContext context, String tripId) {
  Navigator.of(context).popUntil(
    (r) => r.isFirst || r.settings.name == 'trip/$tripId',
  );
}

void popToRoot(BuildContext context) {
  Navigator.of(context).popUntil((r) => r.isFirst);
}
