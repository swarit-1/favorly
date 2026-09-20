import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/favors_provider.dart';
import '../services/trellis_client.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/error_panel.dart';
import '../widgets/page.dart';
import '../widgets/people.dart';
import '../widgets/surfaces.dart';

/// Closes out a favor. Resolves to `true` once the favor is marked done.
Future<bool?> showFavorFinishSheet(
  BuildContext context, {
  required FavorSuggestion favor,
}) {
  return showFavorlySheet<bool>(
    context,
    builder: (_) => FavorFinishSheet(favor: favor),
  );
}

/// One answer to the connection question, and the 1..5 the review API stores
/// it as. Nothing maps to 1: a favor that fell flat is still someone who
/// showed up for you.
class _Connection {
  const _Connection(
    this.rating,
    this.icon,
    this.label,
    this.hint, {
    this.subdued = false,
  });

  final int rating;
  final IconData icon;
  final String label;
  final String hint;

  /// The honest-but-negative answer sits last and quieter, so picking it
  /// never feels like filing a complaint.
  final bool subdued;
}

const _connections = <_Connection>[
  _Connection(
    3,
    CupertinoIcons.arrow_right_arrow_left,
    'Quick handoff',
    'We barely crossed paths.',
  ),
  _Connection(
    4,
    CupertinoIcons.chat_bubble_2,
    'We got talking',
    'It turned into a real conversation.',
  ),
  _Connection(
    5,
    CupertinoIcons.sparkles,
    'Genuinely clicked',
    'I would go out of my way for them again.',
  ),
  _Connection(
    2,
    CupertinoIcons.cloud,
    'It did not really land',
    'Quiet, awkward, or not what I expected.',
    subdued: true,
  ),
];

/// The off-boarding beat: who you helped, whether the two of you actually
/// connected, and one thing worth remembering. The question is the ask, not a
/// toll: "Just mark it done" is always one tap away.
class FavorFinishSheet extends ConsumerStatefulWidget {
  const FavorFinishSheet({super.key, required this.favor});

  final FavorSuggestion favor;

  @override
  ConsumerState<FavorFinishSheet> createState() => _FavorFinishSheetState();
}

class _FavorFinishSheetState extends ConsumerState<FavorFinishSheet> {
  final _comment = TextEditingController();
  int _rating = 0;
  bool _busy = false;
  // The favor can be done while the note is still unsent: finish once, then
  // let a retry send only what failed.
  bool _finished = false;
  String? _localError;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send({required bool withRating}) async {
    final notifier = ref.read(favorsProvider.notifier);
    final reviewerId = ref.read(authProvider).userId;
    if (withRating && reviewerId == null) {
      setState(() => _localError = 'Sign in again to save how it went.');
      return;
    }
    setState(() {
      _busy = true;
      _localError = null;
    });

    if (!_finished) {
      // Passing the id lets the notifier rewrite this device's cache too.
      await notifier.finish(widget.favor.needId, personId: reviewerId);
      if (!mounted) return;
      if (ref.read(favorsProvider).error != null) {
        setState(() => _busy = false);
        return;
      }
      _finished = true;
    }

    if (withRating && reviewerId != null) {
      final comment = _comment.text.trim();
      await notifier.submitReview(
        needId: widget.favor.needId,
        reviewerId: reviewerId,
        rating: _rating,
        comment: comment.isEmpty ? null : comment,
      );
      if (!mounted) return;
      if (ref.read(favorsProvider).error != null) {
        setState(() => _busy = false);
        return;
      }
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(favorsProvider);
    final error = _localError ?? state.error;
    final noteFailed = _finished && error != null;
    // A rehydrated favor can arrive with every string empty, so the copy has
    // to read without a name at all.
    final name = widget.favor.requesterName.trim();
    final first = _firstName(name);
    final title = widget.favor.title.trim();

    return SheetBody(
      children: [
        _PersonHeader(
          name: name,
          headline: first.isEmpty ? 'You helped out' : 'You helped $first',
          subtitle: title.isEmpty ? 'That favor is done.' : '$title · done',
        ),
        if (noteFailed)
          const Notice(
            'The favor is marked done. Only your note didn’t send.',
            kind: NoticeKind.success,
          ),
        const SectionHeader('How did you two leave it?'),
        for (final option in _connections) ...[
          _ConnectionTile(
            option: option,
            selected: _rating == option.rating,
            onTap: _busy ? null : () => setState(() => _rating = option.rating),
          ),
          const SizedBox(height: FSpace.sm),
        ],
        const SizedBox(height: FSpace.lg),
        _NoteLabel(
          first.isEmpty
              ? 'Anything worth remembering?'
              : 'Anything worth remembering about $first?',
        ),
        TextField(
          controller: _comment,
          minLines: 3,
          maxLines: 6,
          enabled: !_busy,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Works nights, has a dog named Pepper…',
          ),
        ),
        ErrorPanel(error),
      ],
      bottom: BottomActions(
        children: [
          FButton(
            label: noteFailed ? 'Try sending again' : 'Save and finish',
            busy: _busy,
            onPressed:
                _rating == 0 || _busy ? null : () => _send(withRating: true),
          ),
          FButton(
            label: noteFailed ? 'Close' : 'Just mark it done',
            kind: FButtonKind.tertiary,
            onPressed: _busy
                ? null
                : noteFailed
                    ? () => Navigator.of(context).pop(true)
                    : () => _send(withRating: false),
          ),
          if (!noteFailed)
            Padding(
              padding: const EdgeInsets.only(top: FSpace.xs),
              child: Text(
                first.isEmpty
                    ? 'Finishing records the favor between the two of you.'
                    : 'Finishing records the favor between you and $first.',
                textAlign: TextAlign.center,
                style: FType.caption.copyWith(color: FColors.inkTertiary),
              ),
            ),
        ],
      ),
    );
  }
}

