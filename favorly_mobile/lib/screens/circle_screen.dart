import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/demo_store.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/page.dart';
import '../widgets/people.dart';
import '../widgets/surfaces.dart';

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
        if (store.lastCompletedTripId != null) ...[
          Notice(
            'Trip delivered. Ledger updated.',
            kind: NoticeKind.success,
            action: 'Dismiss',
            onAction: store.dismissLedgerBanner,
          ),
          const SizedBox(height: 16),
        ],
        Panel(
          dividerIndent: 68,
          children: [
            for (final row in rows)
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
