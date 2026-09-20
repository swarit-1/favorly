import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/asks_provider.dart';
import '../providers/auth_provider.dart';
import '../services/trellis_client.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/error_panel.dart';
import '../widgets/page.dart';
import '../widgets/people.dart';
import '../widgets/surfaces.dart';

/// The three people Favorly picked for an ask: three different kinds of tie,
/// each with a true, human reason and the little path that explains it.
///
/// No scores anywhere. The `signals` map is parsed and never rendered.
class MatchesScreen extends ConsumerStatefulWidget {
  const MatchesScreen({
    super.key,
    required this.needId,
    required this.title,
    this.whenText = '',
    this.initialHelpers,
  });

  final String needId;
  final String title;
  final String whenText;

  /// Helpers already in hand (from the ask flow or the asks poll), so the
  /// screen draws people immediately instead of a spinner.
  final List<HelperMatch>? initialHelpers;

  @override
  ConsumerState<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends ConsumerState<MatchesScreen> {
  List<HelperMatch> _helpers = const [];
  Timer? _poll;
  bool _busy = false;
  bool _broadcasted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _helpers = widget.initialHelpers ?? const [];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_helpers.isEmpty) _refresh();
      _syncPolling();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  HelperMatch? get _pending {
    for (final h in _helpers) {
      if (h.isPending) return h;
    }
    return null;
  }

  HelperMatch? get _accepted {
    for (final h in _helpers) {
      if (h.isAccepted) return h;
    }
    return null;
  }

  Future<void> _refresh() async {
    try {
      final helpers = await TrellisClient.helpers(widget.needId);
      if (!mounted) return;
      setState(() => _helpers = helpers);
      _syncPolling();
      // Keep the home card in the same story.
      final userId = ref.read(authProvider).userId;
      if (userId != null) {
        unawaited(ref.read(asksProvider.notifier).refresh(userId));
      }
    } catch (e) {
      if (!mounted) return;
      // Between polls a blip is not worth a banner; only a screen with
      // nothing on it needs the excuse.
      if (_helpers.isEmpty) setState(() => _error = e.toString());
    }
  }

  /// Poll every 4 s while an invite is out and unanswered; the acceptance
  /// arrives through here. Stops itself when there is nothing to wait for.
  void _syncPolling() {
    final wants = _pending != null && _accepted == null;
    if (wants && _poll == null) {
      _poll = Timer.periodic(
          const Duration(seconds: 4), (_) => _refresh());
    } else if (!wants && _poll != null) {
      _poll?.cancel();
      _poll = null;
    }
  }

  Future<void> _invite(HelperMatch helper) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await TrellisClient.invite(
          needId: widget.needId, helperId: helper.personId);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _helpers = [
          for (final h in _helpers)
            h.personId == helper.personId
                ? h.withInviteStatus('pending')
                : h,
        ];
      });
      _syncPolling();
    } on TrellisConflict catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
      _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _broadcast() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await TrellisClient.broadcast(widget.needId);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _broadcasted = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accepted = _accepted;
    final pending = _pending;

    return FavorlyPage(
      topBar: const FTopBar(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        PageTitle(
          widget.title,
          subtitle: widget.whenText.isEmpty ? null : widget.whenText,
          padding: const EdgeInsets.only(top: 4, bottom: 18),
        ),
        if (_broadcasted) ...[
          const Notice(
            'Everyone in your circle can see this now.',
            kind: NoticeKind.success,
            icon: CupertinoIcons.speaker_2,
          ),
          const SizedBox(height: FSpace.lg),
        ],
        ErrorPanel(_error),
        if (_helpers.isEmpty && _error == null)
          const EmptyState(
            icon: CupertinoIcons.person_2,
            title: 'Finding the right neighbor',
            body: 'Favorly is looking around your circle. The three people '
                'worth asking land here.',
          )
        else
          Panel(
            children: [
              for (final helper in _helpers)
                _PersonMatchCard(
                  helper: helper,
                  // While one invite is out (or answered yes), the other
                  // cards step back the way held favors do.
                  dimmed: (pending != null || accepted != null) &&
                      !helper.isPending &&
                      !helper.isAccepted,
                  busy: _busy,
                  canInvite:
                      pending == null && accepted == null && !_busy,
                  onInvite: () => _invite(helper),
                ),
            ],
          ),
        if (accepted == null && _helpers.isNotEmpty) ...[
          const SizedBox(height: FSpace.lg),
          Center(
            child: FTextButton(
              'Ask everyone instead',
              color: FColors.inkTertiary,
              onPressed: _busy || _broadcasted ? null : _broadcast,
            ),
          ),
        ],
      ],
    );
  }
}

/// One helper: the person, the tie, the reason, the path. The button is the
/// only saturated thing on the card.
class _PersonMatchCard extends StatelessWidget {
  const _PersonMatchCard({
    required this.helper,
    required this.dimmed,
    required this.busy,
    required this.canInvite,
    required this.onInvite,
  });

