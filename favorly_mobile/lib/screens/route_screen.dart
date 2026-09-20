import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../models/route_models.dart';
import '../services/api_client.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/buttons.dart';
import '../widgets/error_panel.dart';
import '../widgets/page.dart';
import '../widgets/surfaces.dart';

/// How `/route/plan` is called. Injectable so tests and fixture rigs can
/// hand the screen a plan without a server.
typedef RoutePlanner = Future<RoutePlan> Function(
  String tripId, {
  List<Map<String, dynamic>>? extraItems,
});

/// Favorly Route: the store laid out for you, not for the store.
///
/// A floor plan with the shortest walk drawn through it, the ordered stops
/// under it, at most three explained suggestions, each one tap to accept or
/// skip, and everyone's spending cap in view. Accepting a suggestion re-plans
/// the walk with that item added.
class RouteScreen extends StatefulWidget {
  const RouteScreen({super.key, required this.tripId, this.planner});

  final String tripId;
  final RoutePlanner? planner;

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  RoutePlan? _plan;
  String? _error;
  bool _loading = true;

  /// Suggestion IDs the shopper waved off. Skipped means gone from view,
  /// never argued with.
  final Set<String> _skipped = {};

  /// Items accepted so far, in `/route/plan` `extra_items` shape. Re-plans
  /// always send the full list so the server rebuilds one consistent walk.
  final List<Map<String, dynamic>> _accepted = [];

  /// The suggestion currently being folded into the route, for the brief
  /// per-card busy state.
  String? _acceptingId;

  RoutePlanner get _planner => widget.planner ?? ApiClient.planRoute;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plan = await _planner(widget.tripId, extraItems: _accepted);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _accept(RouteSuggestion s) async {
    setState(() => _acceptingId = s.id);
    final entry = s.item.toJson();
    try {
      final plan = await _planner(
        widget.tripId,
        extraItems: [..._accepted, entry],
      );
      if (!mounted) return;
      setState(() {
        _accepted.add(entry);
        _plan = plan;
        _acceptingId = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _acceptingId = null;
        _error = '$e';
      });
    }
  }

  void _skip(RouteSuggestion s) => setState(() => _skipped.add(s.id));

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    return FavorlyPage(
      topBar: const FTopBar(title: 'Route'),
      children: [
        if (_loading && plan == null)
          const Padding(
            padding: EdgeInsets.only(top: 120),
            child: Center(child: CupertinoActivityIndicator(radius: 14)),
          )
        else if (plan == null) ...[
          ErrorPanel(_error),
          const SizedBox(height: 16),
          FButton(label: 'Try again', kind: FButtonKind.secondary, onPressed: _load),
        ] else
          ..._loaded(plan),
      ],
    );
  }

  List<Widget> _loaded(RoutePlan plan) {
    final visible = plan.suggestions
        .where((s) => !_skipped.contains(s.id))
        .take(3)
        .toList();
    return [
      PageTitle(
        plan.store,
        subtitle: 'A store is laid out for the store. '
            'Your route is laid out for you.',
        padding: const EdgeInsets.only(top: 4, bottom: 16),
      ),
      _FloorPlan(plan: plan),
      const SizedBox(height: 16),
      Text(
        '${plan.distanceM.round()} m instead of '
        '${plan.baselineDistanceM.round()} m',
        style: FType.heading,
      ),
      const SizedBox(height: 2),
      Text(
        'The written list walked in order is the long way around.',
        style: FType.bodySmall.copyWith(color: FColors.inkSecondary),
      ),
      const SizedBox(height: 24),
      const Eyebrow('Stops'),
      const SizedBox(height: 8),
      Panel(
        dividerIndent: 56,
        children: [
          for (final stop in plan.stops)
            PanelRow(
              leading: _OrderBadge(stop.order),
              title: routeSectionLabel(stop.section),
              subtitle: stop.items.map(_itemLine).join(' · '),
            ),
        ],
      ),
      if (visible.isNotEmpty) ...[
        const SizedBox(height: 24),
        const Eyebrow('Worth a stop', icon: CupertinoIcons.sparkles),
        const SizedBox(height: 8),
        for (final s in visible) ...[
          _SuggestionCard(
            suggestion: s,
            busy: _acceptingId == s.id,
            enabled: _acceptingId == null,
            onAdd: () => _accept(s),
            onSkip: () => _skip(s),
          ),
          const SizedBox(height: 10),
        ],
      ],
      if (plan.caps.isNotEmpty) ...[
        const SizedBox(height: 20),
        const Eyebrow('Caps'),
        const SizedBox(height: 8),
        Panel(
          children: [
            for (final cap in plan.caps)
              PanelRow(
                title: '${cap.requesterFirst} · '
                    '${money(cap.runningTotal)} of ${moneyShort(cap.cap)}',
                titleStyle: FType.bodySmallStrong,
                trailing: cap.over
                    ? const StatusPill('Over cap', kind: PillKind.attention)
                    : null,
                minHeight: 48,
              ),
          ],
        ),
        for (final cap in plan.caps.where((c) => c.over)) ...[
          const SizedBox(height: 10),
          Notice("Over ${cap.requesterFirst}'s cap", kind: NoticeKind.attention),
        ],
      ],
      if (_error != null) ErrorPanel(_error),
    ];
  }

  /// Person first: "Milk for Grace", never "1 gal 2%".
  String _itemLine(RouteStopItem item) {
    final name = item.name.isEmpty
        ? 'Item'
        : item.name[0].toUpperCase() + item.name.substring(1);
    final qty = item.qty > 1 ? '$name x${item.qty}' : name;
    return item.requesterFirst.isEmpty ? qty : '$qty for ${item.requesterFirst}';
  }
}

