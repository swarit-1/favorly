import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/favors_provider.dart';
import '../services/trellis_client.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/error_panel.dart';
import '../widgets/favor_card.dart';
import '../widgets/page.dart';
import '../widgets/surfaces.dart';
import 'favor_finish_sheet.dart';

/// Plain English for each ranking signal. The map keys are the model's
/// vocabulary; these are the words a neighbor would use.
const _signalLabels = <String, String>{
  'trip': 'You’re already going to the store',
  'reciprocity': 'They’ve helped you before',
  'mutual': 'You share a connection',
  'fit': 'Fits what they need',
  'freshness': 'Posted recently',
};

/// One recommended favor, in full: what it is, their own words, why it was
/// surfaced for you, and the one action that moves it forward.
class FavorDetailScreen extends ConsumerStatefulWidget {
  const FavorDetailScreen({super.key, required this.favor});

  final FavorSuggestion favor;

  @override
  ConsumerState<FavorDetailScreen> createState() => _FavorDetailScreenState();
}

class _FavorDetailScreenState extends ConsumerState<FavorDetailScreen> {
  bool _busy = false;
  String? _localError;

  FavorSuggestion get _favor => widget.favor;

  Future<void> _start() async {
    final userId = ref.read(authProvider).userId;
    if (userId == null) {
      setState(() => _localError = 'Sign in again to take this favor on.');
      return;
    }
    setState(() {
      _busy = true;
      _localError = null;
    });
    await ref.read(favorsProvider.notifier).start(_favor.needId, userId);
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _finish() async {
    final done = await showFavorFinishSheet(context, favor: _favor);
    // The favor is off your plate once it is closed out; drop back to the list
    // rather than leaving a stale detail screen on the stack.
    if (done == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(favorsProvider);
    final started = state.startedNeedIds.contains(_favor.needId);

    return FavorlyPage(
      topBar: const FTopBar(title: 'Favor'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(_favor.title, style: FType.heading)),
            if (started) ...[
              const SizedBox(width: FSpace.md),
              const StatusPill(
                'In progress',
                kind: PillKind.info,
                icon: CupertinoIcons.arrow_2_circlepath,
              ),
            ],
          ],
        ),
        const SizedBox(height: FSpace.sm),
        Text(_favor.action, style: FType.body.copyWith(color: FColors.inkSecondary)),
        if (started) ...[
          const SizedBox(height: FSpace.lg),
          const Notice(
            'You’re on this one. Close it out when it’s done.',
            icon: CupertinoIcons.arrow_2_circlepath,
          ),
        ],
        ErrorPanel(_localError ?? state.error),
        const SizedBox(height: FSpace.xl),
        Panel(
          dividerIndent: 68,
          children: [
            PanelRow(
              leading: const LeadingIcon(CupertinoIcons.person),
              title: _favor.requesterName,
              subtitle: 'Asked ${_favor.posted}',
            ),
            PanelRow(
              leading: const LeadingIcon(CupertinoIcons.gauge),
              title: 'Effort',
              trailing: EffortMeter(_favor.effort),
            ),
          ],
        ),
        if (_favor.originalRequest.isNotEmpty) ...[
          const SectionHeader('Their exact words'),
          _Quote(text: _favor.originalRequest, who: _favor.requesterName),
        ],
        ..._whySection(),
      ],
      bottom: started
          ? FButton(
              label: 'Finish favor',
              icon: CupertinoIcons.checkmark_alt,
              onPressed: _busy ? null : _finish,
            )
          : FButton(
              label: 'Start this favor',
              busy: _busy,
              onPressed: _busy ? null : _start,
            ),
    );
  }

  /// The transparency block: why this favor was put in front of you. Signals
  /// with no weight are left out entirely — a row of empty bars says nothing.
  List<Widget> _whySection() {
    final signals = [
      for (final entry in _favor.signals.entries)
        if (entry.value > 0 && _signalLabels.containsKey(entry.key)) entry,
    ]..sort((a, b) => b.value.compareTo(a.value));

    if (_favor.reason.isEmpty && signals.isEmpty) return const [];

    return [
      const SectionHeader('Why this reached you'),
      if (_favor.reason.isNotEmpty)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 3),
              child: Icon(CupertinoIcons.sparkles, size: 16, color: FColors.blue),
            ),
            const SizedBox(width: FSpace.sm),
            Expanded(
              child: Text(
                _favor.reason,
                style: FType.bodySmall.copyWith(color: FColors.inkSecondary),
              ),
            ),
          ],
        ),
      if (signals.isNotEmpty) ...[
        const SizedBox(height: FSpace.xl),
        for (final signal in signals)
          Padding(
            padding: const EdgeInsets.only(bottom: FSpace.md),
            child: _SignalRow(
              label: _signalLabels[signal.key]!,
              value: signal.value.clamp(0.0, 1.0),
            ),
          ),
        const SizedBox(height: FSpace.xs),
        Text(
          'Longer bars counted for more. Nothing here is a promise — you decide.',
          style: FType.caption.copyWith(color: FColors.inkTertiary),
        ),
      ],
    ];
  }
}

/// The request as it was written. Verbatim, and said to be verbatim, so a
/// paraphrase is never mistaken for their words.
class _Quote extends StatelessWidget {
  const _Quote({required this.text, required this.who});

  final String text;
  final String who;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FSpace.lg),
      decoration: BoxDecoration(
        color: FColors.surface,
        borderRadius: BorderRadius.circular(FRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('“$text”', style: FType.body),
          const SizedBox(height: FSpace.sm),
          Text(
            '$who’s words, unedited',
            style: FType.caption.copyWith(color: FColors.inkTertiary),
          ),
        ],
      ),
    );
  }
}

/// One ranking signal: what it is and how much it weighed. The strength word
/// leads, the bar backs it up; the raw score never shows.
class _SignalRow extends StatelessWidget {
  const _SignalRow({required this.label, required this.value});

  final String label;
  final double value;

  String get _strength {
    if (value >= 0.66) return 'Strong';
    if (value >= 0.33) return 'Some';
    return 'Slight';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: FType.bodySmall)),
            const SizedBox(width: FSpace.sm),
            Text(_strength, style: FType.caption.copyWith(color: FColors.inkTertiary)),
          ],
        ),
        const SizedBox(height: 6),
        ProgressBar(value: value, height: 4, label: '$label, $_strength'),
      ],
    );
  }
}
