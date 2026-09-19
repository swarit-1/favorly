import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/common.dart';
import 'post_trip_screen.dart';

class TripsScreen extends StatelessWidget {
  const TripsScreen({super.key});

  static String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

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
                onPressed: () {},
                icon: const Icon(Icons.notifications_none_rounded),
                color: AppColors.green,
                tooltip: 'Notifications',
              ),
            ],
          ),
          const SizedBox(height: 4),
          const _CirclePill(label: 'Maple St · Building B'),
          const SizedBox(height: 20),
          Text('${_greeting(DateTime.now())}, Ana', style: text.titleLarge),
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
          const _ActiveTripCard(),
          const SizedBox(height: 22),
          const SectionHeader(title: 'Upcoming trips'),
          const SizedBox(height: 10),
          const _UpcomingTripTile(
            store: 'CVS',
            when: 'Tomorrow · 10:30 AM',
          ),
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
  const _ActiveTripCard();

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
                    Text("Trader Joe's", style: text.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      'Today · leaves at 3:00 PM',
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
            label: 'Ana is going',
            filled: true,
          ),
          const SizedBox(height: 10),
          const _TripMetaRow(
            icon: Icons.groups_rounded,
            label: '2 of 5 spots left',
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
