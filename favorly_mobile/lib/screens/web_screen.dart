import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/favors_provider.dart';
import '../providers/graph_provider.dart';
import '../services/trellis_client.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/error_panel.dart';
import '../widgets/favor_graph_view.dart';
import '../widgets/page.dart';
import '../widgets/people.dart';
import '../widgets/surfaces.dart';

/// How the graph sees the circle, and why it put the favors it did in front
/// of you.
///
/// Everything on this screen is already-visible history rendered a second
/// way, no new facts, no scores about people. The one number the graph keeps
/// and never shows, `give_balance`, stays hidden here too: a reciprocity
/// scoreboard is exactly what this product is not.
class WebScreen extends ConsumerStatefulWidget {
  const WebScreen({super.key});

  @override
  ConsumerState<WebScreen> createState() => _WebScreenState();
}

class _WebScreenState extends ConsumerState<WebScreen> {
  GraphNode? _selected;

  @override
  Widget build(BuildContext context) {
    final meId = ref.watch(authProvider).userId;
    if (meId == null) {
      return const FavorlyPage(children: [
        EmptyState(
          icon: CupertinoIcons.circle_grid_hex,
          title: 'Sign in to see the web',
          body: 'The map is drawn from your circle, so it needs to know who you are.',
        ),
      ]);
    }

    final graph = ref.watch(favorGraphProvider(meId));
    final favors = ref.watch(favorsProvider);

    return FavorlyPage(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const PageTitle(
          'The web',
          subtitle: 'How favors connect your circle',
          padding: EdgeInsets.only(top: 12, bottom: 18),
        ),
        graph.when(
          loading: () => const _MapSkeleton(),
          error: (e, _) => ErrorPanel('$e'),
          data: (g) => _map(context, g, meId),
        ),
        const SectionHeader('Why these reached you'),
        Text(
          'Every favor the app suggests is scored on the same handful of '
          'signals. Open one to see which fired, and how much each counted.',
          style: FType.bodySmall.copyWith(color: FColors.inkSecondary),
        ),
        const SizedBox(height: FSpace.lg),
        if (favors.favors.isEmpty && favors.active == null)
          const EmptyState(
            icon: CupertinoIcons.sparkles,
            title: 'Nothing to explain yet',
            body: 'When a neighbor posts something you are well placed to help '
                'with, the reasoning shows up here.',
          )
        else
          Panel(
            dividerIndent: 16,
            children: [
              for (final favor in [
                if (favors.active != null) favors.active!,
                ...favors.favors,
              ])
                _MatchRow(favor: favor, isActive: favors.isActive(favor.needId)),
            ],
          ),
      ],
    );
  }

  Widget _map(BuildContext context, FavorGraph g, String meId) {
    if (g.isEmpty) {
      return const EmptyState(
        icon: CupertinoIcons.circle_grid_hex,
        title: 'No web yet',
        body: 'Once favors start moving around your circle, the connections '
            'they make show up here.',
      );
    }

    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: FColors.surface,
            borderRadius: BorderRadius.circular(FRadius.xl),
          ),
          clipBehavior: Clip.antiAlias,
          child: FavorGraphView(
            graph: g,
            meId: meId,
            selectedId: selected?.id,
            onSelect: (node) => setState(
              () => _selected = node?.id == _selected?.id ? null : node,
            ),
          ),
        ),
        const SizedBox(height: FSpace.md),
        _Legend(graph: g),
        const SizedBox(height: FSpace.sm),
        Text(
          'Thicker lines are stronger ties. Favors fade as they age, so the '
          'web shows what is live, not everything that ever happened.',
          style: FType.caption.copyWith(color: FColors.inkTertiary),
        ),
        if (selected != null && selected.id != meId) ...[
          const SizedBox(height: FSpace.lg),
          _ThreadCard(meId: meId, node: selected),
        ] else if (selected != null) ...[
          const SizedBox(height: FSpace.lg),
          Notice(
            'That is you, ${plural(selected.degree, 'neighbor')} connected so far.',
            kind: NoticeKind.neutral,
            icon: CupertinoIcons.person_crop_circle,
          ),
        ] else ...[
          const SizedBox(height: FSpace.lg),
          const Notice(
            'Tap anyone to see what ties you to them.',
            kind: NoticeKind.neutral,
            icon: CupertinoIcons.hand_point_right,
          ),
        ],
      ],
    );
  }
}

