import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../state/demo_store.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/buttons.dart';
import '../widgets/page.dart';
import '../widgets/surfaces.dart';

/// What one neighbor owes, and the Venmo hand-off. No money moves in-app.
class SettlementScreen extends ConsumerWidget {
  const SettlementScreen({super.key, required this.tripId});

  final String tripId;

  Future<void> _pay(BuildContext context, Settlement s, Member shopper) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(s.venmoLink),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      messenger.showSnackBar(SnackBar(
        content: Text('Couldn’t open Venmo. Send @${shopper.venmoHandle} ${money(s.total)}.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    final trip = store.tripById(tripId);
    final shopper = store.memberById(trip.shopperId);
    final settlement = store.settlementFor(tripId, store.meId);

    if (settlement == null) {
      return FavorlyPage(
        topBar: FTopBar(title: trip.store),
        children: const [
          PageTitle(
            'Nothing to settle',
            subtitle: 'Nothing on the receipt was for you this time.',
          ),
        ],
      );
    }

    return FavorlyPage(
      topBar: FTopBar(title: trip.store),
      children: [
        Notice(
          trip.status == TripStatus.done ? 'Delivered' : '${shopper.firstName} is back',
          kind: NoticeKind.success,
        ),
        const SizedBox(height: 22),
        Text('You owe ${shopper.firstName}', style: FType.body.copyWith(color: FColors.inkSecondary)),
        const SizedBox(height: 2),
        Text(money(settlement.total), style: FType.display),
        const SizedBox(height: 20),
        Panel(
          dividers: false,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            for (final line in settlement.lines) KeyValueRow(line.description, money(line.amount)),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Divider(),
            ),
            KeyValueRow('Subtotal', money(settlement.subtotal)),
            KeyValueRow('Your tax share', money(settlement.taxShare)),
            KeyValueRow('Total', money(settlement.total), strong: true),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Favorly never touches your money. Venmo opens with the amount and a note filled in.',
          style: FType.caption.copyWith(color: FColors.inkSecondary),
        ),
      ],
      bottom: settlement.paid
          ? const Notice('Paid. Thanks for closing the loop.', kind: NoticeKind.success)
          : BottomActions(
              children: [
                FButton(
                  label: 'Pay ${money(settlement.total)} with Venmo',
                  icon: CupertinoIcons.arrow_up_right,
                  onPressed: () => _pay(context, settlement, shopper),
                ),
                FButton(
                  label: 'Mark as paid',
                  kind: FButtonKind.secondary,
                  onPressed: () {
                    store.markPaid(tripId, settlement.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Marked as paid. ${shopper.firstName} will see it.')),
                    );
                  },
                ),
              ],
            ),
    );
  }
}
