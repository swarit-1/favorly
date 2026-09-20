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

/// The off-boarding beat: a rating, an optional note, done. The rating is the
/// ask, not a toll — "Just mark it done" is always one tap away.
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
      setState(() => _localError = 'Sign in again to leave a rating.');
      return;
    }
    setState(() {
      _busy = true;
      _localError = null;
    });

    if (!_finished) {
      await notifier.finish(widget.favor.needId);
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

    return SheetBody(
      children: [
        SheetTitle(
          'How did it go?',
          subtitle: '${widget.favor.title} · for ${widget.favor.requesterName}',
        ),
        if (noteFailed)
          const Notice(
            'The favor is marked done. Only your note didn’t send.',
            kind: NoticeKind.success,
          ),
        _StarRating(
          value: _rating,
          onChanged: _busy ? null : (v) => setState(() => _rating = v),
        ),
        const SizedBox(height: FSpace.xxl),
        const FieldLabel('Anything worth noting?', hint: 'optional'),
        TextField(
          controller: _comment,
          minLines: 3,
          maxLines: 6,
          enabled: !_busy,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Went smoothly, the line was long…',
          ),
        ),
        ErrorPanel(error),
      ],
      bottom: BottomActions(
        children: [
          FButton(
            label: noteFailed ? 'Try sending again' : 'Finish and send',
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
        ],
      ),
    );
  }
}

const _ratingWords = ['Rough', 'Could be better', 'Fine', 'Good', 'Great'];

/// Five stars, each its own 48pt target with its own label, so this works by
/// touch and by screen reader. Tapping the current star clears it.
class _StarRating extends StatelessWidget {
  const _StarRating({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var star = 1; star <= 5; star++)
              Semantics(
                button: true,
                selected: value >= star,
                inMutuallyExclusiveGroup: true,
                label: star == 1 ? '1 star' : '$star stars',
                excludeSemantics: true,
                child: InkResponse(
                  onTap: onChanged == null
                      ? null
                      : () => onChanged!(value == star ? 0 : star),
                  radius: 26,
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: FColors.attentionTint,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(
                      value >= star ? CupertinoIcons.star_fill : CupertinoIcons.star,
                      size: 30,
                      color: value >= star
                          ? FColors.attentionIcon
                          : FColors.hairlineStrong,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: FSpace.sm),
        Text(
          value == 0 ? 'Tap a star' : _ratingWords[value - 1],
          style: FType.bodySmallStrong.copyWith(
            color: value == 0 ? FColors.inkTertiary : FColors.ink,
          ),
        ),
      ],
    );
  }
}
