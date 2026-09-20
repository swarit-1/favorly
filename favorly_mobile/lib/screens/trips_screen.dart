import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/favors_provider.dart';
import '../services/trellis_client.dart';
import '../state/demo_store.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../util/nav.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/error_panel.dart';
import '../widgets/favor_card.dart';
import '../widgets/favor_hero.dart';
import '../widgets/page.dart';
import '../widgets/surfaces.dart';
import '../widgets/trip_hero.dart';
import 'add_list_screen.dart';
import 'favor_detail_screen.dart';
import 'favor_finish_sheet.dart';
import 'post_trip_screen.dart';
import 'settlement_screen.dart';
import 'shopping_screen.dart';
import 'trip_detail_screen.dart';

/// Home: who needs you, and who you are already helping.
///
/// The screen reads top to bottom as one sentence about people. A greeting, at
/// most one saturated card for the thing in flight, then the neighbors you
/// could show up for. Trips are the machinery underneath that, so they sit at
/// the bottom as a quiet list rather than competing for the same surface.
class TripsScreen extends ConsumerWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final store = ref.watch(storeProvider);

    // Use auth data if available, fall back to demo store
    final userName = authState.name ?? store.me.name;
    final firstName = userName.split(' ').first;
    final active = store.activeTrip;
    final recent = store.recentTrips;

    // The one favor you are on owns the blue box. It is the only thing in the
    // app someone is waiting on you for, so nothing outranks it, not even a
    // trip you are running yourself.
    final myFavor = ref.watch(favorsProvider.select((s) => s.active));
    final startedAt =
        ref.watch(favorsProvider.select((s) => s.activeStartedAt));
    final waitingCount = ref.watch(favorsProvider.select((s) => s.favors.length));

    // The trip only shows up in the list when the favor has taken the hero;
    // otherwise it is already the blue box and printing it twice says nothing.
    final tripRows = [
      if (myFavor != null && active != null) active,
      ...recent.take(3),
    ];

    return FavorlyPage(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text('${greeting(DateTime.now())}, $firstName', style: FType.title),
        // One quiet line, and only when it tells you something you cannot see
        // yet: how many people are waiting further down.
        if (myFavor == null && waitingCount > 0) ...[
          const SizedBox(height: 6),
          Text(
            '${plural(waitingCount, 'neighbor')} nearby could use a hand.',
            style: FType.body.copyWith(color: FColors.inkSecondary),
          ),
        ],
        const SizedBox(height: FSpace.xxl),
        if (myFavor != null)
          _ActiveFavor(favor: myFavor, startedAt: startedAt)
        else if (active != null)
          _ActiveTrip(trip: active)
        else
          const EmptyState(
            icon: CupertinoIcons.person_2,
            title: 'Nobody waiting on you',
            body: 'Take on one favor at a time. Whoever you are helping shows '
                'up here with everything you need to finish it.',
          ),
        const _RecommendedFavors(),
        if (tripRows.isNotEmpty) ...[
          const SectionHeader('Trips'),
          Panel(
            dividerIndent: 68,
            children: [for (final t in tripRows) _TripRow(trip: t)],
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

/// The favor you are on, in the blue box: who you are helping, what they
/// asked for, and the one way to close it out.
class _ActiveFavor extends StatelessWidget {
  const _ActiveFavor({required this.favor, this.startedAt});

  final FavorSuggestion favor;
  final DateTime? startedAt;

  @override
  Widget build(BuildContext context) {
    final name = favor.requesterName.isEmpty
        ? 'them'
        : favor.requesterName.split(' ').first;

    return FavorHero(
      favor: favor,
      startedAt: startedAt,
      onTap: () => push(context, FavorDetailScreen(favor: favor)),
      action: FButton(
        label: 'Wrap up with $name',
        kind: FButtonKind.onAccent,
        icon: CupertinoIcons.checkmark_alt,
        onPressed: () => showFavorFinishSheet(context, favor: favor),
      ),
    );
  }
}

/// Neighbors the agent thinks you are well placed to help.
///
/// Cached, so opening the app shows the last list immediately and refreshes
/// behind it: a recommendation call goes through an LLM and is too slow to
/// block the home screen on.
class _RecommendedFavors extends ConsumerStatefulWidget {
  const _RecommendedFavors();

  @override
  ConsumerState<_RecommendedFavors> createState() => _RecommendedFavorsState();
}

class _RecommendedFavorsState extends ConsumerState<_RecommendedFavors> {
  @override
  void initState() {
    super.initState();
    // After the first frame: reading a provider during init is not allowed,
    // and the auth state is already settled by the time the home screen builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = ref.read(authProvider).userId;
      if (userId != null) ref.read(favorsProvider.notifier).load(userId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(authProvider).userId;
    final state = ref.watch(favorsProvider);

    if (userId == null) return const SizedBox.shrink();

    final busy = state.hasActive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The header carries the whole frame: who these people are, and the
        // one control that acts on them. What Trellis is and is not belongs on
        // the favor itself, where you are actually deciding.
        //
        // SectionHeader already lays out a title plus an action; wrapping it
        // in another Row leaves its Expanded with unbounded width.
        SectionHeader(
          busy ? 'After this one' : 'Who needs you',
          action: state.isRefreshing ? 'Refreshing...' : 'Refresh',
          onAction: state.isRefreshing
              ? null
              : () =>
                  ref.read(favorsProvider.notifier).load(userId, force: true),
        ),
        if (state.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: FSpace.xl),
            child: Center(child: CupertinoActivityIndicator()),
          )
        else if (state.favors.isEmpty)
          const EmptyState(
            icon: CupertinoIcons.hand_thumbsup,
            title: 'Nobody needs a hand right now',
            body: 'When someone nearby asks, the people you are best placed to '
                'show up for land here.',
          )
        else
          Panel(
            dividerIndent: 74,
            children: [
              for (final favor in state.favors)
                FavorCard(
                  favor: favor,
                  waiting: busy,
                  onTap: () =>
                      push(context, FavorDetailScreen(favor: favor)),
                ),
            ],
          ),
        // A failed refresh keeps the cached list on screen; say so rather than
        // silently showing stale data.
        if (state.error != null) ErrorPanel(state.error),
      ],
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
        ? '${dayLabel(trip.departAt)} · $who'
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