/// Names each community on the map, so identity never rests on color alone.
class _Legend extends StatelessWidget {
  const _Legend({required this.graph});

  final FavorGraph graph;

  @override
  Widget build(BuildContext context) {
    final present = graph.nodes.map((n) => n.cluster).toSet().toList()..sort();
    final named = present.where((c) => c >= 0 && c < GraphPalette.clusters.length);
    final hasOther = present.any((c) => c < 0 || c >= GraphPalette.clusters.length);

    return Wrap(
      spacing: FSpace.md,
      runSpacing: FSpace.sm,
      children: [
        const _LegendDot(color: FColors.blue, label: 'You'),
        for (final c in named)
          _LegendDot(
            color: GraphPalette.clusters[c],
            label: 'Group ${c + 1}',
          ),
        if (hasOther)
          const _LegendDot(color: GraphPalette.other, label: 'Everyone else'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: FType.caption.copyWith(color: FColors.inkSecondary)),
      ],
    );
  }
}

/// What ties you to one neighbor: the pairwise view behind a node tap.
class _ThreadCard extends ConsumerWidget {
  const _ThreadCard({required this.meId, required this.node});

  final String meId;
  final GraphNode node;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thread = ref.watch(
      favorThreadProvider((meId: meId, otherId: node.id)),
    );