class _OrderBadge extends StatelessWidget {
  const _OrderBadge(this.order);

  final int order;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: FColors.blueTint,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$order',
        style: FType.captionStrong.copyWith(color: FColors.blue),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.suggestion,
    required this.busy,
    required this.enabled,
    required this.onAdd,
    required this.onSkip,
  });

  final RouteSuggestion suggestion;
  final bool busy;
  final bool enabled;
  final VoidCallback onAdd;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: FColors.canvas,
        borderRadius: BorderRadius.circular(FRadius.lg),
        border: Border.all(color: FColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(suggestion.title, style: FType.bodyStrong)),
              if (suggestion.addedDistanceM > 0) ...[
                const SizedBox(width: 8),
                StatusPill(
                  'Adds ${suggestion.addedDistanceM.round()} m',
                  kind: PillKind.info,
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            suggestion.reason,
            style: FType.bodySmall.copyWith(color: FColors.inkSecondary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FButton(
                  label: 'Add',
                  compact: true,
                  busy: busy,
                  onPressed: enabled ? onAdd : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FButton(
                  label: 'Skip',
                  kind: FButtonKind.secondary,
                  compact: true,
                  onPressed: enabled && !busy ? onSkip : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The floor plan: rounded store outline, section nodes as labeled dots, and
/// the walk entrance to checkout in the app's blue.
class _FloorPlan extends StatelessWidget {
  const _FloorPlan({required this.plan});

  final RoutePlan plan;

  @override
  Widget build(BuildContext context) {
    final layout = plan.layout;
    final ratio = layout.widthM > 0 && layout.heightM > 0
        ? layout.widthM / layout.heightM
        : 3 / 2;
    return Semantics(
      label:
          'Store map with your route through ${plural(plan.stops.length, 'stop')}',
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: FColors.surface,
          borderRadius: BorderRadius.circular(FRadius.lg),
          border: Border.all(color: FColors.hairline),
        ),
        child: AspectRatio(
          aspectRatio: ratio,
          child: CustomPaint(painter: _FloorPlanPainter(plan)),
        ),
      ),
    );
  }
}

class _FloorPlanPainter extends CustomPainter {
  _FloorPlanPainter(this.plan);

  final RoutePlan plan;

  static const _inset = 14.0;

  Offset _place(double x, double y, Size size) {
    final layout = plan.layout;
    final w = layout.widthM <= 0 ? 1.0 : layout.widthM;
    final h = layout.heightM <= 0 ? 1.0 : layout.heightM;
    final scale = math.min(
      (size.width - _inset * 2) / w,
      (size.height - _inset * 2) / h,
    );
    final dx = (size.width - w * scale) / 2;
    final dy = (size.height - h * scale) / 2;
    return Offset(dx + x * scale, dy + y * scale);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final layout = plan.layout;

    // The store footprint, a rounded rect inside the card.
    final origin = _place(0, 0, size);
    final corner = _place(layout.widthM, layout.heightM, size);
    final store = RRect.fromRectAndRadius(
      Rect.fromPoints(origin, corner),
      const Radius.circular(10),
    );
    canvas.drawRRect(store, Paint()..color = FColors.canvas);
    canvas.drawRRect(
      store,
      Paint()
        ..color = FColors.hairlineStrong
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // The walk, entrance to checkout, in the app's blue.
    if (plan.path.length > 1) {
      final walk = Path()
        ..moveTo(_place(plan.path.first.x, plan.path.first.y, size).dx,
            _place(plan.path.first.x, plan.path.first.y, size).dy);
      for (final p in plan.path.skip(1)) {
        final o = _place(p.x, p.y, size);
        walk.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
        walk,
        Paint()
          ..color = FColors.blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // Section nodes: small labeled dots. Entrance and checkout get the ink
    // treatment so the walk reads start to finish.
    final stopSections = {for (final s in plan.stops) s.section};
    for (final node in layout.nodes) {
      final o = _place(node.x, node.y, size);
      final isDoor = node.key == 'entrance' || node.key == 'checkout';
      final onWalk = stopSections.contains(node.key);
      if (!isDoor) {
        canvas.drawCircle(
          o,
          onWalk ? 4.5 : 3,
          Paint()..color = onWalk ? FColors.blue : FColors.hairlineStrong,
        );
        if (onWalk) {
          canvas.drawCircle(
            o,
            4.5,
            Paint()
              ..color = FColors.canvas
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
      } else {
        canvas.drawCircle(o, 5, Paint()..color = FColors.ink);
        canvas.drawCircle(
          o,
          5,
          Paint()
            ..color = FColors.canvas
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
      _label(
        canvas,
        size,
        o,
        isDoor ? _title(node.key) : routeSectionLabel(node.key),
        strong: isDoor || onWalk,
      );
    }
  }

  String _title(String key) =>
      key.isEmpty ? key : key[0].toUpperCase() + key.substring(1);

  void _label(Canvas canvas, Size size, Offset at, String text,
      {required bool strong}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: FType.family,
          fontSize: 10,
          fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
          color: strong ? FColors.ink : FColors.inkTertiary,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Below the dot, nudged back inside the card when it would clip.
    var dx = at.dx - painter.width / 2;
    dx = dx.clamp(2.0, math.max(2.0, size.width - painter.width - 2));
    var dy = at.dy + 7;
    if (dy + painter.height > size.height - 2) {
      dy = at.dy - painter.height - 7;
    }
    painter.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_FloorPlanPainter oldDelegate) =>
      oldDelegate.plan != plan;
}
