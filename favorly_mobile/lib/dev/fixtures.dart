/// Appendix C of the Lane B PRD, verbatim, plus just enough scripted
/// progression that the whole hero journey can be rehearsed with no server:
/// intake -> three helpers -> invite -> (a beat later) accepted.
///
/// Everything here is raw wire-shaped JSON. TrellisClient feeds it through
/// the same fromJson paths as a live response, so the parsing is exercised
/// even in fixture mode.
///
/// Run with `--dart-define=FIXTURES=true` until Trellis is live.
library;

const bool kUseFixtures = bool.fromEnvironment('FIXTURES');

/// How long after an invite the fixture helper says yes: two polls at the
/// app's 4 s cadence, which is about how a demo should breathe.
const Duration kFixtureAcceptAfter = Duration(seconds: 8);

Map<String, dynamic> _deepCopy(Map<String, dynamic> m) =>
    Map<String, dynamic>.from({
      for (final e in m.entries)
        e.key: e.value is Map<String, dynamic>
            ? _deepCopy(e.value as Map<String, dynamic>)
            : e.value is List
                ? [
                    for (final v in e.value as List)
                      v is Map<String, dynamic> ? _deepCopy(v) : v,
                  ]
                : e.value,
    });

// ---------------------------------------------------------------------------
// Appendix C, verbatim.
// ---------------------------------------------------------------------------

const Map<String, dynamic> fixtureIntake = {
  'intent': 'ask_favor',
  'scope': 'ok',
  'scope_reply': null,
  'right_sized': null,
  'parsed_by': 'model',
  'need': {
    'id': 'need-1',
    'category': 'borrow',
    'title': 'Borrow a ladder',
    'body': 'I need to borrow a ladder for an hour today',
    'requires': ['ladder'],
    'when_text': 'today',
    'duration_minutes': 60,
    'items': [],
  },
};

const Map<String, dynamic> fixtureIntakeTooBig = {
  'intent': 'ask_favor',
  'scope': 'too_big',
  'need': null,
  'parsed_by': 'model',
  'scope_reply': 'That is more than one favor. Want to start with a piece of it?',
  'right_sized': 'help me frame and raise one wall, about two hours',
};

const Map<String, dynamic> fixtureHelpers = {
  'need_id': 'need-1',
  'decided_by': 'model',
  'helpers': [
    {
      'person': {
        'id': 'p-marcus',
        'display_name': 'Marcus Hill',
        'first_name': 'Marcus',
      },
      'rank': 1,
      'tie': 'friend_of_friend',
      'tie_label': 'Friend of Nora',
      'hops': 2,
      'path': [
        {'id': 'me', 'name': 'You'},
        {'id': 'p-nora', 'name': 'Nora'},
        {'id': 'p-marcus', 'name': 'Marcus'},
      ],
      'headline': 'Has a 6 ft ladder',
      'where': '3 floors up',
      'reason':
          'Has a 6 ft ladder and is usually free Sunday afternoons. You both know Nora.',
      'spark': 'You both follow F1.',
      'signals': {},
      'why': {
        'mutual_names': ['Nora Chen'],
        'shared': ['formula 1'],
      },
      'invite_status': null,
    },
    {
      'person': {
        'id': 'p-elena',
        'display_name': 'Elena Vasquez',
        'first_name': 'Elena',
      },
      'rank': 2,
      'tie': 'close',
      'tie_label': 'You know each other',
      'hops': 1,
      'path': [
        {'id': 'me', 'name': 'You'},
        {'id': 'p-elena', 'name': 'Elena'},
      ],
      'headline': 'Has a step ladder',
      'where': 'same floor',
      'reason':
          'Has a step ladder and lives on your floor. Elena helped you out last week.',
      'spark': null,
      'signals': {},
      'why': {},
      'invite_status': null,
    },
    {
      'person': {
        'id': 'p-jordan',
        'display_name': 'Jordan Reyes',
        'first_name': 'Jordan',
      },
      'rank': 3,
      'tie': 'new',
      'tie_label': 'New to the building',
      'hops': 4,
      'path': [
        {'id': 'me', 'name': 'You'},
        {'id': 'p-jordan', 'name': 'Jordan'},
      ],
      'headline': 'Has a ladder',
      'where': '1 floor down',
      'reason':
          "Still has a ladder from the move. This would be Jordan's first favor in the building.",
      'spark': null,
      'signals': {},
      'why': {},
      'invite_status': null,
    },
  ],
};