    return Panel(
      padding: const EdgeInsets.all(FSpace.lg),
      dividers: false,
      children: [
        Row(
          children: [
            InitialsAvatar(node.name, size: 40),
            const SizedBox(width: FSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(node.name, style: FType.subheading),
                  Text(
                    plural(node.degree, 'connection'),
                    style: FType.caption.copyWith(color: FColors.inkTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: FSpace.lg),
        thread.when(
          loading: () => const _Shimmer(height: 60),
          error: (e, _) => ErrorPanel('$e'),
          data: (t) => _body(t),
        ),
      ],
    );
  }

  Widget _body(FavorThread t) {
    if (t.isEmpty) {
      return Text(
        'Nothing between you two yet. That is not a gap to close, it is just '
        'what the graph knows.',
        style: FType.bodySmall.copyWith(color: FColors.inkSecondary),
      );
    }

    final first = node.name.trim().split(RegExp(r'\s+')).first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (t.hasHistory) ...[
          _Fact(
            icon: CupertinoIcons.arrow_up_right,
            text: t.given.count == 0
                ? 'You have not picked anything up for $first yet.'
                : 'You helped $first ${plural(t.given.count, 'time')}'
                    '${t.given.lastAt == null ? '' : ', last ${agoLabel(t.given.lastAt)}'}.',
          ),
          _Fact(
            icon: CupertinoIcons.arrow_down_left,
            text: t.received.count == 0
                ? '$first has not picked anything up for you yet.'
                : '$first helped you ${plural(t.received.count, 'time')}'
                    '${t.received.lastAt == null ? '' : ', last ${agoLabel(t.received.lastAt)}'}.',
          ),
        ],
        if (t.mutuals.isNotEmpty)
          _Fact(
            icon: CupertinoIcons.person_2,
            text: 'You both know ${joinNames(t.mutuals.take(3).toList())}'
                '${t.mutuals.length > 3 ? ' and ${t.mutuals.length - 3} more' : ''}.',
          ),
        if (t.sharedClaims.isNotEmpty)
          _Fact(
            icon: CupertinoIcons.tag,
            text: 'You both mentioned '
                '${joinNames(t.sharedClaims.take(3).map((c) => c.label).toList())}.',
          ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 15, color: FColors.inkTertiary),
          ),
          const SizedBox(width: FSpace.sm),
          Expanded(
            child: Text(
              text,
              style: FType.bodySmall.copyWith(color: FColors.inkSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// One recommendation, expandable into the arithmetic behind it.
class _MatchRow extends StatefulWidget {
  const _MatchRow({required this.favor, required this.isActive});

  final FavorSuggestion favor;
  final bool isActive;

  @override
  State<_MatchRow> createState() => _MatchRowState();
}

class _MatchRowState extends State<_MatchRow> {
  bool _open = false;

  static const _labels = {
    'trip': 'Already going',
    'reciprocity': 'They helped you',
    'mutual': 'Shared neighbors',
    'fit': 'You can, they cannot',
    'affinity': 'You know this need',
    'freshness': 'Posted recently',
  };

  @override
  Widget build(BuildContext context) {
    final f = widget.favor;
    final fired = [
      for (final e in f.signals.entries)
        if (e.value > 0 && _labels.containsKey(e.key)) e,
    ]..sort((a, b) => f.why
        .contribution(b.key, b.value)
        .compareTo(f.why.contribution(a.key, a.value)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Pressable(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.all(FSpace.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InitialsAvatar(f.requesterName, size: 34),
                const SizedBox(width: FSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.title.isEmpty ? f.originalRequest : f.title,
                        style: FType.bodySmallStrong,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.isActive
                            ? 'You are on this one'
                            : '${plural(fired.length, 'signal')} fired',
                        style: FType.caption.copyWith(
                          color: widget.isActive
                              ? FColors.blue
                              : FColors.inkTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _open
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 16,
                  color: FColors.inkTertiary,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: FMotion.normal,
          sizeCurve: FMotion.curve,
          crossFadeState:
              _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: _Breakdown(favor: f, fired: fired, labels: _labels),
        ),
      ],
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({
    required this.favor,
    required this.fired,
    required this.labels,
  });

  final FavorSuggestion favor;
  final List<MapEntry<String, double>> fired;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    final why = favor.why;
    // The tallest contribution sets the scale, so the bars compare against
    // each other rather than against a ceiling nothing ever reaches.
    final top = fired.isEmpty
        ? 1.0
        : fired
            .map((e) => why.contribution(e.key, e.value))
            .reduce((a, b) => a > b ? a : b);

    return Padding(
      padding: const EdgeInsets.fromLTRB(FSpace.lg, 0, FSpace.lg, FSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (favor.reason.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(FSpace.md),
              decoration: BoxDecoration(
                color: FColors.blueTint,
                borderRadius: BorderRadius.circular(FRadius.md),
              ),
              child: Text(
                favor.reason,
                style: FType.bodySmall.copyWith(color: FColors.ink),
              ),
            ),
            const SizedBox(height: FSpace.lg),
          ],
          for (final e in fired)
            Padding(
              padding: const EdgeInsets.only(bottom: FSpace.md),
              child: _Bar(
                label: labels[e.key]!,
                detail: _detailFor(e.key, why),
                fraction: top <= 0 ? 0 : why.contribution(e.key, e.value) / top,
              ),
            ),
          if (fired.isEmpty)
            Text(
              'No signal fired for this one. It is here because no one has '
              'offered yet.',
              style: FType.caption.copyWith(color: FColors.inkTertiary),
            ),
          const SizedBox(height: FSpace.xs),
          Text(
            'Bar length is how much that signal moved this favor up the list.',
            style: FType.caption.copyWith(color: FColors.inkTertiary),
          ),
        ],
      ),
    );
  }

  /// The concrete fact behind a signal, where the graph handed one over.
  /// Absent for signals that are pure arithmetic, like freshness.
  String? _detailFor(String key, MatchEvidence why) {
    switch (key) {
      case 'trip':
        return why.tripReason;
      case 'reciprocity':
        return why.favorCount == 0
            ? null
            : '${plural(why.favorCount, 'favor')} for you';
      case 'mutual':
        return why.mutualNames.isEmpty
            ? null
            : joinNames(why.mutualNames.take(2).toList());
      case 'fit':
        return why.fitReason;
      case 'affinity':
        return why.affinityReason;
      default:
        return null;
    }
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.detail, required this.fraction});

  final String label;
  final String? detail;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: FType.captionStrong)),
            if (detail != null)
              Flexible(
                child: Text(
                  detail!,
                  style: FType.caption.copyWith(color: FColors.inkTertiary),
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: FColors.surface,
            valueColor: const AlwaysStoppedAnimation(FColors.blue),
          ),
        ),
      ],
    );
  }
}

class _MapSkeleton extends StatelessWidget {
  const _MapSkeleton();

  @override
  Widget build(BuildContext context) => const _Shimmer(height: 320);
}

class _Shimmer extends StatelessWidget {
  const _Shimmer({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: FColors.surface,
        borderRadius: BorderRadius.circular(FRadius.xl),
      ),
      alignment: Alignment.center,
      child: const CupertinoActivityIndicator(),
    );
  }
}
