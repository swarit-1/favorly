import 'package:flutter/cupertino.dart';

/// What kind of favor this is, per the v2 taxonomy.
///
/// The wire vocabulary is owned by the server; anything it sends that this
/// enum does not know (old rows, old caches, a category added later) decodes
/// as [errand], the original favor type, so nothing ever fails to render.
enum FavorCategory {
  errand('errand', 'Pick up', CupertinoIcons.cart),
  borrow('borrow', 'Borrow', CupertinoIcons.arrow_right_arrow_left),
  hands('hands', 'Extra hands', CupertinoIcons.hammer),
  skill('skill', 'Know-how', CupertinoIcons.wrench),
  company('company', 'Company', CupertinoIcons.person_2),
  ride('ride', 'Ride', CupertinoIcons.car),
  care('care', 'Look after', CupertinoIcons.heart),
  other('other', 'Favor', CupertinoIcons.sparkles);

  const FavorCategory(this.wire, this.label, this.icon);

  /// The string the API speaks.
  final String wire;

  /// The label the app shows.
  final String label;

  /// The 16 px glyph the app badges cards with.
  final IconData icon;

  /// Unknown or missing decodes as [errand] so pre-v2 rows and caches keep
  /// working.
  static FavorCategory fromWire(Object? value) {
    final s = '$value';
    for (final c in values) {
      if (c.wire == s) return c;
    }
    return FavorCategory.errand;
  }
}
