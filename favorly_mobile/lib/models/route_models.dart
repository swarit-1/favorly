/// Favorly Route models: the frozen `POST /route/plan` wire shape.
///
/// Every fromJson is default-safe: a missing or oddly typed field decodes to
/// a sensible zero value instead of throwing, so a partial server response
/// still draws a screen.
library;

double _d(Object? v) => v is num ? v.toDouble() : 0.0;
int _i(Object? v) => v is num ? v.toInt() : 0;
String _s(Object? v) => v == null ? '' : '$v';

List<Map<String, dynamic>> _maps(Object? v) => v is List
    ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
    : const [];

/// One x,y position in store metres. Used for both layout nodes and the
/// walked path polyline.
class RoutePoint {
  const RoutePoint({required this.x, required this.y});

  final double x;
  final double y;

  factory RoutePoint.fromJson(Map<String, dynamic> json) =>
      RoutePoint(x: _d(json['x']), y: _d(json['y']));
}

/// A named place on the floor plan: `entrance`, `checkout`, or a section.
class RouteNode {
  const RouteNode({required this.key, required this.x, required this.y});

  final String key;
  final double x;
  final double y;

  factory RouteNode.fromJson(Map<String, dynamic> json) =>
      RouteNode(key: _s(json['key']), x: _d(json['x']), y: _d(json['y']));
}

/// The store footprint in metres plus its labeled nodes.
class RouteLayout {
  const RouteLayout({
    required this.widthM,
    required this.heightM,
    required this.nodes,
  });

  final double widthM;
  final double heightM;
  final List<RouteNode> nodes;

  factory RouteLayout.fromJson(Map<String, dynamic> json) => RouteLayout(
        widthM: _d(json['width_m']),
        heightM: _d(json['height_m']),
        nodes: [for (final n in _maps(json['nodes'])) RouteNode.fromJson(n)],
      );
}

/// One item picked up at a stop, with who it is for.
class RouteStopItem {
  const RouteStopItem({
    required this.name,
    required this.qty,
    required this.requesterFirst,
  });

  final String name;
  final int qty;
  final String requesterFirst;

  factory RouteStopItem.fromJson(Map<String, dynamic> json) => RouteStopItem(
        name: _s(json['name']),
        qty: _i(json['qty']),
        requesterFirst: _s(json['requester_first']),
      );
}

/// One stop on the walk, in visit order.
class RouteStop {
  const RouteStop({
    required this.order,
    required this.section,
    required this.x,
    required this.y,
    required this.items,
  });

  final int order;
  final String section;
  final double x;
  final double y;
  final List<RouteStopItem> items;

  factory RouteStop.fromJson(Map<String, dynamic> json) => RouteStop(
        order: _i(json['order']),
        section: _s(json['section']),
        x: _d(json['x']),
        y: _d(json['y']),
        items: [
          for (final i in _maps(json['items'])) RouteStopItem.fromJson(i)
        ],
      );
}

/// The item inside a suggestion, shaped so it can go straight back to
/// `/route/plan` as an `extra_items` entry when accepted.
class RouteSuggestionItem {
  const RouteSuggestionItem({
    required this.name,
    required this.qty,
    required this.section,
    this.requesterId,
  });

  final String name;
  final int qty;
  final String section;
  final String? requesterId;

  factory RouteSuggestionItem.fromJson(Map<String, dynamic> json) =>
      RouteSuggestionItem(
        name: _s(json['name']),
        qty: _i(json['qty']),
        section: _s(json['section']),
        requesterId: json['requester_id'] == null
            ? null
            : _s(json['requester_id']),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'qty': qty,
        'section': section,
        if (requesterId != null && requesterId!.isNotEmpty)
          'requester_id': requesterId,
      };
}

/// One explained, one-tap suggestion. `kind` is neighbor, future_you, or
/// forgotten; unknown kinds still render, the reason carries the meaning.
class RouteSuggestion {
  const RouteSuggestion({
    required this.id,
    required this.kind,
    required this.title,
    required this.reason,
    required this.item,
    required this.addedDistanceM,
    required this.requesterFirst,
  });

  final String id;
  final String kind;
  final String title;
  final String reason;
  final RouteSuggestionItem item;
  final double addedDistanceM;
  final String requesterFirst;

  factory RouteSuggestion.fromJson(Map<String, dynamic> json) =>
      RouteSuggestion(
        id: _s(json['id']),
        kind: _s(json['kind']),
        title: _s(json['title']),
        reason: _s(json['reason']),
        item: RouteSuggestionItem.fromJson(
          json['item'] is Map
              ? Map<String, dynamic>.from(json['item'] as Map)
              : const {},
        ),
        addedDistanceM: _d(json['added_distance_m']),
        requesterFirst: _s(json['requester_first']),
      );
}

/// One requester's running total against the cap they set.
class RouteCap {
  const RouteCap({
    required this.requesterFirst,
    required this.requesterId,
    required this.cap,
    required this.runningTotal,
    required this.over,
  });

  final String requesterFirst;
  final String requesterId;
  final double cap;
  final double runningTotal;
  final bool over;

  factory RouteCap.fromJson(Map<String, dynamic> json) => RouteCap(
        requesterFirst: _s(json['requester_first']),
        requesterId: _s(json['requester_id']),
        cap: _d(json['cap']),
        runningTotal: _d(json['running_total']),
        over: json['over'] == true,
      );
}

/// The whole `/route/plan` response.
class RoutePlan {
  const RoutePlan({
    required this.tripId,
    required this.store,
    required this.layout,
    required this.stops,
    required this.path,
    required this.distanceM,
    required this.baselineDistanceM,
    required this.suggestions,
    required this.caps,
  });

  final String tripId;
  final String store;
  final RouteLayout layout;
  final List<RouteStop> stops;
  final List<RoutePoint> path;
  final double distanceM;
  final double baselineDistanceM;
  final List<RouteSuggestion> suggestions;
  final List<RouteCap> caps;

  factory RoutePlan.fromJson(Map<String, dynamic> json) => RoutePlan(
        tripId: _s(json['trip_id']),
        store: _s(json['store']),
        layout: RouteLayout.fromJson(
          json['layout'] is Map
              ? Map<String, dynamic>.from(json['layout'] as Map)
              : const {},
        ),
        stops: [for (final s in _maps(json['stops'])) RouteStop.fromJson(s)]
          ..sort((a, b) => a.order.compareTo(b.order)),
        path: [for (final p in _maps(json['path'])) RoutePoint.fromJson(p)],
        distanceM: _d(json['distance_m']),
        baselineDistanceM: _d(json['baseline_distance_m']),
        suggestions: [
          for (final s in _maps(json['suggestions']))
            RouteSuggestion.fromJson(s)
        ],
        caps: [for (final c in _maps(json['caps'])) RouteCap.fromJson(c)],
      );
}

/// "produce" -> "Produce", "personal_care" -> "Personal care". Matches the
/// labels `StoreSection` uses so Route reads like the shopping list.
String routeSectionLabel(String wire) => switch (wire) {
      'produce' => 'Produce',
      'bakery' => 'Bakery',
      'meat' => 'Meat',
      'dairy' => 'Dairy',
      'frozen' => 'Frozen',
      'pantry' => 'Pantry',
      'beverages' => 'Drinks',
      'household' => 'Household',
      'personal_care' => 'Personal care',
      _ => wire.isEmpty
          ? 'Other'
          : wire[0].toUpperCase() + wire.substring(1).replaceAll('_', ' '),
    };
