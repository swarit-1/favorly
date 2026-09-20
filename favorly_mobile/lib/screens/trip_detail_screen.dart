import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../state/demo_store.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../util/nav.dart';
import '../widgets/buttons.dart';
import '../widgets/page.dart';
import '../widgets/people.dart';
import '../widgets/request_panel_enhanced.dart';
import '../widgets/surfaces.dart';
import '../widgets/trip_hero.dart';
import 'add_list_screen.dart';
import 'handoff_screen.dart';
import 'settlement_screen.dart';
import 'shopping_screen.dart';
import 'substitution_choice_sheet.dart';

/// One trip, seen from whichever side the person is on.
class TripDetailScreen extends ConsumerWidget {
  const TripDetailScreen({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    final trip = store.tripById(tripId);
    final shopper = store.memberById(trip.shopperId);
    final mine = store.isShopper(trip);

    final children = <Widget>[
      TripHero(
        trip: trip,
        shopper: shopper,
        isMine: mine,
        badge: trip.status == TripStatus.open
            ? '${store.spotsLeft(trip)} of ${trip.caps.maxRequesters} spots'
            : null,
      ),
      const SizedBox(height: 14),
      _CapsLine(trip: trip),
      if (mine)
        ..._shopperSections(context, store, trip)
      else
        ..._requesterSections(context, store, trip, shopper),
    ];

    return FavorlyPage(
      topBar: const FTopBar(title: 'Trip'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: children,
      bottom: mine
          ? _shopperAction(context, store, trip)
          : _requesterAction(context, store, trip, shopper),
    );
  }

  // ---------------------------------------------------------------- shopper

  List<Widget> _shopperSections(
    BuildContext context,
    DemoStore store,
    Trip trip,
  ) {
    final taking = trip.requests.where((r) => r.taking).toList();
    switch (trip.status) {
      case TripStatus.open:
      case TripStatus.shopping:
        final items = trip.items;
        final done = items.where((i) => !i.isOpen).length;
        return [
          if (trip.status == TripStatus.shopping) ...[
            const SizedBox(height: 16),
            Notice('You’re shopping. $done of ${items.length} items done.'),
          ],
          const SectionHeader('Lists from neighbors'),
          if (trip.requests.isEmpty)
            EmptyState(
              icon: CupertinoIcons.doc_text,
              title: 'No lists yet',
              body:
                  'Neighbors can add until you leave at ${clock(trip.departAt)}.',
            )
          else
            for (final r in trip.requests) ...[
              RequestPanelEnhanced(
                trip: trip,
                request: r,
                member: store.memberById(r.requesterId),
                editable: trip.status == TripStatus.open,
                onTaking: (v) => store.setTaking(trip.id, r.id, v),
                compatibilityScore: store
                    .compatibilityScore(store.meId, r.requesterId)
                    .score,
                tripsWorkedTogether: store
                    .compatibilityScore(store.meId, r.requesterId)
                    .tripsWorkedTogether,
              ),
              const SizedBox(height: 10),
            ],
        ];
      case TripStatus.settling:
      case TripStatus.done:
        final settlements = store.settlementsFor(trip.id);
        return [
          if (trip.status == TripStatus.done) ...[
            const SizedBox(height: 16),
            const Notice(
              'Delivered. The ledger is updated.',
              kind: NoticeKind.success,
            ),
          ],
          const SectionHeader('Who owes what'),
          if (settlements.isEmpty)
            const Notice(
              'Nobody owes anything for this trip.',
              kind: NoticeKind.neutral,
            )
          else
            Panel(
              dividerIndent: 68,
              children: [
                for (final s in settlements)
                  PanelRow(
                    leading: Avatar(store.memberById(s.requesterId), size: 40),
                    title: store.memberById(s.requesterId).name,
                    subtitle: s.paid ? 'Paid' : 'Waiting for payment',
                    value: money(s.total),
                    trailing: s.paid
                        ? const Icon(
                            CupertinoIcons.checkmark_circle_fill,
                            size: 22,
                            color: FColors.success,
                          )
                        : null,
                  ),
              ],
            ),
          if (taking.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Each neighbor sees their own items, a proportional tax share, and a Venmo link.',
              style: FType.caption.copyWith(color: FColors.inkSecondary),
            ),
          ],
        ];
    }
  }

  Widget? _shopperAction(BuildContext context, DemoStore store, Trip trip) {
    switch (trip.status) {
      case TripStatus.open:
        return FButton(
          label: 'Start shopping',
          onPressed: () {
            store.startShopping(trip.id);
            push(context, ShoppingScreen(tripId: trip.id));
          },
        );
      case TripStatus.shopping:
        return FButton(
          label: 'Continue shopping',
          onPressed: () => push(context, ShoppingScreen(tripId: trip.id)),
        );
      case TripStatus.settling:
        return FButton(
          label: 'Confirm handoff',
          onPressed: () => push(context, HandoffScreen(tripId: trip.id)),
        );
      case TripStatus.done:
        return null;
    }
  }

  // -------------------------------------------------------------- requester

  List<Widget> _requesterSections(
    BuildContext context,
    DemoStore store,
    Trip trip,
    Member shopper,
  ) {
    final myRequest = store.myRequest(trip);
    final others = [
      for (final r in trip.requests)
        if (r.requesterId != store.meId) store.memberById(r.requesterId),
    ];
    final prompt = store.promptForMe;
    final settlement = store.settlementFor(trip.id, store.meId);

    return [
      if (prompt != null && prompt.tripId == trip.id) ...[
        const SizedBox(height: 16),
        Notice(
          '${shopper.firstName} is asking about ${prompt.originalName.toLowerCase()}',
          kind: NoticeKind.attention,
          icon: CupertinoIcons.bubble_left_fill,
          action: 'Answer',
          onAction: () => showSubstitutionChoiceSheet(context, prompt.id),
        ),
      ],
      if (trip.status == TripStatus.shopping) ...[
        const SizedBox(height: 16),
        Notice(
          '${shopper.firstName} is shopping now. You’ll hear if something’s out.',
        ),
      ],
      if (trip.status == TripStatus.settling && settlement != null) ...[
        const SizedBox(height: 16),
        Notice(
          settlement.paid
              ? 'Paid. Thanks for closing the loop.'
              : 'You owe ${shopper.firstName} ${money(settlement.total)}',
          kind: settlement.paid ? NoticeKind.success : NoticeKind.info,
          icon: settlement.paid ? null : CupertinoIcons.creditcard,
        ),
      ],
      if (trip.status == TripStatus.done) ...[
        const SizedBox(height: 16),
        const Notice(
          'Delivered. Thanks for using the trip.',
          kind: NoticeKind.success,
        ),
      ],
      if (myRequest == null && trip.status == TripStatus.open) ...[
        const SizedBox(height: 24),
        EmptyState(
          icon: CupertinoIcons.doc_text,
          title: 'Add your list',
          body:
              'Type it, say it, or snap a photo. '
              '${shopper.firstName} ${leavesLabel(trip.departAt).toLowerCase()}.',
        ),
      ] else if (myRequest != null) ...[
        SectionHeader(
          'Your list',
          action: trip.status == TripStatus.open ? 'Edit' : null,
          onAction: () => push(context, AddListScreen(tripId: trip.id)),
        ),
        Panel(
          children: [
            for (final item in myRequest.items)
              _MyItemRow(item: item, trip: trip),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '${plural(myRequest.items.length, 'item')} · up to ${moneyShort(myRequest.cappedTotal)}',
          style: FType.caption.copyWith(color: FColors.inkSecondary),
        ),
      ],
      if (others.isNotEmpty) ...[
        const SectionHeader('Also on this trip'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final m in others) MemberChip(m)],
        ),
      ],
    ];
  }

