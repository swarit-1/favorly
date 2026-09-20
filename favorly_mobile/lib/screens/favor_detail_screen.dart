import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/favor_category.dart';
import '../providers/auth_provider.dart';
import '../providers/favors_provider.dart';
import '../services/trellis_client.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/error_panel.dart';
import '../widgets/favor_card.dart';
import '../widgets/page.dart';
import '../widgets/people.dart';
import '../widgets/surfaces.dart';
import 'favor_finish_sheet.dart';

/// The signals, read as facts about the two of you rather than as weights.
/// Nobody decides whether to help a neighbor by comparing bar lengths; they
/// decide by knowing the person, so the screen says what is true between you
/// and leaves the arithmetic on the server.
///
/// Freshness is missing on purpose: how recently they posted says nothing
/// about the two of you.
const _connectionFacts = <String, (IconData, String)>{
  'reciprocity': (CupertinoIcons.arrow_2_squarepath, 'They have helped you before'),
  'forward': (CupertinoIcons.arrow_turn_up_right, 'You helped someone close to them'),
  'mutual': (CupertinoIcons.person_2, 'You share people in common'),
  'trip': (CupertinoIcons.location, 'You were already headed that way'),
  'fit': (CupertinoIcons.hand_thumbsup, 'It is the kind of thing you do'),
  // v2 matcher signals, same rule: a fact about the two of you, never a bar.
  'capability': (CupertinoIcons.cube_box, 'You have what they need'),
  'nearness': (CupertinoIcons.placemark, 'You live close by'),
  'similarity': (CupertinoIcons.sparkles, 'You have things in common'),
  'tie': (CupertinoIcons.link, 'You share people in common'),
};

/// First name only, the way you would say it out loud. Empty for a favor that
/// arrived without a name on it, so callers can fall back in their own words.
String _firstNameOf(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.split(RegExp(r'\s+')).first;
}

