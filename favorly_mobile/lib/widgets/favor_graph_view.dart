import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/trellis_client.dart';
import '../theme/tokens.dart';

/// Colors for the communities the server's modularity pass found.
///
/// Three, not more, on purpose. A node-link map scatters marks, so any two
/// clusters can end up adjacent, which puts every pair of hues in play at
/// once, and no larger set clears colorblind separation under that condition.
/// Past three, the rest fold into [clusterOther] rather than inventing a
/// fourth hue that some readers can't tell from the third.
///
/// Identity is never carried by color alone here: every node is labelled with
/// its name, and the legend names each community.
abstract final class GraphPalette {
  static const clusters = <Color>[
    Color(0xFF2A78D6), // blue
    Color(0xFFEB6834), // orange
    Color(0xFF1BAF7A), // aqua
  ];

  /// Everyone past the third community, and anyone unassigned.
  static const other = FColors.inkTertiary;

  static Color forCluster(int cluster) =>
      cluster >= 0 && cluster < clusters.length ? clusters[cluster] : other;
}

/// The circle's favor network, laid out and drawn.
///
/// Layout is computed once per data change and is deterministic: the same
/// graph always produces the same picture, so the map doesn't reshuffle under
/// someone mid-sentence about it. The animation is only the reveal.
class FavorGraphView extends StatefulWidget {
  const FavorGraphView({
    super.key,
    required this.graph,
    required this.meId,
    this.selectedId,
    this.onSelect,
    this.height = 320,
  });

  final FavorGraph graph;
  final String meId;
  final String? selectedId;
  final ValueChanged<GraphNode?>? onSelect;
  final double height;

  @override
  State<FavorGraphView> createState() => _FavorGraphViewState();
}