  Widget? _requesterAction(
    BuildContext context,
    DemoStore store,
    Trip trip,
    Member shopper,
  ) {
    final myRequest = store.myRequest(trip);
    final settlement = store.settlementFor(trip.id, store.meId);
    if (trip.status == TripStatus.open && myRequest == null) {
      return FButton(
        label: 'Add my list',
        onPressed: () => push(context, AddListScreen(tripId: trip.id)),
      );
    }
    if (trip.status != TripStatus.open &&
        settlement != null &&
        !settlement.paid) {
      return FButton(
        label: 'Pay ${money(settlement.total)}',
        onPressed: () => push(context, SettlementScreen(tripId: trip.id)),
      );
    }
    if (settlement != null && settlement.paid) {
      return FButton(
        label: 'See your share',
        kind: FButtonKind.secondary,
        onPressed: () => push(context, SettlementScreen(tripId: trip.id)),
      );
    }
    return null;
  }
}

class _CapsLine extends StatelessWidget {
  const _CapsLine({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final caps = trip.caps;
    return Row(
      children: [
        const Icon(
          CupertinoIcons.person_2,
          size: 15,
          color: FColors.inkSecondary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Up to ${caps.maxRequesters} neighbors · '
            '${plural(caps.maxItemsPerPerson, 'item')} and '
            '${moneyShort(caps.maxDollarsPerPerson)} each',
            style: FType.bodySmall.copyWith(color: FColors.inkSecondary),
          ),
        ),
      ],
    );
  }
}

class _MyItemRow extends StatelessWidget {
  const _MyItemRow({required this.item, required this.trip});

  final TripItem item;
  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final showStatus = trip.status != TripStatus.open;
    final (String? statusLabel, PillKind kind) = switch (item.status) {
      ItemStatus.pending => (null, PillKind.neutral),
      ItemStatus.got => ('Got it', PillKind.success),
      ItemStatus.substituted => ('Swapped', PillKind.info),
      ItemStatus.skipped => ('Skipped', PillKind.neutral),
    };
    final subtitle = item.status == ItemStatus.substituted
        ? 'Now ${item.substituteName}'
        : item.note;
    return PanelRow(
      title: item.qty > 1 ? '${item.name} · ${item.qtyLabel}' : item.name,
      subtitle: subtitle,
      value: item.maxPrice == null ? null : moneyShort(item.maxPrice!),
      trailing: showStatus && statusLabel != null
          ? StatusPill(statusLabel, kind: kind)
          : null,
    );
  }
}