/// Trellis knows people by one display name, and it can be empty.
String _firstName(String name) {
  if (name.isEmpty) return '';
  return name.split(RegExp(r'\s+')).first;
}

/// Who this was for, before anything is asked of you.
class _PersonHeader extends StatelessWidget {
  const _PersonHeader({
    required this.name,
    required this.headline,
    required this.subtitle,
  });

  final String name;
  final String headline;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: FSpace.xs, bottom: FSpace.lg),
      child: Row(
        children: [
          InitialsAvatar(name, size: 48),
          const SizedBox(width: FSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  headline,
                  style: FType.heading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: FType.bodySmall.copyWith(color: FColors.inkSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One tappable answer. Selection has to survive a glance: tint, blue outline
/// and a checkmark all say it at once.
class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _Connection option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final subdued = option.subdued && !selected;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: '${option.label}. ${option.hint}',
      excludeSemantics: true,
      child: Material(
        color: selected ? FColors.blueTint : FColors.canvas,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FRadius.md),
          // Constant width: only the color changes, so nothing shifts by a
          // pixel when the selection moves.
          side: BorderSide(
            color: selected ? FColors.blue : FColors.hairline,
            width: 1.5,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: FColors.blueTint,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(
              horizontal: FSpace.md,
              vertical: FSpace.md,
            ),
            child: Row(
              children: [
                Icon(
                  option.icon,
                  size: 20,
                  color: selected
                      ? FColors.blue
                      : subdued
                          ? FColors.inkDisabled
                          : FColors.inkTertiary,
                ),
                const SizedBox(width: FSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        option.label,
                        style: FType.bodyStrong.copyWith(
                          color: subdued ? FColors.inkSecondary : FColors.ink,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        option.hint,
                        style: FType.caption.copyWith(
                          color: FColors.inkTertiary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: FSpace.sm),
                // Always laid out, visible only when picked, so the label
                // never reflows as the selection moves.
                Icon(
                  CupertinoIcons.checkmark_alt_circle_fill,
                  size: 22,
                  color: selected ? FColors.blue : Colors.transparent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// FieldLabel keeps its label and its hint on one unwrapped row, and this
/// label carries a name, so it wraps on its own.
class _NoteLabel extends StatelessWidget {
  const _NoteLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final quiet = FType.caption.copyWith(color: FColors.inkTertiary);
    return Padding(
      padding: const EdgeInsets.only(bottom: FSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(text, style: FType.bodySmallStrong)),
              const SizedBox(width: FSpace.sm),
              Text('optional', style: quiet),
            ],
          ),
          const SizedBox(height: 2),
          Text('A detail that helps next time you cross paths.', style: quiet),
        ],
      ),
    );
  }
}