/// The unit only exists after both sides said yes; pre-acceptance the card
/// shows the relative `where` above.
const Map<String, String> _fixtureUnits = {
  'p-marcus': 'Unit 6C, 3 floors up',
  'p-elena': 'Unit 3F, same floor',
  'p-jordan': 'Unit 2A, 1 floor down',
};

// ---------------------------------------------------------------------------
// Scripted world state.
// ---------------------------------------------------------------------------

/// One ask at a time is all the demo needs. Static on purpose: every screen
/// sees the same world, exactly like they would share one server.
abstract final class FixtureWorld {
  static bool _needOpen = false;
  static String? _invitedHelperId;
  static DateTime? _invitedAt;
  static final Set<String> _declined = {};
  static bool _broadcast = false;
  static bool _fulfilled = false;

  static void reset() {
    _needOpen = false;
    _invitedHelperId = null;
    _invitedAt = null;
    _declined.clear();
    _broadcast = false;
    _fulfilled = false;
  }

  static bool get _accepted =>
      _invitedAt != null &&
      DateTime.now().difference(_invitedAt!) >= kFixtureAcceptAfter;

  /// POST /needs/intake. `confirm_right_sized: true` skips the scope check.
  /// The scripted scope check flags asks that read like a whole project, so
  /// the too_big path can be rehearsed by typing e.g. "build a deck".
  static Map<String, dynamic> intake(String text,
      {bool confirmRightSized = false}) {
    final t = text.toLowerCase();
    final looksTooBig = !confirmRightSized &&
        (t.contains('build') || t.contains('deck') || t.contains('renovate'));
    if (looksTooBig) return _deepCopy(fixtureIntakeTooBig);

    _needOpen = true;
    _fulfilled = false;
    final out = _deepCopy(fixtureIntake);
    if (text.trim().isNotEmpty) {
      (out['need'] as Map<String, dynamic>)['body'] = text.trim();
    }
    return out;
  }

  /// GET /needs/{id}/helpers, with invite_status reflecting what happened.
  static Map<String, dynamic> helpers() {
    final out = _deepCopy(fixtureHelpers);
    final list = (out['helpers'] as List).cast<Map<String, dynamic>>();
    for (final h in list) {
      final id = (h['person'] as Map)['id'];
      if (_declined.contains(id)) {
        h['invite_status'] = 'declined';
      } else if (id == _invitedHelperId) {
        h['invite_status'] = _accepted ? 'accepted' : 'pending';
        if (_accepted) {
          // Both sides said yes: the unit replaces the relative location.
          h['where'] = _fixtureUnits[id] ?? h['where'];
        }
      }
    }
    return out;
  }

  static Map<String, dynamic> invite(String helperId) {
    _invitedHelperId = helperId;
    _invitedAt = DateTime.now();
    return {'status': 'pending'};
  }

  static Map<String, dynamic> respondInvite(String helperId,
      {required bool accept}) {
    if (accept) return {'status': 'accepted', 'next': null};
    _declined.add(helperId);
    if (_invitedHelperId == helperId) {
      _invitedHelperId = null;
      _invitedAt = null;
    }
    return {'status': 'declined', 'next': null};
  }

  static Map<String, dynamic> broadcast() {
    _broadcast = true;
    return {'status': 'broadcast'};
  }

  static Map<String, dynamic> cancel() {
    reset();
    return {'status': 'cancelled'};
  }

  /// GET /people/{id}/asks: open and claimed needs I posted, with helpers and
  /// the accepted helper.
  static Map<String, dynamic> myAsks() {
    if (!_needOpen) return {'asks': []};
    final helperList =
        (helpers()['helpers'] as List).cast<Map<String, dynamic>>();
    Map<String, dynamic>? accepted;
    for (final h in helperList) {
      if (h['invite_status'] == 'accepted') accepted = h;
    }
    return {
      'asks': [
        {
          'need': _deepCopy(fixtureIntake['need'] as Map<String, dynamic>),
          'status': _fulfilled
              ? 'fulfilled'
              : accepted != null
                  ? 'claimed'
                  : 'open',
          'broadcast': _broadcast,
          'helpers': helperList,
          'accepted': accepted,
        },
      ],
    };
  }

  static Map<String, dynamic> graphStats() => {
        'people': 16,
        'ties': 23,
        // The demo beat: fulfilling the friend-of-a-friend favor closes a
        // triangle and the building tightens from 2.6 to 2.5 degrees.
        'avg_separation': _fulfilled ? 2.51 : 2.61,
        'triangles': _fulfilled ? 8 : 7,
      };

