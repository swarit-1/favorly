import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/favor_category.dart';
import '../models/models.dart';
import '../providers/asks_provider.dart';
import '../providers/auth_provider.dart';
import '../services/trellis_client.dart';
import '../state/demo_store.dart';
import '../theme/tokens.dart';
import '../util/nav.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/error_panel.dart';
import '../widgets/page.dart';
import '../widgets/surfaces.dart';
import '../widgets/voice_sheet.dart';
import 'add_list_screen.dart';
import 'matches_screen.dart';
import 'standalone_request_screen.dart';

/// The composer: say what you need, in your own words, and Favorly finds the
/// neighbor. One field, because the parsing is the server's job, not a form's.
class AskScreen extends ConsumerStatefulWidget {
  const AskScreen({super.key});

  @override
  ConsumerState<AskScreen> createState() => _AskScreenState();
}

/// Rotating examples: small, concrete, one per kind of favor, so the empty
/// field teaches the size of thing to ask for.
const _placeholders = [
  'Borrow a ladder for an hour',
  'Help me put up a shelf Saturday',
  'Walk the reservoir with me at 6',
  'Grab oat milk if you are out',
];

/// What a category chip drops into the field: the first few words of an ask,
/// never a finished sentence, so people keep talking in their own voice.
const _starters = <FavorCategory, String>{
  FavorCategory.errand: 'Pick up ',
  FavorCategory.borrow: 'Borrow ',
  FavorCategory.hands: 'Help me ',
  FavorCategory.skill: 'Show me how to ',
  FavorCategory.company: 'Join me for ',
  FavorCategory.ride: 'Give me a lift to ',
  FavorCategory.care: 'Keep an eye on ',
  FavorCategory.other: 'I could use a hand with ',
};

/// The four honest steps of finding someone. Steps 2 and 3 belong to the one
/// helpers call; splitting them names what the matcher is actually doing.
const _steps = [
  'Reading your ask',
  'Looking around your circle',
  'Picking three people',
  'Generating smart insights',
];

class _AskScreenState extends ConsumerState<AskScreen> {
  final _text = TextEditingController();
  Timer? _rotate;
  int _placeholderIndex = 0;
  FavorCategory? _chip;

  /// 0 = composing; 1..3 = which of [_steps] is running.
  int _step = 0;

  /// The scope check bounced it: the sentence, and the rewrite when there is
  /// one worth offering.
  String? _scopeReply;
  String? _rightSized;
  String? _error;

  bool get _busy => _step > 0;

