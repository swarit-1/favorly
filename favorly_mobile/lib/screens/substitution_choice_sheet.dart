import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../state/demo_store.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/buttons.dart';
import '../widgets/capture.dart';
import '../widgets/page.dart';
import '../widgets/surfaces.dart';

Future<void> showSubstitutionChoiceSheet(BuildContext context, String promptId) {
  return showFavorlySheet<void>(
    context,
    builder: (_) => SubstitutionChoiceSheet(promptId: promptId),
  );
}

/// Requester side of the substitution beat: one tap plus confirm.
class SubstitutionChoiceSheet extends ConsumerStatefulWidget {
  const SubstitutionChoiceSheet({super.key, required this.promptId});

  final String promptId;

  @override
  ConsumerState<SubstitutionChoiceSheet> createState() =>
      _SubstitutionChoiceSheetState();
}

class _SubstitutionChoiceSheetState extends ConsumerState<SubstitutionChoiceSheet> {
  int? _selected = 0;

  void _resolve({int? chosenIndex}) {
    ref.read(storeProvider).resolveSubstitution(widget.promptId, chosenIndex: chosenIndex);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final prompt = store.pendingPrompt;
    if (prompt == null || prompt.id != widget.promptId) {
      return SheetBody(
        children: const [
          SheetTitle('Already settled', subtitle: 'This item was handled another way.'),
        ],
        bottom: FButton(
          label: 'Close',
          kind: FButtonKind.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      );
    }
    final trip = store.tripById(prompt.tripId);
    final shopper = store.memberById(trip.shopperId);
    final cap = prompt.maxPrice;

    return SheetBody(
      children: [
        Notice(
          '${shopper.firstName} needs your answer',
          kind: NoticeKind.attention,
          icon: CupertinoIcons.bubble_left_fill,
        ),
        const SizedBox(height: 16),
        SheetTitle(
          'Choose a substitute',
          subtitle: 'For ${prompt.originalName.toLowerCase()}'
              '${cap == null ? '' : ' · up to ${moneyShort(cap)}'}',
          trailing: CountdownRing(
            expiresAt: prompt.expiresAt,
            window: DemoStore.substitutionWindow,
            onExpired: () => _resolve(),
          ),
        ),
        for (var i = 0; i < prompt.candidates.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CandidateCard(
              candidate: prompt.candidates[i],
              selected: _selected == i,
              overCap: cap != null && prompt.candidates[i].price > cap,
              onTap: () => setState(() => _selected = i),
            ),
          ),
      ],
      bottom: BottomActions(
        children: [
          FButton(
            label: 'Choose this',
            onPressed: _selected == null ? null : () => _resolve(chosenIndex: _selected),
          ),
          FButton(
            label: 'Skip this item',
            kind: FButtonKind.tertiary,
            onPressed: () => _resolve(),
          ),
        ],
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.selected,
    required this.overCap,
    required this.onTap,
  });

  final ShelfCandidate candidate;
  final bool selected;
  final bool overCap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: Material(
        color: selected ? FColors.blueTint : FColors.canvas,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FRadius.lg),
          side: BorderSide(
            color: selected ? FColors.blue : FColors.hairline,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: FColors.canvas,
                    border: Border.all(
                      color: selected ? FColors.blue : FColors.hairlineStrong,
                      width: selected ? 7 : 2,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(candidate.name, style: FType.bodyStrong),
                      const SizedBox(height: 2),
                      Text(
                        '${candidate.size} · ${money(candidate.price)}',
                        style: FType.moneySmall.copyWith(
                          color: FColors.inkSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        overCap ? 'Over your cap · ${candidate.reason}' : candidate.reason,
                        style: FType.caption.copyWith(
                          color: overCap ? FColors.attention : FColors.inkSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
