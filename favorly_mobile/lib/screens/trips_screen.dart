import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/trip_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'post_trip_screen.dart';

class TripsScreen extends ConsumerStatefulWidget {
  const TripsScreen({super.key});

  static String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  ConsumerState<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends ConsumerState<TripsScreen> {
  @override
  void initState() {
    super.initState();
    // Load trips when screen is mounted
    Future.microtask(() {
      final authState = ref.read(authProvider);
      if (authState.circleId != null) {
        ref.read(tripsProvider.notifier).fetchTrips(authState.circleId!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final authState = ref.watch(authProvider);
    final tripsState = ref.watch(tripsProvider);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Favorly',
                style: text.headlineMedium?.copyWith(
                  color: AppColors.green,
                  fontSize: 30,
                  letterSpacing: -1,
                ),
              ),
              IconButton(
                onPressed: () {
                  // Logout
                  ref.read(authProvider.notifier).logout();
                },
                icon: const Icon(Icons.logout_rounded),
                color: AppColors.green,
                tooltip: 'Logout',
              ),
            ],
          ),
          const SizedBox(height: 4),
          const _CirclePill(label: 'Maple St · Building B'),
          const SizedBox(height: 20),
          Text(
            '${TripsScreen._greeting(DateTime.now())}, ${authState.name ?? "Neighbor"}',
            style: text.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            "Neighbors help neighbors. That's Favorly.",
            style: text.bodyMedium,
          ),
          const SizedBox(height: 22),
          SectionHeader(
            title: 'Active trip',
            action: TextButton(
              onPressed: () {},
              style: TextButton.styleFrom(
                foregroundColor: AppColors.green,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'See all',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (tripsState.currentTrip != null)
            _ActiveTripCard(trip: tripsState.currentTrip!)
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cream,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'No active trip',
                style: text.bodyMedium,
              ),
            ),
          const SizedBox(height: 22),
          const SectionHeader(title: 'Upcoming trips'),
          const SizedBox(height: 10),
          if (tripsState.trips.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No upcoming trips',
                style: text.bodyMedium,
              ),
            )
          else
            ...tripsState.trips
                .map((trip) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _UpcomingTripTile(
                        store: trip.store,
                        when: trip.departAt.toString().split('.')[0],
                      ),
                    ))
                .toList(),
          const SizedBox(height: 24),
          PillButton(
            label: 'Post a trip',
            background: AppColors.orange,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PostTripScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CirclePill extends StatelessWidget {
  const _CirclePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF1EEE8),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              const Icon(Icons.groups_rounded, size: 20, color: AppColors.green),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveTripCard extends StatelessWidget {
  const _ActiveTripCard({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.greenTint,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(trip.store, style: text.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      'Departs at ${trip.departAt.toString().split('.')[0]}',
                      style: text.bodyMedium,
                    ),
                  ],
                ),
              ),
              const IconBadge(icon: Icons.shopping_basket_rounded),
            ],
          ),
          const SizedBox(height: 16),
          const _TripMetaRow(
            icon: Icons.person_rounded,
            label: 'Trip open',
            filled: true,
          ),
          const SizedBox(height: 10),
          const _TripMetaRow(
            icon: Icons.groups_rounded,
            label: '6 spots available',
          ),
          const SizedBox(height: 18),
          PillButton(label: 'Add my list', onPressed: () {}),
        ],
      ),
    );
  }
}

class _TripMetaRow extends StatelessWidget {
  const _TripMetaRow({
    required this.icon,
    required this.label,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (filled)
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: AppColors.green,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 14, color: AppColors.greenTint),
          )
        else
          Icon(icon, size: 22, color: AppColors.green),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

class _UpcomingTripTile extends StatelessWidget {
  const _UpcomingTripTile({required this.store, required this.when});

  final String store;
  final String when;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return OutlinedCard(
      onTap: () {},
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          const IconBadge(icon: Icons.storefront_rounded, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(store, style: text.titleMedium),
                const SizedBox(height: 2),
                Text(when, style: text.bodyMedium?.copyWith(fontSize: 14)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.muted),
        ],
      ),
    );
  }
}
