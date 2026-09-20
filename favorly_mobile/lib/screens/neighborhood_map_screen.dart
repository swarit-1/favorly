import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/map_models.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/location_provider.dart';
import '../providers/map_provider.dart';
import '../state/demo_store.dart';
import '../theme/tokens.dart';
import '../widgets/chips.dart';
import '../widgets/map/favor_marker.dart';
import '../widgets/map/map_bottom_sheet.dart';
import '../widgets/map/trip_marker.dart';

class NeighborhoodMapScreen extends ConsumerStatefulWidget {
  const NeighborhoodMapScreen({super.key});

  @override
  ConsumerState<NeighborhoodMapScreen> createState() =>
      _NeighborhoodMapScreenState();
}

class _NeighborhoodMapScreenState extends ConsumerState<NeighborhoodMapScreen> {
  late final MapController _mapController = MapController();
  LatLng? _myLocation;
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
        // Request permission and subscribe to live locations
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

  /// Build a marker widget for a map entity.
  Widget _buildMarkerChild(MapEntity entity) {
    return switch (entity) {
      MemberPin() => _buildMemberMarker(entity),
      TripPin() => _buildTripMarker(entity),
      FavorPin() => _buildFavorMarker(entity),
    };
  }

  Widget _buildMemberMarker(MemberPin pin) {
    final member = pin.member;
    return GestureDetector(
      onTap: () {
        ref.read(mapProvider.notifier).selectEntity(pin);
        showModalBottomSheet(
          context: context,
          builder: (_) => MapBottomSheet(entity: pin),
          isScrollControlled: true,
        );
      },
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4),
          ],
        ),
        child: CircleAvatar(
          backgroundColor: tintBgColor(member.tint),
          child: Text(
            member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
            style: FType.body.copyWith(color: tintFgColor(member.tint)),
          ),
        ),
      ),
    );
  }

  Widget _buildTripMarker(TripPin pin) {
    return GestureDetector(
      onTap: () {
        ref.read(mapProvider.notifier).selectEntity(pin);
        showModalBottomSheet(
          context: context,
          builder: (_) => MapBottomSheet(entity: pin),
          isScrollControlled: true,
        );
      },
      child: TripMarker(
        storeName: pin.trip.store,
        spotsLeft: pin.spotsLeft,
        status: pin.trip.status,
      ),
    );
  }

  Widget _buildFavorMarker(FavorPin pin) {
    return GestureDetector(
      onTap: () {
        ref.read(mapProvider.notifier).selectEntity(pin);
        showModalBottomSheet(
          context: context,
          builder: (_) => MapBottomSheet(entity: pin),
          isScrollControlled: true,
        );
      },
      child: FavorMarker(
        title: pin.title,
        requesterName: pin.requesterName,
        category: pin.category,
        effortLevel: pin.effortLevel,
        isInvited: pin.isInvited,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mapState = ref.watch(mapProvider);
    final store = ref.watch(storeProvider);

    // Build entity markers from the current layer
    final entityMarkers = mapState.visibleEntities.map((entity) {
      return Marker(
        point: entity.position,
        width: 56,
        height: 56,
        child: _buildMarkerChild(entity),
      );
    }).toList();

    // Add self marker
    if (_myLocation != null) {
      entityMarkers.insert(
        0,
        Marker(
          point: _myLocation!,
          width: 50,
          height: 50,
          child: Container(
            decoration: BoxDecoration(
              color: FColors.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: FColors.blue.withOpacity(0.3),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              CupertinoIcons.location_solid,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Neighborhood'),
        centerTitle: false,
        elevation: 0,
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
              MarkerLayer(markers: entityMarkers),
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
          // Layer filter chips
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final layer in MapLayer.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SelectChip(
                        label: layer.label,
                        selected: mapState.activeLayer == layer,
                        onTap: () {
                          ref.read(mapProvider.notifier).switchLayer(layer);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _centerOnUser,
        tooltip: 'Center on my location',
        child: const Icon(CupertinoIcons.location),
      ),
    );
  }
}