  // PRD-DEVIATION: Appendix C carries no /graph fixture, but 4.7 mounts the
  // web inside Circle and the demo has to work offline, so a small graph in
  // the same cast as the helpers fixture lives here. `meId` is the signed-in
  // person so the view's "You" node matches whoever is logged in.
  static Map<String, dynamic> graph(String meId) {
    final acceptedDone = _accepted && _invitedHelperId == 'p-marcus';
    return {
      'nodes': [
        {'id': meId, 'name': 'You', 'degree': 3, 'cluster': 0},
        {'id': 'p-nora', 'name': 'Nora Chen', 'degree': 3, 'cluster': 0},
        {'id': 'p-marcus', 'name': 'Marcus Hill', 'degree': 2, 'cluster': 1},
        {'id': 'p-elena', 'name': 'Elena Vasquez', 'degree': 2, 'cluster': 0},
        {'id': 'p-jordan', 'name': 'Jordan Reyes', 'degree': 1, 'cluster': 2},
        {'id': 'p-priya', 'name': 'Priya Natarajan', 'degree': 2, 'cluster': 1},
      ],
      'edges': [
        {'src': meId, 'dst': 'p-nora', 'kind': 'favor', 'strength': 0.9},
        {'src': meId, 'dst': 'p-elena', 'kind': 'favor', 'strength': 0.7},
        {'src': 'p-nora', 'dst': 'p-marcus', 'kind': 'knows', 'strength': 0.6},
        {'src': 'p-nora', 'dst': 'p-elena', 'kind': 'neighbor', 'strength': 0.4},
        {'src': 'p-marcus', 'dst': 'p-priya', 'kind': 'favor', 'strength': 0.5},
        {'src': 'p-jordan', 'dst': 'p-elena', 'kind': 'neighbor', 'strength': 0.2},
        // The fulfilled favor is a new solid edge: the triangle closes.
        if (_fulfilled && acceptedDone)
          {'src': meId, 'dst': 'p-marcus', 'kind': 'favor', 'strength': 0.8},
      ],
    };
  }

  /// The helper's phone marked it done (or the demo driver did). Lets the
  /// dashed path snap solid and the separation line tighten.
  static Map<String, dynamic> fulfill() {
    _fulfilled = true;
    _needOpen = true;
    return {
      'status': 'fulfilled',
      'first_favor_together': true,
      'separation': {'before': 2.61, 'after': 2.51},
    };
  }
}

// ---------------------------------------------------------------------------
// Favorly Route (S2): POST /route/plan, in the frozen contract shape.
// ---------------------------------------------------------------------------

/// The base plan for the seeded trip: three stops, the 212-instead-of-480
/// line, three explained suggestions, and one requester already over cap so
/// the warning can be rehearsed without a server.
const Map<String, dynamic> fixtureRoutePlanBase = {
  'trip_id': 'trip-1',
  'store': "Trader Joe's",
  'layout': {
    'width_m': 30,
    'height_m': 20,
    'nodes': [
      {'key': 'entrance', 'x': 1.0, 'y': 18.0},
      {'key': 'produce', 'x': 4.0, 'y': 4.0},
      {'key': 'bakery', 'x': 10.0, 'y': 3.0},
      {'key': 'dairy', 'x': 26.0, 'y': 5.0},
      {'key': 'pantry', 'x': 16.0, 'y': 10.0},
      {'key': 'frozen', 'x': 22.0, 'y': 14.0},
      {'key': 'beverages', 'x': 26.0, 'y': 11.0},
      {'key': 'checkout', 'x': 8.0, 'y': 18.0},
    ],
  },
  'stops': [
    {
      'order': 1,
      'section': 'produce',
      'x': 4.0,
      'y': 4.0,
      'items': [
        {'name': 'bananas', 'qty': 2, 'requester_first': 'Grace'},
        {'name': 'spinach', 'qty': 1, 'requester_first': 'Ana'},
      ],
    },
    {
      'order': 2,
      'section': 'dairy',
      'x': 26.0,
      'y': 5.0,
      'items': [
        {'name': 'yogurt', 'qty': 1, 'requester_first': 'Ana'},
      ],
    },
    {
      'order': 3,
      'section': 'pantry',
      'x': 16.0,
      'y': 10.0,
      'items': [
        {'name': 'pasta', 'qty': 2, 'requester_first': 'Dev'},
      ],
    },
  ],
  'path': [
    {'x': 1.0, 'y': 18.0},
    {'x': 4.0, 'y': 4.0},
    {'x': 26.0, 'y': 5.0},
    {'x': 16.0, 'y': 10.0},
    {'x': 8.0, 'y': 18.0},
  ],
  'distance_m': 212.0,
  'baseline_distance_m': 480.0,
  'suggestions': [
    {
      'id': 'sug-milk',
      'kind': 'neighbor',
      'title': 'Milk for Grace',
      'reason': 'Grace needs milk. Dairy is already on your route. Adds 0 m.',
      'item': {'name': 'milk', 'qty': 1, 'section': 'dairy'},
      'added_distance_m': 0.0,
      'requester_first': 'Grace',
    },
    {
      'id': 'sug-eggs',
      'kind': 'future_you',
      'title': 'Eggs for you',
      'reason':
          'Your pantry scan on Thursday showed one egg left. Dairy is already on your route. Adds 0 m.',
      'item': {'name': 'eggs', 'qty': 1, 'section': 'dairy'},
      'added_distance_m': 0.0,
      'requester_first': '',
    },
    {
      'id': 'sug-seltzer',
      'kind': 'forgotten',
      'title': 'Seltzer for you',
      'reason':
          'On your last three lists but missing from this one. Drinks sit just past dairy. Adds 12 m.',
      'item': {'name': 'seltzer', 'qty': 1, 'section': 'beverages'},
      'added_distance_m': 12.0,
      'requester_first': '',
    },
  ],
  'caps': [
    {
      'requester_first': 'Grace',
      'requester_id': 'p-grace',
      'cap': 40.00,
      'running_total': 12.50,
      'over': false,
    },
    {
      'requester_first': 'Ana',
      'requester_id': 'p-ana',
      'cap': 30.00,
      'running_total': 9.25,
      'over': false,
    },
    {
      'requester_first': 'Dev',
      'requester_id': 'p-dev',
      'cap': 25.00,
      'running_total': 26.75,
      'over': true,
    },
  ],
};

