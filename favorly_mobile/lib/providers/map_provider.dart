/// State management for the neighborhood map: layers, filters, selections.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../models/map_models.dart';
import '../models/models.dart';
import '../state/demo_store.dart';

/// Map layer types: what category of entities to display.
enum MapLayer {
  members('People'),
  trips('Trips'),
  favors('Favors'),
  activity('Activity');

  const MapLayer(this.label);
  final String label;
}

/// Map state: active layer, selected entity, visible radius filter.
class MapState {
  const MapState({
    required this.activeLayer,
    required this.visibleEntities,
    this.selectedEntity,
    this.radiusMeters = 2000,
  });

  /// Which layer is currently active (determines what's shown).
  final MapLayer activeLayer;

  /// All entities visible on the map for the active layer.
  final List<MapEntity> visibleEntities;

  /// Currently selected entity (drives the bottom sheet).
  final MapEntity? selectedEntity;

  /// Radius filter for proximity-based layers (members, trips).
  final int radiusMeters;

  MapState copyWith({
    MapLayer? activeLayer,
    List<MapEntity>? visibleEntities,
    MapEntity? selectedEntity,
    int? radiusMeters,
  }) {
    return MapState(
      activeLayer: activeLayer ?? this.activeLayer,
      visibleEntities: visibleEntities ?? this.visibleEntities,
      selectedEntity: selectedEntity ?? this.selectedEntity,
      radiusMeters: radiusMeters ?? this.radiusMeters,
    );
  }
}

/// Manages map state: layer selection, entity visibility, filtering.
class MapNotifier extends StateNotifier<MapState> {
  MapNotifier(this._demoStore) : super(_initialState(_demoStore));

  final DemoStore _demoStore;

  static MapState _initialState(DemoStore demoStore) {
    final trips = demoStore.trips;
    final tripEntities = trips
        .map(
          (trip) => TripPin(
            trip: trip,
            position:
                demoStore.storeCoordinates(trip.store) ??
                const LatLng(42.3601, -71.0589), // Fallback to Boston center
            spotsLeft:
                trip.caps.maxRequesters -
                trip.requests.where((r) => r.taking).length,
          ),
        )
        .toList();

    return MapState(
      activeLayer: MapLayer.trips,
      visibleEntities: tripEntities,
      selectedEntity: null,
      radiusMeters: 2000,
    );
  }

  /// Switch to a different layer (members, trips, favors, activity).
  void switchLayer(MapLayer layer) {
    final visibleEntities = _computeEntitiesForLayer(layer);
    state = state.copyWith(
      activeLayer: layer,
      visibleEntities: visibleEntities,
      selectedEntity: null, // Clear selection when switching layers
    );
  }

  /// Select an entity to show in the bottom sheet.
  void selectEntity(MapEntity? entity) {
    state = state.copyWith(selectedEntity: entity);
  }

  /// Update the proximity radius filter.
  void setRadiusFilter(int meters) {
    state = state.copyWith(
      radiusMeters: meters,
      visibleEntities: _computeEntitiesForLayer(state.activeLayer),
    );
  }

  /// Compute visible entities based on the active layer.
  List<MapEntity> _computeEntitiesForLayer(MapLayer layer) {
    switch (layer) {
      case MapLayer.members:
        return _memberEntities();
      case MapLayer.trips:
        return _tripEntities();
      case MapLayer.favors:
        return _favorEntities();
      case MapLayer.activity:
        return []; // Activity layer is handled separately by the heatmap widget
    }
  }

  List<MapEntity> _memberEntities() {
    return _demoStore.members
        .where(
          (member) =>
              member.address?.lat != null && member.address?.lng != null,
        )
        .map(
          (member) => MemberPin(
            member: member,
            position: LatLng(member.address!.lat!, member.address!.lng!),
          ),
        )
        .toList();
  }

  List<MapEntity> _tripEntities() {
    return _demoStore.trips
        .map((trip) {
          final spotsLeft =
              trip.caps.maxRequesters -
              trip.requests.where((r) => r.taking).length;
          return TripPin(
            trip: trip,
            position:
                _demoStore.storeCoordinates(trip.store) ??
                const LatLng(42.3601, -71.0589),
            spotsLeft: spotsLeft,
          );
        })
        .where(
          (pin) => pin.trip.status != TripStatus.done,
        ) // Hide completed trips
        .toList();
  }

  List<MapEntity> _favorEntities() {
    // Phase 3: This will be populated with favor data from Trellis
    return [];
  }
}

/// Provider for map state.
final mapProvider = StateNotifierProvider<MapNotifier, MapState>((ref) {
  final demoStore = ref.watch(storeProvider);
  return MapNotifier(demoStore);
});
