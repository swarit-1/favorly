import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/favors_provider.dart';
import '../services/trellis_client.dart';
import '../theme/tokens.dart';
import 'people.dart';
import 'surfaces.dart';

/// Plain-English name for how much a favor asks of you.
///
/// A word, not a meter. Three little bars only ever said what "Quick" says,
/// and they said it on every row.
String effortLabel(String effort) => switch (effort) {
      'low' => 'Quick',
      'high' => 'Big lift',
      _ => 'Some effort',
    };

/// One neighbor who could use a hand.
///
/// The person leads, their ask follows, and one line says what the two of you
/// already have. Nothing else: this is a list you read down, and a score, a
/// timestamp and an effort chart on every row turn five people into a
/// spreadsheet.
///
/// The card carries no border of its own: it sits inside a [Panel] with the
/// other rows. It never renders the favor you are already on, that one lives
/// in the hero at the top of the home screen. When your plate is full the card
/// steps back to say "later", without hiding who is waiting.
class FavorCard extends ConsumerWidget {
  const FavorCard({super.key, required this.favor, this.waiting, this.onTap});

  final FavorSuggestion favor;

  /// Your plate is already full, so this one has to wait. Falls back to the
  /// provider so a card is correct wherever it is dropped.
  final bool? waiting;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracked = ref.watch(favorsProvider.select((s) => s.hasActive));
    final onHold = waiting ?? tracked;
    final ink = onHold ? FColors.inkTertiary : FColors.ink;
    final name = favor.requesterName.isEmpty ? 'A neighbor' : favor.requesterName;

    return Pressable(
      onTap: onTap,
      label: onHold
          ? '$name needs ${favor.title}, waiting on your current favor'
          : '$name needs ${favor.title}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Opacity(
              opacity: onHold ? 0.45 : 1,
              child: InitialsAvatar(name, size: 44),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: FType.bodyStrong.copyWith(color: ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    favor.title,
                    style: FType.bodySmall.copyWith(
                      color: onHold ? FColors.inkTertiary : FColors.inkSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Why the two of you: the only line here that is about the
                  // relationship rather than the errand, so it earns its space.
                  if (favor.reason.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Icon(
                            CupertinoIcons.sparkles,
                            size: 12,
                            color: onHold ? FColors.inkTertiary : FColors.blue,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            favor.reason,
                            style: FType.caption.copyWith(
                              color: FColors.inkTertiary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            // A full plate is the one thing worth spelling out; otherwise the
            // chevron is the whole call to action.
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: onHold
                  ? Text(
                      'Later',
                      style: FType.caption.copyWith(color: FColors.inkTertiary),
                    )
                  : const Icon(
                      CupertinoIcons.chevron_right,
                      size: 18,
                      color: FColors.inkTertiary,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