/// What accepting a suggestion costs a requester in the fixture world, since
/// no server priced the item. Flat and small on purpose.
const double _kFixtureRouteItemPrice = 4.50;

/// `POST /route/plan` on fixtures: the base plan with every `extra_items`
/// entry folded in, exactly the re-plan the server would do. An extra item
/// lands on its section's stop when the section is already on the walk,
/// otherwise it becomes a new stop before checkout; the matching suggestion
/// disappears, its added distance is walked, and the named requester's
/// running total moves.
Map<String, dynamic> fixtureRoutePlan(
  String tripId, [
  List<Map<String, dynamic>> extraItems = const [],
]) {
  final out = _deepCopy(fixtureRoutePlanBase);
  out['trip_id'] = tripId;
  final stops = (out['stops'] as List).cast<Map<String, dynamic>>();
  final suggestions = (out['suggestions'] as List).cast<Map<String, dynamic>>();
  final path = (out['path'] as List).cast<Map<String, dynamic>>();
  final caps = (out['caps'] as List).cast<Map<String, dynamic>>();
  final nodes = ((out['layout'] as Map)['nodes'] as List).cast<Map>();

  for (final extra in extraItems) {
    final name = '${extra['name'] ?? ''}';
    final section = '${extra['section'] ?? 'other'}';

    Map<String, dynamic>? matched;
    final i = suggestions.indexWhere((s) => (s['item'] as Map)['name'] == name);
    if (i >= 0) matched = suggestions.removeAt(i);

    final item = {
      'name': name,
      'qty': extra['qty'] ?? 1,
      'requester_first': '${matched?['requester_first'] ?? ''}'.isEmpty
          ? 'You'
          : matched!['requester_first'],
    };

    final stop = stops.where((s) => s['section'] == section).toList();
    if (stop.isNotEmpty) {
      (stop.first['items'] as List).add(item);
    } else {
      final node = nodes.where((n) => n['key'] == section).toList();
      final x = node.isEmpty ? 15.0 : (node.first['x'] as num).toDouble();
      final y = node.isEmpty ? 10.0 : (node.first['y'] as num).toDouble();
      stops.add({
        'order': stops.length + 1,
        'section': section,
        'x': x,
        'y': y,
        'items': [item],
      });
      path.insert(path.length - 1, {'x': x, 'y': y});
    }

    out['distance_m'] = (out['distance_m'] as num).toDouble() +
        ((matched?['added_distance_m'] as num?)?.toDouble() ?? 0.0);

    final who = '${matched?['requester_first'] ?? ''}';
    for (final cap in caps) {
      if (who.isNotEmpty && cap['requester_first'] == who) {
        final total =
            (cap['running_total'] as num).toDouble() + _kFixtureRouteItemPrice;
        cap['running_total'] = total;
        cap['over'] = total > (cap['cap'] as num).toDouble();
      }
    }
  }
  return out;
}
