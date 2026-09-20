/// Custom marker widget for favors on the neighborhood map.
import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// A custom marker showing an open favor/ask at a location.
/// Displays category icon, effort level via border thickness, and requester initials.
class FavorMarker extends StatelessWidget {
  const FavorMarker({
    required this.title,
    required this.requesterName,
    required this.category,
    required this.effortLevel,
    required this.isInvited,
    super.key,
  });

  final String title;
  final String requesterName;
  final String category;
  final String effortLevel; // 'low', 'medium', 'high'
  final bool isInvited;

  /// Category icon emoji.
  String _categoryIcon() {
    return switch (category.toLowerCase()) {
      'errand' => '🛍️',
      'borrow' => '🔑',
      'care' => '❤️',
      'skill' => '🛠️',
      _ => '⭐',
    };
  }

  /// Border thickness based on effort level.
  double _borderWidth() {
    return switch (effortLevel.toLowerCase()) {
      'low' => 1.5,
      'medium' => 2.5,
      'high' => 3.5,
      _ => 2.0,
    };
  }

  /// Color based on effort level.
  Color _effortColor() {
    return switch (effortLevel.toLowerCase()) {
      'low' => const Color(0xFF4db87a), // green
      'medium' => const Color(0xFFffa500), // orange
      'high' => const Color(0xFFfb4c2f), // red
      _ => const Color(0xFF666666), // gray
    };
  }

  /// Get requester initials (first letter of each word).
  String _requesterInitials() {
    final parts = requesterName.split(' ');
    return parts.map((p) => p.isNotEmpty ? p[0] : '').join('').toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final initials = _requesterInitials();
    final effortColor = _effortColor();
    final borderWidth = _borderWidth();

    return Tooltip(
      message: '$title · $requesterName · ${effortLevel.toUpperCase()}',
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: effortColor, width: borderWidth),
          color: effortColor.withOpacity(0.1),
          boxShadow: [
            BoxShadow(
              color: effortColor.withOpacity(0.2),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Category icon (centered)
            Center(
              child: Text(
                _categoryIcon(),
                style: FType.body.copyWith(fontSize: 24),
              ),
            ),

            // Requester initials (bottom right corner)
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: effortColor,
                  border: Border.all(color: const Color(0xFFfafafa), width: 1),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials.length <= 2 ? initials : initials[0],
                  style: FType.caption.copyWith(
                    color: const Color(0xFFfafafa),
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            ),

            // "Invited" eyebrow (top left) if applicable
            if (isInvited)
              Positioned(
                top: 4,
                left: 4,
                child: Text(
                  '✓',
                  style: FType.caption.copyWith(
                    color: const Color(0xFF16a765),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
