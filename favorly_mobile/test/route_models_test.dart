// Favorly Route models against the frozen /route/plan contract: the exact
// wire shape parses field for field, and a hollow response still decodes.

import 'package:flutter_test/flutter_test.dart';

import 'package:favorly_mobile/models/route_models.dart';

/// The frozen contract example, verbatim.
const Map<String, dynamic> frozenPlan = {
  'trip_id': 'trip-1',
  'store': "Trader Joe's",
  'layout': {
    'width_m': 30,
    'height_m': 20,
    'nodes': [
      {'key': 'entrance', 'x': 1.0, 'y': 18.0},
      {'key': 'produce', 'x': 4.0, 'y': 4.0},
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
      ],
    },
  ],
  'path': [
    {'x': 1.0, 'y': 18.0},
    {'x': 4.0, 'y': 4.0},
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
  ],
  'caps': [
    {
      'requester_first': 'Grace',
      'requester_id': 'p-grace',
      'cap': 40.00,
      'running_total': 12.50,
      'over': false,
    },
  ],
};

void main() {
  test('the frozen contract decodes field for field', () {
    final plan = RoutePlan.fromJson(frozenPlan);

    expect(plan.tripId, 'trip-1');
    expect(plan.store, "Trader Joe's");

    expect(plan.layout.widthM, 30);
    expect(plan.layout.heightM, 20);
    expect(plan.layout.nodes, hasLength(3));
    expect(plan.layout.nodes.first.key, 'entrance');
    expect(plan.layout.nodes.first.x, 1.0);
    expect(plan.layout.nodes.first.y, 18.0);

    expect(plan.stops, hasLength(1));
    final stop = plan.stops.single;
    expect(stop.order, 1);
    expect(stop.section, 'produce');
    expect(stop.x, 4.0);
    expect(stop.y, 4.0);
    expect(stop.items.single.name, 'bananas');
    expect(stop.items.single.qty, 2);
    expect(stop.items.single.requesterFirst, 'Grace');

    expect(plan.path, hasLength(2));
    expect(plan.path.last.x, 4.0);
    expect(plan.distanceM, 212.0);
    expect(plan.baselineDistanceM, 480.0);

    final s = plan.suggestions.single;
    expect(s.id, 'sug-milk');
    expect(s.kind, 'neighbor');
    expect(s.title, 'Milk for Grace');
    expect(s.reason,
        'Grace needs milk. Dairy is already on your route. Adds 0 m.');
    expect(s.addedDistanceM, 0.0);
    expect(s.requesterFirst, 'Grace');
    // The item goes back to /route/plan as an extra_items entry unchanged.
    expect(s.item.toJson(), {'name': 'milk', 'qty': 1, 'section': 'dairy'});

    final cap = plan.caps.single;
    expect(cap.requesterFirst, 'Grace');
    expect(cap.requesterId, 'p-grace');
    expect(cap.cap, 40.00);
    expect(cap.runningTotal, 12.50);
    expect(cap.over, isFalse);
  });

  test('stops decode into visit order even when the wire is shuffled', () {
    final plan = RoutePlan.fromJson({
      'stops': [
        {'order': 3, 'section': 'pantry'},
        {'order': 1, 'section': 'produce'},
        {'order': 2, 'section': 'dairy'},
      ],
    });
    expect(plan.stops.map((s) => s.section).toList(),
        ['produce', 'dairy', 'pantry']);
  });

  test('an empty response decodes to safe defaults, never a throw', () {
    final plan = RoutePlan.fromJson(const {});
    expect(plan.tripId, '');
    expect(plan.store, '');
    expect(plan.layout.nodes, isEmpty);
    expect(plan.stops, isEmpty);
    expect(plan.path, isEmpty);
    expect(plan.distanceM, 0);
    expect(plan.baselineDistanceM, 0);
    expect(plan.suggestions, isEmpty);
    expect(plan.caps, isEmpty);
  });

  test('section labels match the shopping list wording', () {
    expect(routeSectionLabel('produce'), 'Produce');
    expect(routeSectionLabel('beverages'), 'Drinks');
    expect(routeSectionLabel('personal_care'), 'Personal care');
    expect(routeSectionLabel('mystery_aisle'), 'Mystery aisle');
  });
}
