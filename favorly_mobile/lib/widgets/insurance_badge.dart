import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/insurance_models.dart';
import '../theme/tokens.dart';

/// Insurance status badge: shows when a user has guaranteed-fill coverage.
class InsuranceBadge extends StatelessWidget {
  const InsuranceBadge({
    required this.status,
    super.key,
  });

  final InsuranceStatus status;

  @override
  Widget build(BuildContext context) {
    if (!status.active) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF2d5f3f), // Deep green
        borderRadius: BorderRadius.circular(FRadius.md),
        border: Border.all(
          color: const Color(0xFF4db87a),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            CupertinoIcons.shield_fill,
            color: Color(0xFF4db87a),
            size: 14,
          ),
          const SizedBox(width: 6),
          Text(
            'Guaranteed by Favorly',
            style: FType.caption.copyWith(
              color: const Color(0xFF4db87a),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Mini insurance status indicator: shows trips carried and eligibility progress.
class InsuranceStatusIndicator extends StatelessWidget {
  const InsuranceStatusIndicator({
    required this.status,
    super.key,
  });

  final InsuranceStatus status;

  @override
  Widget build(BuildContext context) {
    final progress =
        status.tripsCarriedThisMonth / status.guaranteedThreshold;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Insurance Progress',
              style: FType.body.copyWith(color: FColors.canvas),
            ),
            Text(
              '${status.tripsCarriedThisMonth}/${status.guaranteedThreshold}',
              style: FType.caption.copyWith(color: FColors.inkSecondary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(FRadius.sm),
          child: SizedBox(
            height: 6,
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: const Color(0xFF2a3f36),
              valueColor: AlwaysStoppedAnimation(
                status.active
                    ? const Color(0xFF4db87a)
                    : const Color(0xFF4dd0ff),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          status.statusMessage,
          style: FType.body.copyWith(
            color: FColors.inkSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
