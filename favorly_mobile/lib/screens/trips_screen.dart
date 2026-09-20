import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../state/demo_store.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../util/nav.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/page.dart';
import '../widgets/people.dart';
import '../widgets/surfaces.dart';
import '../widgets/trip_hero.dart';
import 'add_list_screen.dart';
import 'post_trip_screen.dart';
import 'settlement_screen.dart';
import 'shopping_screen.dart';
import 'trip_detail_screen.dart';

class TripsScreen extends ConsumerWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    final me = store.me;
    final active = store.activeTrip;
    final upcoming = store.upcomingTrips;
    final recent = store.recentTrips;

    return FavorlyPage(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Row(
          children: [
            const _CircleTag(label: DemoStore.circleName),
            const Spacer(),
            Pressable(
              label: 'Your profile',
              onTap: () => ref.read(tabProvider.notifier).state = 2,
              child: Avatar(me, size: 36),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Text('${greeting(DateTime.now())}, ${me.firstName}', style: FType.title),
        const SizedBox(height: 20),
        if (active == null)
          const EmptyState(
            icon: CupertinoIcons.cart,
            title: 'No trips yet',
            body: 'Heading to a store? Post the trip and neighbors can add a few items.',
          )
        else
          _ActiveTrip(trip: active),
        if (upcoming.isNotEmpty) ...[
          const SectionHeader('Coming up'),
          Panel(
            dividerIndent: 68,
            children: [for (final t in upcoming) _TripRow(trip: t)],
          ),
        ],
        if (recent.isNotEmpty) ...[
          const SectionHeader('Recent'),
          Panel(
            dividerIndent: 68,
            children: [for (final t in recent) _TripRow(trip: t)],
          ),
        ],
      ],
      bottom: FButton(
        label: 'Post a trip',
        icon: CupertinoIcons.plus,
        onPressed: () => push(context, const PostTripScreen()),
      ),
    );
  }
}

class _CircleTag extends StatelessWidget {
  const _CircleTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
      decoration: BoxDecoration(
        color: FColors.surface,
        borderRadius: BorderRadius.circular(FRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(CupertinoIcons.person_2, size: 16, color: FColors.inkSecondary),
          const SizedBox(width: 6),
          Text(label, style: FType.captionStrong),
        ],
      ),
    );
  }
}

class _ActiveTrip extends ConsumerWidget {
  const _ActiveTrip({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    final shopper = store.memberById(trip.shopperId);
    final mine = store.isShopper(trip);
    final myRequest = store.myRequest(trip);
    final settlement = store.settlementFor(trip.id, store.meId);

    void openDetail() =>
        push(context, TripDetailScreen(tripId: trip.id), name: 'trip/${trip.id}');

    final (String label, VoidCallback go) = switch (trip.status) {
      TripStatus.open when mine => (
          trip.requests.isEmpty
              ? 'Open trip'
              : 'Review ${plural(trip.requests.length, 'list')}',
          openDetail,
        ),
      TripStatus.open => myRequest == null
          ? ('Add my list', () => push(context, AddListScreen(tripId: trip.id)))
          : ('See my list', openDetail),
      TripStatus.shopping when mine => (
          'Continue shopping',
          () => push(context, ShoppingScreen(tripId: trip.id)),
        ),
      TripStatus.shopping => ('Track trip', openDetail),
      TripStatus.settling when mine => ('Finish up', openDetail),
      TripStatus.settling when settlement != null && !settlement.paid => (
          'Pay ${money(settlement.total)}',
          () => push(context, SettlementScreen(tripId: trip.id)),
        ),
      TripStatus.settling => ('See trip', openDetail),
      TripStatus.done => ('See trip', openDetail),
    };

    final badge = switch (trip.status) {
      TripStatus.open => '${store.spotsLeft(trip)} of ${trip.caps.maxRequesters} spots',
      _ => plural(trip.items.length, 'item'),
    };

    return TripHero(
      trip: trip,
      shopper: shopper,
      isMine: mine,
      badge: badge,
      onTap: openDetail,
      action: FButton(label: label, kind: FButtonKind.onAccent, onPressed: go),
    );
  }
}

class _TripRow extends ConsumerWidget {
  const _TripRow({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    final shopper = store.memberById(trip.shopperId);
    final done = trip.status == TripStatus.done;
    final who = store.isShopper(trip) ? 'you' : shopper.firstName;
    final subtitle = done
        ? '${dayLabel(trip.departAt)} · ${plural(trip.requesterCount, 'neighbor')} · $who'
        : '${whenLabel(trip.departAt)} · $who';
    return PanelRow(
      leading: const LeadingIcon(CupertinoIcons.cart, size: 40),
      title: trip.store,
      subtitle: subtitle,
      trailing: done ? const StatusPill('Done', kind: PillKind.success) : null,
      onTap: () => push(context, TripDetailScreen(tripId: trip.id), name: 'trip/${trip.id}'),
    );
  }
}
