/// Map entity types: unified marker handling for the neighborhood map.
import 'package:flutter/cupertino.dart';
import 'package:latlong2/latlong.dart';

import 'models.dart';

/// Map tint colors to background color.
Color tintBgColor(MemberTint tint) {
  return switch (tint) {
    MemberTint.blue => const Color(0xFF4a86e8),
    MemberTint.green => const Color(0xFF16a765),
    MemberTint.amber => const Color(0xFFffa500),
    MemberTint.plum => const Color(0xFF6B4A99),
  };
}

/// Map tint colors to foreground color.
Color tintFgColor(MemberTint tint) {
  return switch (tint) {
    MemberTint.blue => const Color(0xFFfafafa),
    MemberTint.green => const Color(0xFFfafafa),
    MemberTint.amber => const Color(0xFFfafafa),
    MemberTint.plum => const Color(0xFFfafafa),
  };
}

/// Base class for all entities that appear on the map.
sealed class MapEntity {
  const MapEntity();

  /// The geographic position of this entity.
  LatLng get position;

  /// Unique identifier for this entity (used for selection, tap handling).
  String get id;

  /// Human-readable label for the entity (for debugging, bottom sheet context).
  String get label;
}

/// A member of the circle, shown at their current location or home address.
final class MemberPin extends MapEntity {
  const MemberPin({required this.member, required this.position});

  final Member member;

  @override
  final LatLng position;

  @override
  String get id => member.id;

  @override
  String get label => member.name;
}

/// An open or active trip, shown at the store location.
final class TripPin extends MapEntity {
  const TripPin({
    required this.trip,
    required this.position,
    required this.spotsLeft,
  });

  final Trip trip;
  final int spotsLeft; // Capacity - accepted requesters

  @override
  final LatLng position;

  @override
  String get id => trip.id;

  @override
  String get label => trip.store;
}

/// An open favor/ask from Trellis, shown at the requester's address.
final class FavorPin extends MapEntity {
  const FavorPin({
    required this.favorId,
    required this.title,
    required this.requesterName,
    required this.position,
    required this.category,
    required this.effortLevel,
    this.isInvited = false,
  });

  final String favorId;
  final String title;
  final String requesterName;
  final String category; // From Trellis FavorCategory
  final String effortLevel; // 'low', 'medium', 'high'
  final bool isInvited;

  @override
  final LatLng position;

  @override
  String get id => favorId;

  @override
  String get label => title;
}
