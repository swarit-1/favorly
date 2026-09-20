import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/unlocks_models.dart';
import '../theme/tokens.dart';

/// Building-wide milestone progress: shows path to next unlock.
class UnlockProgressWidget extends StatelessWidget {
  const UnlockProgressWidget({
    required this.status,
    super.key,
  });

  final CircleUnlockStatus status;

  @override
  Widget build(BuildContext context) {
    if (status.nextMilestoneThreshold == null) {
      // All milestones unlocked
      return _AllUnlockedCard();
    }

    final progress = status.favorsThisMonth / status.nextMilestoneThreshold!;

    return Container(
      padding: const EdgeInsets.all(FSpace.md),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1a3a2a), Color(0xFF0d2f1f)],
        ),
        borderRadius: BorderRadius.circular(FRadius.lg),
        border: Border.all(color: const Color(0xFF2d6b52), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Building Milestone',
            style: FType.eyebrow.copyWith(
              color: const Color(0xFF4db87a),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            status.nextMilestoneDescription ?? 'Unlocking next reward...',
            style: FType.title.copyWith(color: FColors.canvas),
          ),
          const SizedBox(height: 12),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(FRadius.sm),
            child: SizedBox(
              height: 8,
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: const Color(0xFF1a3a2a),
                valueColor: const AlwaysStoppedAnimation(
                  Color(0xFF4db87a),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                status.progressLabel,
                style: FType.body.copyWith(color: FColors.canvas),
              ),
              Text(
                '${status.progressPercentage.toStringAsFixed(0)}%',
                style: FType.caption.copyWith(
                  color: const Color(0xFF4db87a),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (status.nextMilestoneFavorsRemaining != null &&
              status.nextMilestoneFavorsRemaining! > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${status.nextMilestoneFavorsRemaining} more favors needed',
              style: FType.caption.copyWith(color: FColors.inkSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Card showing all milestones have been unlocked.
class _AllUnlockedCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FSpace.md),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2a3a1a), Color(0xFF1f2f0d)],
        ),
        borderRadius: BorderRadius.circular(FRadius.lg),
        border: Border.all(color: const Color(0xFF4db87a), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🌟 All Milestones Unlocked',
            style: FType.title.copyWith(color: const Color(0xFF4db87a)),
          ),
          const SizedBox(height: 8),
          Text(
            'Your building has claimed all available rewards this month!',
            style: FType.body.copyWith(color: FColors.canvas),
          ),
        ],
      ),
    );
  }
}

/// Claimed unlock reward card.
class UnlockRewardCard extends StatelessWidget {
  const UnlockRewardCard({
    required this.unlock,
    super.key,
  });

  final CircleUnlock unlock;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FSpace.md),
      decoration: BoxDecoration(
        color: const Color(0xFF1f3f2a),
        borderRadius: BorderRadius.circular(FRadius.md),
        border: Border.all(color: const Color(0xFF2d6b52), width: 1),
      ),
      child: Row(
        children: [
          Text(
            unlock.emoji,
            style: const TextStyle(fontSize: 32),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unlock.rewardDescription,
                  style: FType.body.copyWith(color: FColors.canvas),
                ),
                const SizedBox(height: 4),
                Text(
                  'Unlocked at ${unlock.favorsAtUnlock} favors',
                  style: FType.caption.copyWith(color: FColors.inkSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
