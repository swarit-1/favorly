import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/favors_provider.dart';
import '../state/demo_store.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../util/nav.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/error_panel.dart';
import '../widgets/favor_card.dart';
import '../widgets/page.dart';
import '../widgets/surfaces.dart';
import '../widgets/trip_hero.dart';
import 'add_list_screen.dart';
import 'favor_detail_screen.dart';
import 'post_trip_screen.dart';
import 'settlement_screen.dart';
import 'shopping_screen.dart';
import 'trip_detail_screen.dart';

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

    return FavorlyPage(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Row(
          children: [
            const _CircleTag(label: 'Your Circle'),
            const Spacer(),
            Pressable(
              label: 'Your profile',
              onTap: () => ref.read(tabProvider.notifier).state = 2,
              child: const Icon(CupertinoIcons.person_circle, size: 36),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Text('${greeting(DateTime.now())}, $firstName', style: FType.title),
        const SizedBox(height: 20),
        if (active == null)
          const EmptyState(
            icon: CupertinoIcons.cart,
            title: 'No trips yet',
            body: 'Heading to a store? Post the trip and neighbors can add a few items.',
          )
        else
          _ActiveTrip(trip: active),
        const _RecommendedFavors(),
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

/// Favors the agent service thinks this person should consider doing.
///
/// Cached, so opening the app shows the last list immediately and refreshes
/// behind it — a recommendation call goes through an LLM and is too slow to
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SectionHeader('Favors for you'),
            const Spacer(),
            if (state.isRefreshing)
              const CupertinoActivityIndicator(radius: 8)
            else
              Pressable(
                label: 'Refresh favors',
                onTap: () => ref
                    .read(favorsProvider.notifier)
                    .load(userId, force: true),
                child: const Icon(CupertinoIcons.refresh,
                    size: 18, color: FColors.inkSecondary),
              ),
          ],
        ),
        if (state.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: FSpace.xl),
            child: Center(child: CupertinoActivityIndicator()),
          )
        else if (state.favors.isEmpty)
          const EmptyState(
            icon: CupertinoIcons.hand_thumbsup,
            title: 'Nothing to pick up yet',
            body: 'When a neighbor posts something they need, the ones worth '
                'your while show up here.',
          )
        else
          Panel(
            dividerIndent: 68,
            children: [
              for (final favor in state.favors)
                FavorCard(
                  favor: favor,
                  started: state.startedNeedIds.contains(favor.needId),
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