  @override
  void initState() {
    super.initState();
    _rotate = Timer.periodic(const Duration(milliseconds: 3200), (_) {
      // Only the hint rotates; never someone's words.
      if (mounted && _text.text.isEmpty) {
        setState(() {
          _placeholderIndex = (_placeholderIndex + 1) % _placeholders.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _rotate?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _listen() async {
    final transcript = await showFavorlySheet<String>(
      context,
      builder: (_) => const VoiceCaptureSheet(
        title: 'Say what you need',
        prompt: 'Try: "I need to borrow a ladder for an hour today."',
        transcript: 'I need to borrow a ladder for an hour today',
      ),
    );
    if (transcript == null || !mounted) return;
    setState(() {
      _text.text = transcript;
      _chip = null;
    });
  }

  void _useStarter(FavorCategory category) {
    setState(() {
      // A chip only ever replaces an empty field or another chip's starter;
      // typed words are theirs and stay.
      final current = _text.text;
      final startedByChip =
          _chip != null && current == (_starters[_chip] ?? '');
      if (current.isEmpty || startedByChip) {
        _text.text = _starters[category] ?? '';
        _text.selection =
            TextSelection.collapsed(offset: _text.text.length);
      }
      _chip = category;
    });
  }

  /// The old "Add your list" home button lives here now: grocery lists keep
  /// their own richer flow (items, caps, substitutions).
  void _snapList() {
    final store = ref.read(storeProvider);
    final active = store.activeTrip;
    final openTrip = [
      ...store.upcomingTrips.where((t) => t.status == TripStatus.open),
      if (active?.status == TripStatus.open) active!,
    ].firstOrNull;
    if (openTrip != null) {
      push(context, AddListScreen(tripId: openTrip.id));
    } else {
      push(context, const StandaloneRequestScreen());
    }
  }

  /// The whole flow: intake, then, when the ask is in scope and not a grocery
  /// run, the ranked helpers, then the matches screen.
  Future<void> _find({bool confirmRightSized = false}) async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final userId = ref.read(authProvider).userId;
    if (userId == null) {
      setState(() => _error = 'Sign in again to ask for a hand.');
      return;
    }

    setState(() {
      _step = 1;
      _scopeReply = null;
      _rightSized = null;
      _error = null;
    });

    try {
      final result = await TrellisClient.intake(
        personId: userId,
        text: text,
        confirmRightSized: confirmRightSized,
      );
      if (!mounted) return;

      final need = result.need;
      if (!result.isOk || need == null) {
        setState(() {
          _step = 0;
          if (result.scope == 'too_big' || result.scope == 'needs_pro') {
            _scopeReply = result.scopeReply ??
                'That is bigger than one favor. Want to start smaller?';
            _rightSized = result.rightSized;
          } else {
            // not_ok, unclear, or an intent that is not an ask at all.
            _scopeReply = result.scopeReply ??
                'Favorly could not read that as a favor. Try saying it '
                    'another way.';
          }
        });
        return;
      }

      if (need.category == FavorCategory.errand) {
        // Groceries already have a whole machine: trips, merged lists,
        // substitutions. Route the parsed items into it rather than
        // reinventing a worse one here.
        setState(() => _step = 0);
        final listText =
            need.items.isNotEmpty ? need.items.join('\n') : need.body;
        if (!mounted) return;
        push(context, StandaloneRequestScreen(initialText: listText));
        return;
      }

      setState(() => _step = 2);
      // Fetch both concurrently so matches screen has recs ready immediately
      final helpersF = TrellisClient.helpers(need.id);
      final recsF = TrellisClient.recommendations(userId, limit: 3);

      final helpers = await helpersF;
      if (!mounted) return;

      setState(() => _step = 3);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;

      setState(() => _step = 4);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;

      final recs = await recsF;
      unawaited(ref.read(asksProvider.notifier).refresh(userId));

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => MatchesScreen(
            needId: need.id,
            title: need.title,
            whenText: need.whenText,
            initialHelpers: helpers,
            initialNearby: recs,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = 0;
        _error = e.toString();
      });
    }
  }

  void _useRightSized() {
    final rewrite = _rightSized;
    if (rewrite == null) return;
    setState(() {
      _text.text = rewrite;
      _text.selection = TextSelection.collapsed(offset: rewrite.length);
    });
    _find(confirmRightSized: true);
  }

  void _reword() {
    setState(() {
      _scopeReply = null;
      _rightSized = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FavorlyPage(
      topBar: const FTopBar(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const PageTitle(
          'What do you need a hand with?',
          subtitle: 'Say it like you would to a neighbor in the hall.',
          padding: EdgeInsets.only(top: 4, bottom: 18),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _text,
                minLines: 3,
                maxLines: 6,
                autofocus: true,
                enabled: !_busy,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: _placeholders[_placeholderIndex],
                ),
              ),
            ),
            const SizedBox(width: FSpace.sm),
            FIconButton(
              icon: CupertinoIcons.mic,
              label: 'Say it instead',
              filled: true,
              color: FColors.blue,
              onPressed: _busy ? null : _listen,
            ),
          ],
        ),
        const SizedBox(height: FSpace.lg),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final category in FavorCategory.values) ...[
                SelectChip(
                  label: category.label,
                  icon: category.icon,
                  selected: _chip == category,
                  onTap: _busy ? () {} : () => _useStarter(category),
                ),
                if (category != FavorCategory.values.last)
                  const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        if (_busy) ...[
          const SizedBox(height: FSpace.xxl),
          _FindingSteps(current: _step),
        ],
        if (!_busy && _scopeReply != null) ...[
          const SizedBox(height: FSpace.xl),
          Notice(
            _scopeReply!,
            kind: NoticeKind.attention,
            icon: CupertinoIcons.arrow_down_right_arrow_up_left,
          ),
          if (_rightSized != null) ...[
            const SizedBox(height: FSpace.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(FSpace.lg),
              decoration: BoxDecoration(
                color: FColors.surface,
                borderRadius: BorderRadius.circular(FRadius.lg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('“$_rightSized”', style: FType.body),
                  const SizedBox(height: FSpace.sm),
                  Text(
                    'A neighbor-sized first piece',
                    style:
                        FType.caption.copyWith(color: FColors.inkTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FSpace.md),
            FButton(label: 'Use that', onPressed: _useRightSized),
            const SizedBox(height: FSpace.sm),
            FButton(
              label: 'Reword it',
              kind: FButtonKind.tertiary,
              onPressed: _reword,
            ),
          ],
        ],
        ErrorPanel(_error),
        const SizedBox(height: FSpace.xxl),
        Panel(
          children: [
            PanelRow(
              leading: const LeadingIcon(
                CupertinoIcons.camera,
                color: FColors.blue,
                background: FColors.blueTint,
              ),
              title: 'Have a grocery list? Snap it',
              subtitle: 'Lists ride along on a neighbor\'s trip.',
              onTap: _busy ? null : _snapList,
            ),
          ],
        ),
      ],
      bottom: FButton(
        label: 'Find my neighbor',
        icon: CupertinoIcons.sparkles,
        busy: _busy,
        onPressed:
            _busy || _text.text.trim().isEmpty ? null : () => _find(),
      ),
    );
  }
}

/// The three steps, drawn honestly: done gets a check, the current one a
/// spinner, the rest wait their turn.
class _FindingSteps extends StatelessWidget {
  const _FindingSteps({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: FSpace.md),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: i + 1 < current
                      ? const Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          size: 20,
                          color: FColors.success,
                        )
                      : i + 1 == current
                          ? const CupertinoActivityIndicator(radius: 9)
                          : const Icon(
                              CupertinoIcons.circle,
                              size: 20,
                              color: FColors.inkDisabled,
                            ),
                ),
                const SizedBox(width: FSpace.md),
                Expanded(
                  child: Text(
                    _steps[i],
                    style: i + 1 <= current
                        ? FType.bodySmallStrong
                        : FType.bodySmall
                            .copyWith(color: FColors.inkTertiary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
