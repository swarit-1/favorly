import 'package:flutter/material.dart';

import '../api_client.dart';
import '../config.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'post_trip_screen.dart';

class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key, this.apiClient});

  /// Overridable for tests -- pass an ApiClient built on an http.MockClient
  /// instead of hitting a real backend.
  final ApiClient? apiClient;

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  late final ApiClient _api = widget.apiClient ?? ApiClient();
  late Future<List<Trip>> _tripsFuture;

  @override
  void initState() {
    super.initState();
    _tripsFuture = _api.fetchCircleTrips(AppConfig.demoCircleId);
  }

  void _refresh() {
    setState(() => _tripsFuture = _api.fetchCircleTrips(AppConfig.demoCircleId));
  }

  static String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _addMyList(Trip trip) async {
    final itemController = TextEditingController();
    final itemName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add an item'),
        content: TextField(
          controller: itemController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. milk'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, itemController.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (itemName == null || itemName.isEmpty || !mounted) return;

    try {
      final requestId = await _api.attachRequest(
        tripId: trip.id,
        requesterId: AppConfig.currentUserId,
        items: [
          {'name': itemName},
        ],
      );
      // No separate approval UI yet -- auto-accept so the merged list / handoff
      // flow (and the Trellis favor it triggers) is reachable end to end.
      await _api.acceptRequest(requestId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added "$itemName" to ${trip.store}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add item: $e')));
      }
    }
  }

  Future<void> _markDelivered(Trip trip) async {
    try {
      final favorsLogged = await _api.handoffTrip(trip.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Trip complete -- $favorsLogged favor(s) logged')),
        );
        _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Handoff failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: FutureBuilder<List<Trip>>(
        future: _tripsFuture,
        builder: (context, snapshot) {
          final trips = snapshot.data ?? const <Trip>[];
          final active = trips.where((t) => t.isActive).toList();
          final activeTrip = active.isEmpty ? null : active.first;
          final upcoming = active.length > 1 ? active.sublist(1) : const <Trip>[];

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
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
                const SectionHeader(title: 'Active trip'),
                const SizedBox(height: 10),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snapshot.hasError)
                  Text('Could not load trips: ${snapshot.error}', style: text.bodyMedium)
                else if (activeTrip == null)
                  Text('No active trip yet.', style: text.bodyMedium)
                else
                  _ActiveTripCard(
                    trip: activeTrip,
                    onAddMyList: () => _addMyList(activeTrip),
                    onMarkDelivered: () => _markDelivered(activeTrip),
                  ),
                const SizedBox(height: 22),
                const SectionHeader(title: 'Upcoming trips'),
                const SizedBox(height: 10),
                if (upcoming.isEmpty)
                  Text('Nothing else on the books.', style: text.bodyMedium)
                else
                  for (final trip in upcoming) ...[
                    _UpcomingTripTile(trip: trip),
                    const SizedBox(height: 10),
                  ],
                const SizedBox(height: 24),
                PillButton(
                  label: 'Post a trip',
                  background: AppColors.orange,
                  onPressed: () async {
                    final posted = await Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (_) => PostTripScreen(apiClient: widget.apiClient),
                      ),
                    );
                    if (posted == true) _refresh();
                  },
                ),
              ],
            ),
          );
        },
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
  const _ActiveTripCard({
    required this.trip,
    required this.onAddMyList,
    required this.onMarkDelivered,
  });

  final Trip trip;
  final VoidCallback onAddMyList;
  final VoidCallback onMarkDelivered;

  String get _when {
    final t = trip.departAt;
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    return 'Departs at $hour:$minute $ampm';
  }

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
                    Text(_when, style: text.bodyMedium),
                  ],
                ),
              ),
              const IconBadge(icon: Icons.shopping_basket_rounded),
            ],
          ),
          const SizedBox(height: 16),
          _TripMetaRow(
            icon: Icons.groups_rounded,
            label: 'Up to ${trip.caps.maxRequesters} neighbors · \$${trip.caps.maxDollarsPerPerson} each',
          ),
          const SizedBox(height: 18),
          PillButton(label: 'Add my list', onPressed: onAddMyList),
          const SizedBox(height: 10),
          PillButton(
            label: 'Mark delivered',
            background: AppColors.orange,
            onPressed: onMarkDelivered,
          ),
        ],
      ),
    );
  }
}

class _TripMetaRow extends StatelessWidget {
  const _TripMetaRow({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22, color: AppColors.green),
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
      ],
    );
  }
}

class _UpcomingTripTile extends StatelessWidget {
  const _UpcomingTripTile({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final t = trip.departAt;
    final when = '${t.month}/${t.day} · ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

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
                Text(trip.store, style: text.titleMedium),
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
