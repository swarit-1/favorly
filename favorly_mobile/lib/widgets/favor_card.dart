import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/favors_provider.dart';
import '../services/trellis_client.dart';
import '../theme/tokens.dart';
import 'surfaces.dart';

/// Plain-English name for how much a favor asks of you.
String effortLabel(String effort) => switch (effort) {
      'low' => 'Quick',
      'high' => 'Big lift',
      _ => 'Some effort',
    };

int _effortSteps(String effort) => switch (effort) {
      'low' => 1,
      'high' => 3,
      _ => 2,
    };

/// Three bars and a word. Neutral on purpose: effort is a fact about the
/// favor, not a warning, so it never borrows the attention color.
class EffortMeter extends StatelessWidget {
  const EffortMeter(this.effort, {super.key, this.showLabel = true});

  final String effort;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final steps = _effortSteps(effort);
    final label = effortLabel(effort);
    return Semantics(
      label: 'Effort: ${label.toLowerCase()}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 3; i++) ...[
            Container(
              width: 4,
              height: 4 + i * 3,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(
                color: i <= steps ? FColors.inkSecondary : FColors.hairlineStrong,
                borderRadius: BorderRadius.circular(FRadius.pill),
              ),
            ),
          ],
          if (showLabel) ...[
            const SizedBox(width: FSpace.xs),
            Text(label, style: FType.caption.copyWith(color: FColors.inkSecondary)),
          ],
        ],
      ),
    );
  }
}

/// One recommended favor in a list: what it is, who needs it, why it reached
/// you, and what it costs you. A summary, not a pitch — the detail screen
/// carries the argument.
///
/// The card carries no border of its own: it sits inside a [Panel] with the
/// other rows, and the in-progress tint is the only thing that breaks the
/// white. In-progress falls back to the provider so a card is correct
/// wherever it is dropped; pass [started] when the list already knows.
class FavorCard extends ConsumerWidget {
  const FavorCard({super.key, required this.favor, this.started, this.onTap});

  final FavorSuggestion favor;
  final bool? started;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracked = ref.watch(
      favorsProvider.select((s) => s.startedNeedIds.contains(favor.needId)),
    );
    final inProgress = started ?? tracked;

    return Pressable(
      onTap: onTap,
      label: inProgress
          ? '${favor.title}, for ${favor.requesterName}, in progress'
          : '${favor.title}, for ${favor.requesterName}',
      child: Container(
        padding: const EdgeInsets.all(FSpace.lg),
        decoration: BoxDecoration(
          color: inProgress ? FColors.blueTint : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    favor.title,
                    style: FType.bodyStrong,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (inProgress) ...[
                  const SizedBox(width: FSpace.sm),
                  const StatusPill(
                    'In progress',
                    kind: PillKind.info,
                    icon: CupertinoIcons.arrow_2_circlepath,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${favor.requesterName} asked',
              style: FType.bodySmall.copyWith(color: FColors.inkSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (favor.reason.isNotEmpty) ...[
              const SizedBox(height: FSpace.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(CupertinoIcons.sparkles, size: 14, color: FColors.blue),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      favor.reason,
                      style: FType.caption.copyWith(color: FColors.inkSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: FSpace.md),
            Row(
              children: [
                EffortMeter(favor.effort),
                const SizedBox(width: FSpace.md),
                Expanded(
                  child: Text(
                    favor.posted,
                    textAlign: TextAlign.right,
                    style: FType.caption.copyWith(color: FColors.inkTertiary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
