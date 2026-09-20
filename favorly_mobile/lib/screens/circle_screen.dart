import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/demo_cast.dart';
import '../state/demo_store.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../util/nav.dart';
import 'web_screen.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/insurance_badge.dart';
import '../widgets/page.dart';
import '../widgets/people.dart';
import '../widgets/referral_card.dart';
import '../widgets/surfaces.dart';
import '../widgets/unlock_progress.dart';

/// Members and the reciprocity ledger. Plain counts, no scores.
class CircleScreen extends ConsumerWidget {
  const CircleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    final rows = store.ledgerRows;

    return FavorlyPage(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const PageTitle(
          DemoStore.circleName,
          subtitle: 'Neighbors helping neighbors',
          padding: EdgeInsets.only(top: 12, bottom: 18),
        ),
        // The web first: the graph is the story of the circle, and this is
        // the row the demo walks through before "done" snaps the path solid.
        Panel(
          children: [
            PanelRow(
              leading: const LeadingIcon(
                CupertinoIcons.circle_grid_hex,
                color: FColors.blue,
                background: FColors.blueTint,
              ),
              title: 'See the web',
              subtitle: 'How favors connect your circle',
              onTap: () => push(context, const WebScreen()),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (store.lastCompletedTripId != null) ...[
          Notice(
            'Trip delivered. Ledger updated.',
            kind: NoticeKind.success,
            action: 'Dismiss',
            onAction: store.dismissLedgerBanner,
          ),
          const SizedBox(height: 16),
        ],
        UnlockProgressWidget(status: store.unlocksFor(DEMO_CIRCLE_ID)),
        const SizedBox(height: 16),
        if (store.unlocksFor(DEMO_CIRCLE_ID).claimedUnlocks.isNotEmpty) ...[
          SectionHeader('Claimed Rewards'),
          Column(
            children: [
              for (final unlock in store.unlocksFor(DEMO_CIRCLE_ID).claimedUnlocks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: UnlockRewardCard(unlock: unlock),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        ReferralCard(
          stats: store.referralStatsFor(store.meId),
          onCopyCode: () async {
            final messenger = ScaffoldMessenger.of(context);
            final code = store.referralStatsFor(store.meId).inviteCode;
            await Clipboard.setData(ClipboardData(text: code));
            messenger.showSnackBar(
              const SnackBar(content: Text('Code copied. Share it!')),
            );
          },
        ),
        const SizedBox(height: 16),
        if (store.referralStatsFor(store.meId).referrals.isNotEmpty) ...[
          SectionHeader('Referral Rewards'),
          Column(
            children: [
              for (final reward in store.referralStatsFor(store.meId).referrals)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ReferralRewardTile(
                    reward: reward,
                    referreeName: store.memberById(reward.referreeId).name,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Panel(
          dividerIndent: 68,
          children: [
            for (final row in rows)
              Column(
                children: [
                  PanelRow(
                    leading: Avatar(store.memberById(row.memberId), size: 40),
                    title: store.memberById(row.memberId).name +
                        (row.memberId == store.meId ? ' (you)' : ''),
                    subtitle: '${plural(row.tripsRun, 'trip')} run · '
                        '${plural(row.favorsReceived, 'favor')} received',
                    trailing: row.dollarsCarried <= 0
                        ? null
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(money(row.dollarsCarried), style: FType.moneySmall),
                              Text(
                                'carried',
                                style: FType.caption.copyWith(color: FColors.inkTertiary),
                              ),
                            ],
                          ),
                  ),
                  if (store.isInsuranceEligible(row.memberId))
                    Padding(
                      padding: const EdgeInsets.only(left: 68, top: 8, bottom: 8),
                      child: InsuranceBadge(
                          status: store.insuranceFor(row.memberId)),
                    ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 16),
        const Notice(
          'A simple history of giving and receiving. No scores, no rankings.',
          kind: NoticeKind.neutral,
          icon: CupertinoIcons.heart,
        ),
        const SectionHeader('Invite a neighbor'),
        Panel(
          children: [
            PanelRow(
              leading: const LeadingIcon(CupertinoIcons.person_badge_plus),
              title: DemoStore.inviteCode,
              titleStyle: FType.money.copyWith(letterSpacing: 2),
              subtitle: 'Anyone with this code joins the circle.',
              trailing: FTextButton(
                'Copy',
                icon: CupertinoIcons.doc_on_doc,
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(const ClipboardData(text: DemoStore.inviteCode));
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Code copied. Text it to a neighbor.')),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
