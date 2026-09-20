import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/location_provider.dart';
import '../state/demo_store.dart';
import '../theme/tokens.dart';
import '../widgets/chips.dart';

class NeighborhoodMapScreen extends ConsumerStatefulWidget {
  const NeighborhoodMapScreen({super.key});

  @override
  ConsumerState<NeighborhoodMapScreen> createState() => _NeighborhoodMapScreenState();
}

class _NeighborhoodMapScreenState extends ConsumerState<NeighborhoodMapScreen> {
  late final MapController _mapController = MapController();
  LatLng? _myLocation;
  String _filter = 'all';
  Member? _selectedMember;
  bool _initialized = false;

  // Cambridge, MA center (Harvard Square)
  static const LatLng _cambridgeCenter = LatLng(42.3736, -71.1190);

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final authState = ref.read(authProvider);
      final store = ref.read(storeProvider);
      if (authState.userId != null && store.me.address?.lat != null) {
        // Request permission and subscribe to live locations (no startSharing)
        final locationNotifier = ref.read(
          locationProvider((authState.userId!, store.me.id)).notifier,
        );
        locationNotifier.requestPermission();
        locationNotifier.subscribe();
      }
    }
  }

  Future<void> _initializeMap() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _myLocation = LatLng(position.latitude, position.longitude);
      });
      if (_myLocation != null) {
        _mapController.move(_myLocation!, 14.0);
      }
    } catch (e) {
      // Use seeded location if GPS unavailable
      final store = ref.read(storeProvider);
      final userAddr = store.me.address;
      if (userAddr?.lat != null && userAddr?.lng != null) {
        setState(() {
          _myLocation = LatLng(userAddr!.lat!, userAddr.lng!);
        });
        _mapController.move(_myLocation!, 14.0);
      } else {
        _mapController.move(_cambridgeCenter, 14.0);
      }
    }
  }

  void _centerOnUser() {
    if (_myLocation != null) {
      _mapController.move(_myLocation!, 15.0);
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  List<Member> _getVisibleMembers() {
    final store = ref.read(storeProvider);
    final me = store.me;

    return store.members.where((m) {
      // Always include self
      if (m.id == me.id) return true;

      // Apply filter
      if (_filter == 'on_trip') {
        // Show members who are shoppers on active trips
        final activeTrip = store.activeTrip;
        return activeTrip != null && activeTrip.shopperId == m.id;
      } else if (_filter == 'nearby') {
        // Show members within 500m (500000 meters) - wait, that's wrong, let me fix it
        // 500m = 500 meters
        final dist = store.distanceBetween(me, m);
        return dist != null && dist <= 500;
      }
      // 'all' filter
      return true;
    }).toList();
  }

  String? _getMemberDistance(Member m) {
    final store = ref.read(storeProvider);
    final me = store.me;
    final dist = store.distanceBetween(me, m);
    if (dist == null) return null;
    if (dist < 1000) {
      return '~${dist.toStringAsFixed(0).replaceAll(RegExp(r'\.0+$'), '')}m';
    }
    return '~${(dist / 1000).toStringAsFixed(1)}km';
  }

  String? _getMemberTripStatus(Member m) {
    final store = ref.read(storeProvider);
    for (final trip in store.trips) {
      if (trip.shopperId == m.id && trip.isLive) {
        return '${trip.status.name} at ${trip.store}';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final visibleMembers = _getVisibleMembers();

    // Determine marker positions: use live Supabase data if available, otherwise use seeded address
    final memberMarkers = visibleMembers.where((m) => m.id != store.me.id).map((m) {
      final lat = m.address?.lat;
      final lng = m.address?.lng;
      if (lat == null || lng == null) return null;
      return Marker(
        point: LatLng(lat, lng),
        width: 50,
        height: 50,
        child: GestureDetector(
          onTap: () => setState(() => _selectedMember = m),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _selectedMember?.id == m.id ? FColors.blue : Colors.white,
                width: _selectedMember?.id == m.id ? 3 : 2,
              ),
            ),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: _tintToColor(m.tint),
              child: Text(
                m.firstName.isNotEmpty ? m.firstName[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      );
    }).whereType<Marker>().toList();

    // Add self marker
    if (_myLocation != null) {
      memberMarkers.insert(
        0,
        Marker(
          point: _myLocation!,
          width: 50,
          height: 50,
          child: Container(
            decoration: BoxDecoration(
              color: FColors.blue,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.person,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Neighborhood Map'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _myLocation ?? _cambridgeCenter,
              initialZoom: 14.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.favorly.app',
              ),
              MarkerLayer(markers: memberMarkers),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    '© OpenStreetMap contributors',
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),
          // Filter chips
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  SelectChip(
                    label: 'All',
                    selected: _filter == 'all',
                    onTap: () => setState(() {
                      _filter = 'all';
                      _selectedMember = null;
                    }),
                  ),
                  const SizedBox(width: 8),
                  SelectChip(
                    label: 'On Trip',
                    selected: _filter == 'on_trip',
                    onTap: () => setState(() {
                      _filter = 'on_trip';
                      _selectedMember = null;
                    }),
                  ),
                  const SizedBox(width: 8),
                  SelectChip(
                    label: 'Nearby (<500m)',
                    selected: _filter == 'nearby',
                    onTap: () => setState(() {
                      _filter = 'nearby';
                      _selectedMember = null;
                    }),
                  ),
                ],
              ),
            ),
          ),
          // Member detail popup
          if (_selectedMember != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _MemberCard(
                member: _selectedMember!,
                distance: _getMemberDistance(_selectedMember!),
                tripStatus: _getMemberTripStatus(_selectedMember!),
                onClose: () => setState(() => _selectedMember = null),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _centerOnUser,
        tooltip: 'Center on my location',
        child: const Icon(Icons.my_location),
      ),
    );
  }

  Color _tintToColor(MemberTint tint) {
    return switch (tint) {
      MemberTint.blue => const Color(0xFF4A90E2),
      MemberTint.green => const Color(0xFF2ACE49),
      MemberTint.amber => const Color(0xFFFFA500),
      MemberTint.plum => const Color(0xFF9B59B6),
    };
  }
}

class _MemberCard extends StatelessWidget {
  final Member member;
  final String? distance;
  final String? tripStatus;
  final VoidCallback onClose;

  const _MemberCard({
    required this.member,
    required this.distance,
    required this.tripStatus,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: FColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: const Color(0xFF4A90E2),
                    child: Text(
                      member.firstName.isNotEmpty ? member.firstName[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.name,
                          style: FType.bodyStrong,
                        ),
                        if (distance != null)
                          Text(
                            distance!,
                            style: FType.caption.copyWith(color: FColors.inkSecondary),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(CupertinoIcons.xmark),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (member.bio != null) ...[
                Text(
                  member.bio!,
                  style: FType.bodySmall,
                ),
                const SizedBox(height: 12),
              ],
              if (tripStatus != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: FColors.blueTint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tripStatus!,
                    style: FType.captionStrong.copyWith(color: FColors.blue),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