/// One favor, in two quite different moods.
///
/// As a suggestion it introduces a person: who asked, in their words, and the
/// one sentence saying what you two already have. Once you are on it the
/// introduction is over, so the screen becomes the person you are helping and
/// the handful of things you would want to reread standing in an aisle.
///
/// Both moods are built from the same three blocks — the person, the ask,
/// their words — so moving between them feels like the same thread continuing
/// rather than a different screen.
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

  bool get _hasName => _favor.requesterName.trim().isNotEmpty;

  /// A favor without a name on it is still somebody's, so it never renders blank.
  String get _name => _hasName ? _favor.requesterName.trim() : 'A neighbor';

  String get _firstName => _hasName ? _firstNameOf(_favor.requesterName) : 'them';

  /// The ask, once. The model's instruction when there is one, the short title
  /// otherwise: printing both only ever said the same thing twice.
  String get _ask => _favor.action.isNotEmpty ? _favor.action : _favor.title;

  /// How much it asks of you and when it was asked, as one quiet line under
  /// the name. Either half may be missing.
  String get _meta => [
        if (_favor.effort.isNotEmpty) effortLabel(_favor.effort),
        if (_favor.posted.isNotEmpty) 'asked ${_favor.posted}',
      ].join(' · ');

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
    await ref.read(favorsProvider.notifier).start(_favor, userId);
    if (!mounted) return;
    setState(() => _busy = false);
  }

  /// They asked for you and the answer is no. Quiet on purpose: declining a
  /// neighbor should feel like a soft word, not an action with a color.
  Future<void> _decline() async {
    final userId = ref.read(authProvider).userId;
    if (userId == null) {
      setState(() => _localError = 'Sign in again to answer this.');
      return;
    }
    setState(() {
      _busy = true;
      _localError = null;
    });
    try {
      await TrellisClient.respondInvite(
        needId: _favor.needId,
        helperId: userId,
        accept: false,
      );
      if (!mounted) return;
      // The list underneath refreshes on its own clock; kick it so the row
      // does not linger, and step back out.
      unawaited(ref.read(favorsProvider.notifier).load(userId, force: true));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _localError = e.toString();
      });
    }
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
    final mine = state.isActive(_favor.needId);

    return FavorlyPage(
      topBar: FTopBar(title: mine ? 'In progress' : 'Favor'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: mine ? _inProgress(state) : _suggestion(state),
      bottom: mine
          ? FButton(
              label: 'Wrap up with $_firstName',
              icon: CupertinoIcons.checkmark_alt,
              onPressed: _busy ? null : _finish,
            )
          : FButton(
              label: 'Start this favor',
              busy: _busy,
              onPressed: _busy || !state.canStart(_favor.needId) ? null : _start,
            ),
    );
  }

  /// A suggestion: somebody asked, and you have not answered yet. The person
  /// leads, the ask follows, and one sentence says why the two of you.
  List<Widget> _suggestion(FavorsState state) {
    final other = _firstNameOf(state.active?.requesterName ?? '');

    return [
      Row(
        children: [
          InitialsAvatar(_name, size: 56),
          const SizedBox(width: FSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name,
                  style: FType.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_meta.isNotEmpty)
                  Text(
                    _meta,
                    style: FType.caption.copyWith(color: FColors.inkTertiary),
                  ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: FSpace.xxl),
      Text(_ask, style: FType.heading),
      if (state.hasActive) ...[
        const SizedBox(height: FSpace.xl),
        Notice(
          other.isEmpty
              ? 'You are on another favor. This one keeps.'
              : 'You are helping $other. This one keeps until you wrap that up.',
          kind: NoticeKind.attention,
          icon: CupertinoIcons.person_crop_circle_badge_checkmark,
          action: 'See it',
          onAction: () => Navigator.of(context).popUntil((r) => r.isFirst),
        ),
      ],
      ErrorPanel(_localError ?? state.error),
      if (_favor.originalRequest.isNotEmpty) ...[
        const SizedBox(height: FSpace.lg),
        _Quote(text: _favor.originalRequest, who: _name),
      ],
      ..._whySection(),
      if (_favor.invited) ...[
        const SizedBox(height: FSpace.xl),
        Center(
          child: FTextButton(
            'Not this time',
            color: FColors.inkTertiary,
            onPressed: _busy ? null : _decline,
          ),
        ),
      ],
    ];
  }

  /// You are on it. No ranking, no case to make: the person you are helping
  /// takes the top of the screen, and everything under it is what you need
  /// while you are out.
  List<Widget> _inProgress(FavorsState state) {
    return [
      _HelpingHeader(name: _name, startedAt: state.activeStartedAt),
      ErrorPanel(_localError ?? state.error),
      const SizedBox(height: FSpace.xxl),
      Text(_ask, style: FType.heading),
      if (_favor.originalRequest.isNotEmpty) ...[
        const SizedBox(height: FSpace.lg),
        _Quote(text: _favor.originalRequest, who: _name),
      ],
      const SizedBox(height: FSpace.xxl),
      // Blue, not grey: grey is the colour of their words a few lines up, and
      // two identical strips read as two quotes rather than a quote and an
      // instruction. The wording follows what kind of favor it is: returning
      // a ladder is not the same beat as spending an afternoon together.
      Notice(
        switch (_favor.category) {
          FavorCategory.borrow =>
            'Meet at the door. Close it out here once it is back with you.',
          FavorCategory.company =>
            'Enjoy it. Close it out here afterwards.',
          FavorCategory.hands || FavorCategory.skill =>
            'Work through it together, then close it out here.',
          _ =>
            'Hand it over in person, then close it out here so $_firstName '
                'knows it landed.',
        },
        kind: NoticeKind.info,
        icon: CupertinoIcons.checkmark_circle,
      ),
      const SizedBox(height: FSpace.sm),
      Text(
        'Cannot make it? Tell $_firstName, and they can ask again.',
        style: FType.caption.copyWith(color: FColors.inkTertiary),
      ),
      ..._connectionSection(),
    ];
  }

  /// Why this reached you, in the sentence the server already wrote. It is
  /// built from the same graph facts the bars were drawing, so showing both
  /// was showing one thing twice; the sentence is the half a neighbor would
  /// actually say out loud.
  List<Widget> _whySection() {
    if (_favor.reason.isEmpty) return _connectionSection();

    return [
      const SectionHeader('Why you'),
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
              style: FType.body.copyWith(color: FColors.inkSecondary),
            ),
          ),
        ],
      ),
      const SizedBox(height: FSpace.md),
      Text(
        'Trellis only points at people. Whether you go is yours.',
        style: FType.caption.copyWith(color: FColors.inkTertiary),
      ),
    ];
  }

  /// What the two of you already have, built only out of signals the server
  /// actually sent. A favor rehydrated from a bare need row has none, and an
  /// empty block would be a worse answer than no block.
  ///
  /// Editorial order, not score order: these are facts, and sorting them would
  /// turn the relationship back into a leaderboard.
  List<Widget> _connectionSection() {
    // v1 "mutual" and v2 "tie" say the same sentence; a server sending both
    // should still read as one fact, so dedupe on the words.
    final seen = <String>{};
    final facts = [
      for (final entry in _connectionFacts.entries)
        if ((_favor.signals[entry.key] ?? 0) > 0 && seen.add(entry.value.$2))
          entry.value,
    ];
    if (facts.isEmpty) return const [];

    return [
      SectionHeader(_hasName ? 'You and $_firstName' : 'You two'),
      Panel(
        dividerIndent: 64,
        children: [
          for (final (icon, text) in facts)
            PanelRow(
              leading: LeadingIcon(
                icon,
                color: FColors.blue,
                background: FColors.blueTint,
              ),
              title: text,
              titleStyle: FType.bodySmall,
            ),
        ],
      ),
    ];
  }
}

/// The one saturated surface on this screen, and the whole point of state B:
/// you are not on an errand, you are on Maya. Same gradient as the home hero
/// so arriving here feels like the same thread continuing.
class _HelpingHeader extends StatelessWidget {
  const _HelpingHeader({required this.name, required this.startedAt});

  final String name;

  /// Null when the claim came back from the server rather than from this
  /// device, in which case the line is dropped rather than guessed at.
  final DateTime? startedAt;

  @override
  Widget build(BuildContext context) {
    const white = FColors.onAccent;
    final soft = white.withValues(alpha: 0.9);
    final since = agoLabel(startedAt);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FRadius.xl),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [FColors.bluePressed, FColors.blue, FColors.blueBright],
          stops: [0, 0.55, 1],
        ),
      ),
      // The same light as the home hero: this is the same favor, carried
      // across from the blue box you tapped.
      child: Stack(
        children: [
          const Positioned(
            right: -70,
            top: -100,
            child: Orb(size: 230, opacity: 0.12),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow('You are helping', color: soft),
                const SizedBox(height: FSpace.md),
                Row(
                  children: [
                    InitialsAvatar(name, size: 48, onAccent: true),
                    const SizedBox(width: FSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: FType.title.copyWith(color: white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (since.isNotEmpty)
                            Text(
                              'Started $since',
                              style: FType.caption.copyWith(color: soft),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