class _FavorGraphViewState extends State<FavorGraphView>
    with SingleTickerProviderStateMixin {
  late AnimationController _reveal;

  /// Unit-square positions, one per node in `widget.graph.nodes` order.
  List<Offset> _positions = const [];

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _relayout();
    _reveal.forward();
  }

  @override
  void didUpdateWidget(FavorGraphView old) {
    super.didUpdateWidget(old);
    // Re-solve only when the shape of the graph changed. A selection change,
    // or a refresh that returned the same people, must not move anything.
    if (!_sameShape(old.graph, widget.graph)) {
      _relayout();
      _reveal.forward(from: 0);
    }
  }

  bool _sameShape(FavorGraph a, FavorGraph b) {
    if (a.nodes.length != b.nodes.length || a.edges.length != b.edges.length) {
      return false;
    }
    for (var i = 0; i < a.nodes.length; i++) {
      if (a.nodes[i].id != b.nodes[i].id) return false;
    }
    return true;
  }

  void _relayout() {
    _positions = _solveLayout(widget.graph);
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  /// Where each node sits inside [size], in pixels.
  ///
  /// One scale for both axes, then centered. Scaling x and y independently
  /// would fill the box more snugly but shear the layout, and in a
  /// force-directed graph the distances *are* the information: a stretched
  /// picture is a wrong one.
  List<Offset> _pixels(Size size) {
    const padX = 30.0;
    const padTop = 16.0;
    const padBottom = 30.0; // room for the name under the lowest node
    final w = math.max(size.width - padX * 2, 1.0);
    final h = math.max(size.height - padTop - padBottom, 1.0);
    final scale = math.min(w, h);
    final offX = padX + (w - scale) / 2;
    final offY = padTop + (h - scale) / 2;
    return [
      for (final p in _positions)
        Offset(offX + p.dx * scale, offY + p.dy * scale),
    ];
  }

  void _handleTap(Offset local, Size size) {
    final pixels = _pixels(size);
    final nodes = widget.graph.nodes;
    var bestIndex = -1;
    var bestDistance = double.infinity;

    for (var i = 0; i < nodes.length && i < pixels.length; i++) {
      final d = (pixels[i] - local).distance;
      // Generous slop: a 20px node is under the fingertip, not in front of it.
      if (d <= _radiusFor(nodes[i], nodes[i].id == widget.meId) + 14 &&
          d < bestDistance) {
        bestDistance = d;
        bestIndex = i;
      }
    }

    // A tap on empty board clears the selection, the way back out without
    // hunting for a close button.
    widget.onSelect?.call(bestIndex < 0 ? null : nodes[bestIndex]);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, widget.height);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _handleTap(details.localPosition, size),
            child: AnimatedBuilder(
              animation: _reveal,
              builder: (context, _) => CustomPaint(
                size: size,
                painter: _GraphPainter(
                  graph: widget.graph,
                  positions: _pixels(size),
                  meId: widget.meId,
                  selectedId: widget.selectedId,
                  progress: Curves.easeOutCubic.transform(_reveal.value),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

double _radiusFor(GraphNode node, bool isMe) {
  // sqrt, not linear: degree 9 should read as busier than degree 1 without
  // drawing a node nine times the area and crowding everyone else off.
  final base = 9.0 + 2.6 * math.sqrt(node.degree.toDouble());
  return math.min(base, 22.0) + (isMe ? 4.0 : 0.0);
}

/// Fruchterman-Reingold, run to convergence up front.
///
/// Deterministic by construction: seeds sit on a circle at distinct angles
/// (which also keeps any two nodes from starting at zero distance, where the
/// repulsion term would divide by zero), and nothing random enters after.
List<Offset> _solveLayout(FavorGraph graph) {
  final n = graph.nodes.length;
  if (n == 0) return const [];
  if (n == 1) return const [Offset(0.5, 0.5)];

  final index = {for (var i = 0; i < n; i++) graph.nodes[i].id: i};
  final pos = <Offset>[
    for (var i = 0; i < n; i++)
      Offset(
        0.5 + 0.35 * math.cos(2 * math.pi * i / n),
        0.5 + 0.35 * math.sin(2 * math.pi * i / n),
      ),
  ];

  // Collapse the directed multigraph to undirected pair strengths: two people
  // who helped each other four times are one strong tie, not four springs.
  final springs = <(int, int), double>{};
  for (final e in graph.edges) {
    final a = index[e.src], b = index[e.dst];
    if (a == null || b == null || a == b) continue;
    final key = a < b ? (a, b) : (b, a);
    springs[key] = (springs[key] ?? 0) + math.max(e.strength, 0.05);
  }

  // Ideal edge length. The textbook sqrt(area/n) assumes nodes fill the
  // board evenly; with a handful of people it makes every edge want to be a
  // third of the board long, repulsion beats attraction everywhere, and the
  // layout relaxes into a featureless ring. Shortening it lets ties pull
  // groups together while repulsion still keeps discs apart.
  final k = 0.45 * math.sqrt(1.0 / n);
  var temp = 0.14;
  const iterations = 320;

  for (var step = 0; step < iterations; step++) {
    final disp = List<Offset>.filled(n, Offset.zero);

    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        var delta = pos[i] - pos[j];
        var d = delta.distance;
        if (d < 1e-4) {
          // Two nodes exactly on top of each other: nudge along a fixed axis
          // rather than a random one, so the layout stays reproducible.
          delta = Offset(1e-4 * (i + 1), 0);
          d = delta.distance;
        }
        final force = (k * k) / d;
        final push = delta / d * force;
        disp[i] += push;
        disp[j] -= push;
      }
    }

    springs.forEach((pair, strength) {
      final (i, j) = pair;
      final delta = pos[i] - pos[j];
      final d = math.max(delta.distance, 1e-4);
      // Stronger ties pull harder, so recent reciprocal favors sit close.
      final force = (d * d) / k * math.min(strength, 3.0);
      final pull = delta / d * force;
      disp[i] -= pull;
      disp[j] += pull;
    });

    for (var i = 0; i < n; i++) {
      final d = disp[i].distance;
      if (d > 1e-9) {
        final capped = disp[i] / d * math.min(d, temp);
        // Gravity toward the middle. It has to be firm: a node with no
        // edges feels only repulsion, so under a weak pull it flies to the
        // rim and stretches the bounding box until everyone else is
        // squeezed into one corner of the board.
        final gravity = (const Offset(0.5, 0.5) - pos[i]) * 0.03;
        pos[i] += capped + gravity;
      }
    }
    temp *= 0.985;
  }

  return _normalize(pos);
}

/// Fit the solved positions to the unit square, preserving aspect so the
/// layout isn't stretched into a different shape than the one solved for.
List<Offset> _normalize(List<Offset> pos) {
  var minX = double.infinity, maxX = -double.infinity;
  var minY = double.infinity, maxY = -double.infinity;
  for (final p in pos) {
    minX = math.min(minX, p.dx);
    maxX = math.max(maxX, p.dx);
    minY = math.min(minY, p.dy);
    maxY = math.max(maxY, p.dy);
  }
  final spanX = math.max(maxX - minX, 1e-6);
  final spanY = math.max(maxY - minY, 1e-6);
  final span = math.max(spanX, spanY);
  final offX = (span - spanX) / 2, offY = (span - spanY) / 2;
  return [
    for (final p in pos)
      Offset((p.dx - minX + offX) / span, (p.dy - minY + offY) / span),
  ];
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.graph,
    required this.positions,
    required this.meId,
    required this.selectedId,
    required this.progress,
  });

  final FavorGraph graph;
  final List<Offset> positions;
  final String meId;
  final String? selectedId;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.length != graph.nodes.length) return;
    final index = {
      for (var i = 0; i < graph.nodes.length; i++) graph.nodes[i].id: i,
    };

    _paintEdges(canvas, index);
    _paintNodes(canvas);
  }

  void _paintEdges(Canvas canvas, Map<String, int> index) {
    // Collapse to one line per pair: the map shows that two people are tied
    // and how strongly, not one stripe per historical favor.
    final pairs = <(int, int), ({double strength, bool touchesMe})>{};
    for (final e in graph.edges) {
      final a = index[e.src], b = index[e.dst];
      if (a == null || b == null || a == b) continue;
      final key = a < b ? (a, b) : (b, a);
      final prior = pairs[key];
      pairs[key] = (
        strength: (prior?.strength ?? 0) + e.strength,
        touchesMe: (prior?.touchesMe ?? false) || e.src == meId || e.dst == meId,
      );
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    pairs.forEach((pair, info) {
      final (i, j) = pair;
      final selected = selectedId != null &&
          (graph.nodes[i].id == selectedId || graph.nodes[j].id == selectedId);

      paint
        ..strokeWidth = (1.2 + info.strength * 2.0).clamp(1.2, 4.5)
        ..color = selected
            ? FColors.blue.withValues(alpha: 0.85)
            : info.touchesMe
                ? FColors.blue.withValues(alpha: 0.34 * progress)
                : FColors.hairlineStrong.withValues(alpha: 0.9 * progress);

      // Edges draw out from their midpoint as the map reveals.
      final mid = Offset.lerp(positions[i], positions[j], 0.5)!;
      canvas.drawLine(
        Offset.lerp(mid, positions[i], progress)!,
        Offset.lerp(mid, positions[j], progress)!,
        paint,
      );
    });
  }

  void _paintNodes(Canvas canvas) {
    for (var i = 0; i < graph.nodes.length; i++) {
      final node = graph.nodes[i];
      final isMe = node.id == meId;
      final isSelected = node.id == selectedId;
      final center = positions[i];
      final r = _radiusFor(node, isMe) * progress;
      if (r <= 0) continue;

      // A ring of surface color between overlapping marks, so two adjacent
      // nodes stay countable where they touch.
      canvas.drawCircle(center, r + 2, Paint()..color = FColors.surface);

      // "You" is marked by form, not hue: a filled brand-blue disc with a
      // halo. Reusing a cluster color for it would make one community look
      // like the viewer.
      final fill = isMe ? FColors.blue : GraphPalette.forCluster(node.cluster);
      if (isMe || isSelected) {
        canvas.drawCircle(
          center,
          r + 6,
          Paint()..color = fill.withValues(alpha: 0.16),
        );
      }
      canvas.drawCircle(center, r, Paint()..color = fill);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 2.5 : 1.5
          ..color = isSelected ? FColors.ink : FColors.canvas,
      );
    }

    _paintLabels(canvas);
  }

  /// Names, drawn after every disc so none is painted over, and in priority
  /// order so that when the board is crowded the ones that get dropped are
  /// the ones that matter least.
  ///
  /// A name is skipped rather than allowed to overlap one already placed:
  /// two names on top of each other identify nobody, and the node is still
  /// one tap from telling you who it is.
  void _paintLabels(Canvas canvas) {
    if (progress < 0.6) return;

    final order = List.generate(graph.nodes.length, (i) => i)
      ..sort((a, b) {
        final na = graph.nodes[a], nb = graph.nodes[b];
        int rank(GraphNode n) =>
            n.id == meId ? 0 : (n.id == selectedId ? 1 : 2);
        final byRank = rank(na).compareTo(rank(nb));
        if (byRank != 0) return byRank;
        return nb.degree.compareTo(na.degree);
      });

    final placed = <Rect>[];
    final opacity = ((progress - 0.6) / 0.4).clamp(0.0, 1.0);

    for (final i in order) {
      final node = graph.nodes[i];
      final isMe = node.id == meId;
      final first = node.name.trim().split(RegExp(r'\s+')).first;
      if (first.isEmpty) continue;

      final painter = TextPainter(
        text: TextSpan(
          text: isMe ? 'You' : first,
          // Text wears text ink, never the mark's color: the disc beside it
          // already carries the community.
          style: (isMe ? FType.captionStrong : FType.caption).copyWith(
            color: isMe ? FColors.blue : FColors.inkSecondary,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '\u2026',
      )..layout(maxWidth: 74);

      final center = positions[i];
      final r = _radiusFor(node, isMe) * progress;
      final origin = Offset(center.dx - painter.width / 2, center.dy + r + 5);
      // Pad the reserved box so two names never sit shoulder to shoulder.
      final box = Rect.fromLTWH(
        origin.dx - 3,
        origin.dy - 2,
        painter.width + 6,
        painter.height + 4,
      );

      if (placed.any(box.overlaps)) continue;
      placed.add(box);

      canvas.saveLayer(
        box,
        Paint()..color = const Color(0xFF000000).withValues(alpha: opacity),
      );
      painter.paint(canvas, origin);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.progress != progress ||
      old.selectedId != selectedId ||
      !identical(old.graph, graph) ||
      !identical(old.positions, positions);
}