  final HelperMatch helper;
  final bool dimmed;
  final bool busy;
  final bool canInvite;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final ink = dimmed ? FColors.inkTertiary : FColors.ink;
    final sub = dimmed ? FColors.inkTertiary : FColors.inkSecondary;

    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InitialsAvatar(helper.displayName, size: 48),
                const SizedBox(width: FSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        helper.displayName,
                        style: FType.bodyStrong.copyWith(color: ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${helper.headline} · ${helper.where}',
                        style: FType.bodySmall.copyWith(color: sub),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: FSpace.sm),
                StatusPill(
                  helper.tieLabel,
                  kind: helper.isAccepted
                      ? PillKind.success
                      : PillKind.info,
                ),
              ],
            ),
            if (helper.reason.isNotEmpty) ...[
              const SizedBox(height: FSpace.sm),
              // The same sparkles line FavorCard draws: one sentence about
              // the two of you, never arithmetic.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Icon(
                      CupertinoIcons.sparkles,
                      size: 12,
                      color: dimmed ? FColors.inkTertiary : FColors.blue,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      helper.reason,
                      style:
                          FType.caption.copyWith(color: FColors.inkTertiary),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: FSpace.md),
            _PathStrip(helper: helper, dimmed: dimmed),
            const SizedBox(height: FSpace.md),
            if (helper.isAccepted)
              _AcceptedBlock(helper: helper)
            else if (helper.isPending)
              _WaitingLine(name: helper.firstName)
            else if (helper.isDeclined)
              Text(
                '${helper.firstName} can\'t this time.',
                style: FType.caption.copyWith(color: FColors.inkTertiary),
              )
            else
              FButton(
                label: 'Ask ${helper.firstName}',
                compact: true,
                busy: busy && canInvite,
                onPressed: canInvite ? onInvite : null,
              ),
          ],
        ),
      ),
    );
  }
}

/// The six-degrees idea, one card at a time: You, whoever carries the
/// introduction, and them. A new face gets two endpoints and a dotted line,
/// honest about the gap the favor would close.
class _PathStrip extends StatelessWidget {
  const _PathStrip({required this.helper, required this.dimmed});

  final HelperMatch helper;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final distant = helper.tie == 'new' || helper.hops > 3;
    final names = distant && helper.path.length >= 2
        ? [helper.path.first.name, helper.path.last.name]
        : helper.path.map((p) => p.name).toList();
    if (names.length < 2) return const SizedBox.shrink();

    final color = dimmed ? FColors.inkTertiary : FColors.blue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 10,
          child: CustomPaint(
            size: const Size(double.infinity, 10),
            painter: _PathPainter(
              stops: names.length,
              dotted: distant,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          names.join(' · '),
          style: FType.caption.copyWith(
            color: dimmed ? FColors.inkTertiary : FColors.inkSecondary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _PathPainter extends CustomPainter {
  const _PathPainter({
    required this.stops,
    required this.dotted,
    required this.color,
  });

  final int stops;
  final bool dotted;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const r = 3.5;
    const inset = r + 1;
    final y = size.height / 2;
    final span = size.width - inset * 2;
    final xs = [
      for (var i = 0; i < stops; i++)
        inset + span * (stops == 1 ? 0 : i / (stops - 1)),
    ];

    final line = Paint()
      ..color = color.withValues(alpha: dotted ? 0.7 : 0.55)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < xs.length - 1; i++) {
      final from = Offset(xs[i] + r + 1, y);
      final to = Offset(xs[i + 1] - r - 1, y);
      if (dotted) {
        const dash = 4.0, gap = 4.0;
        var x = from.dx;
        while (x < to.dx) {
          canvas.drawLine(
            Offset(x, y),
            Offset((x + dash).clamp(from.dx, to.dx), y),
            line,
          );
          x += dash + gap;
        }
      } else {
        canvas.drawLine(from, to, line);
      }
    }

    final dot = Paint()..color = color;
    for (final x in xs) {
      canvas.drawCircle(Offset(x, y), r, dot);
    }
  }

  @override
  bool shouldRepaint(_PathPainter old) =>
      old.stops != stops || old.dotted != dotted || old.color != color;
}

/// The invite is out. Pulses gently so waiting reads as alive, not stuck.
class _WaitingLine extends StatefulWidget {
  const _WaitingLine({required this.name});

  final String name;

  @override
  State<_WaitingLine> createState() => _WaitingLineState();
}

class _WaitingLineState extends State<_WaitingLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.45,
    upperBound: 1,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _pulse,
      child: Row(
        children: [
          const Icon(CupertinoIcons.ellipsis, size: 16, color: FColors.blue),
          const SizedBox(width: FSpace.sm),
          Text(
            'Waiting on ${widget.name}',
            style: FType.bodySmallStrong.copyWith(color: FColors.blue),
          ),
        ],
      ),
    );
  }
}

/// They said yes: the spark, the unit (only now), and the one next step.
class _AcceptedBlock extends StatelessWidget {
  const _AcceptedBlock({required this.helper});

  final HelperMatch helper;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Notice(
          '${helper.firstName} is in',
          kind: NoticeKind.success,
          icon: CupertinoIcons.checkmark_circle_fill,
        ),
        if (helper.spark != null) ...[
          const SizedBox(height: FSpace.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(CupertinoIcons.sparkles,
                    size: 14, color: FColors.blue),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  helper.spark!,
                  style:
                      FType.caption.copyWith(color: FColors.inkSecondary),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: FSpace.xs),
        // Both sides said yes, so `where` has become the unit.
        Text(
          helper.where,
          style: FType.caption.copyWith(color: FColors.inkSecondary),
        ),
        const SizedBox(height: FSpace.md),
        FButton(
          label: 'Message ${helper.firstName}',
          compact: true,
          icon: CupertinoIcons.chat_bubble,
          onPressed: () {
            // TODO(4.6): open the real thread once messaging is wired live.
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    '${helper.firstName} got your ask. Knock, or say hi '
                    'in person.'),
              ),
            );
          },
        ),
      ],
    );
  }
}
