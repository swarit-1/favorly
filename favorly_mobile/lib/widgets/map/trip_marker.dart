/// Custom marker widget for trips on the neighborhood map.
import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../models/models.dart';

/// A custom marker showing a trip at a store location.
/// Displays store name, spots left, and trip status via color ring.
class TripMarker extends StatelessWidget {
  const TripMarker({
    required this.storeName,
    required this.spotsLeft,
    required this.status,
    super.key,
  });

  final String storeName;
  final int spotsLeft;
  final TripStatus status;

  /// Color ring based on trip status.
  Color _statusColor() {
    return switch (status) {
      TripStatus.open => const Color(0xFF4a86e8), // blue
      TripStatus.shopping => const Color(0xFF16a765), // green
      TripStatus.settling => const Color(0xFFffa500), // orange
      TripStatus.done => const Color(0xFF9e9e9e), // gray
    };
  }

  /// Short label for the status.
  String _statusLabel() {
    return switch (status) {
      TripStatus.open => 'Open',
      TripStatus.shopping => 'Shopping',
      TripStatus.settling => 'Settling',
      TripStatus.done => 'Done',
    };
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor();
    final shortStore = storeName
        .split(' ')
        .first; // "Whole Foods Cambridge" → "Whole"

    return Tooltip(
      message: '$storeName · ${_statusLabel()} · $spotsLeft spots',
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: statusColor, width: 3),
          color: const Color(0xFFfafafa),
          boxShadow: [
            BoxShadow(
              color: statusColor.withOpacity(0.2),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Store icon (shopping cart)
            Center(child: Text('🛒', style: FType.body.copyWith(fontSize: 24))),

            // Spots-left badge (top right)
            if (spotsLeft > 0)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    spotsLeft.toString(),
                    style: FType.caption.copyWith(
                      color: const Color(0xFFfafafa),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              )
            else
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF9e9e9e),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '✓',
                    style: FType.caption.copyWith(
                      color: const Color(0xFFfafafa),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
