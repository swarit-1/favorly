import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/tokens.dart';
import 'people.dart';

/// Badge showing past collaboration history with a member.
/// Displays compatibility score and trip count if available.
class CompatibilityBadge extends StatelessWidget {
  const CompatibilityBadge({
    super.key,
    required this.score,
    this.tripCount = 0,
  });

  /// Compatibility score from 0.0 to 1.0
  final double score;

  /// How many trips they've worked together
  final int tripCount;

  String _getRating() {
    if (score >= 0.9) return 'Perfect fit';
    if (score >= 0.75) return 'Great match';
    if (score >= 0.5) return 'Good together';
    if (score >= 0.25) return 'OK';
    return 'First time';
  }

  @override
  Widget build(BuildContext context) {
    if (score == 0.0) return const SizedBox.shrink();

    final percentage = (score * 100).toInt();
    final tripText = tripCount == 1 ? '1 trip' : '$tripCount trips';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: FColors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: FColors.blue.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$percentage%',
                style: FType.caption.copyWith(
                  color: FColors.blue,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '• $tripText',
                style: FType.caption.copyWith(color: FColors.inkTertiary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Full recommendation card showing a member they've worked with before.
/// Displays avatar, name, compatibility score, and past trip count.
class RecommendationCard extends StatelessWidget {
  const RecommendationCard({
    super.key,
    required this.member,
    required this.score,
    required this.tripsWorkedTogether,
    this.onTap,
  });

  final Member member;
  final double score;
  final int tripsWorkedTogether;
  final VoidCallback? onTap;

  String _getDescription() {
    if (score >= 0.9) return 'You work great together';
    if (score >= 0.75) return 'Great track record';
    if (score >= 0.5) return 'Good history';
    if (score >= 0.25) return 'Worked together before';
    return 'New teammate';
  }

  @override
  Widget build(BuildContext context) {
    final percentage = (score * 100).toInt();
    final tripText = tripsWorkedTogether == 1
        ? '1 trip together'
        : '$tripsWorkedTogether trips together';
    final description = _getDescription();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: FColors.surfacePressed,
          borderRadius: BorderRadius.circular(FRadius.md),
          border: Border.all(color: FColors.hairline),
        ),
        child: Row(
          children: [
            Avatar(member, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(member.name, style: FType.bodyStrong),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: FType.caption.copyWith(color: FColors.inkTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$percentage%',
                  style: FType.bodyStrong.copyWith(color: FColors.blue),
                ),
                Text(
                  tripText,
                  style: FType.caption.copyWith(color: FColors.inkTertiary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Section showing top recommended partners for a member.
/// Typically used in profile or trip creation screens.
class RecommendedPartnersSection extends StatelessWidget {
  const RecommendedPartnersSection({
    super.key,
    required this.members,
    required this.recommendations,
  });

  /// Map of member ID to compatibility score (0.0-1.0)
  final Map<String, double> recommendations;
  final Map<String, Member> members;

  @override
  Widget build(BuildContext context) {
    if (recommendations.isEmpty) {
      return const SizedBox.shrink();
    }

    // Sort by score descending
    final sorted = recommendations.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Your best partners', style: FType.bodyStrong),
        const SizedBox(height: 8),
        for (final entry in sorted.take(3)) ...[
          if (members.containsKey(entry.key))
            RecommendationCard(
              member: members[entry.key]!,
              score: entry.value,
              tripsWorkedTogether: 1, // Would come from API
            ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
