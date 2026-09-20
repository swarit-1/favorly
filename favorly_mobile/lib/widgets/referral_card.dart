import 'package:flutter/cupertino.dart';

import '../models/referrals_models.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';

/// Card showing user's invite code and referral stats.
class ReferralCard extends StatelessWidget {
  const ReferralCard({
    required this.stats,
    required this.onCopyCode,
    super.key,
  });

  final ReferralStats stats;
  final VoidCallback onCopyCode;

  @override
  Widget build(BuildContext context) {
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
            'Invite a neighbor',
            style: FType.eyebrow.copyWith(
              color: const Color(0xFF4db87a),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Share your code. When they complete their first favor, you earn karma.',
            style: FType.body.copyWith(color: FColors.canvas),
          ),
          const SizedBox(height: 16),
          // Invite code box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0d2f1f),
              borderRadius: BorderRadius.circular(FRadius.sm),
              border: Border.all(color: const Color(0xFF2d6b52), width: 1),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    stats.inviteCode,
                    style: FType.money.copyWith(
                      color: const Color(0xFF4db87a),
                      letterSpacing: 2,
                    ),
                  ),
                ),
                FTextButton(
                  'Copy',
                  icon: CupertinoIcons.doc_on_doc,
                  onPressed: onCopyCode,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Stats
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${stats.totalReferred}',
                    style: FType.title.copyWith(color: const Color(0xFF4db87a)),
                  ),
                  Text(
                    'invited',
                    style: FType.caption.copyWith(color: FColors.inkSecondary),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '+${stats.totalKarmaEarned}',
                    style: FType.title.copyWith(color: const Color(0xFF4db87a)),
                  ),
                  Text(
                    'karma earned',
                    style: FType.caption.copyWith(color: FColors.inkSecondary),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Expanded view of individual referral rewards.
class ReferralRewardTile extends StatelessWidget {
  const ReferralRewardTile({
    required this.reward,
    required this.referreeName,
    super.key,
  });

  final ReferralReward reward;
  final String referreeName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FSpace.md),
      decoration: BoxDecoration(
        color: const Color(0xFF1f3f2a),
        borderRadius: BorderRadius.circular(FRadius.md),
        border: Border.all(color: const Color(0xFF2d6b52), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$referreeName completed their first favor',
                style: FType.body.copyWith(color: FColors.canvas),
              ),
              Text(
                '+${reward.karmaEarned}',
                style: FType.body.copyWith(
                  color: const Color(0xFF4db87a),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Earned ${reward.earnedAt.toString().split('.')[0]}',
            style: FType.caption.copyWith(color: FColors.inkSecondary),
          ),
        ],
      ),
    );
  }
}
