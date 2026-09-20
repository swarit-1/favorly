import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/savings_models.dart';
import '../theme/tokens.dart';
import '../util/format.dart';

/// Displays personal savings or earnings on a card.
/// Shows "Fees avoided" for requesters, "Earned" for carriers.
class SavingsMeter extends ConsumerWidget {
  const SavingsMeter({
    required this.savings,
    super.key,
  });

  final PersonalSavings savings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (savings.isEmpty) {
      return const SizedBox.shrink();
    }

    // Prefer carrier view if both, else requester, else nothing
    final carrierView = savings.carrierSavings;
    final requesterView = savings.requesterSavings;

    if (carrierView != null) {
      return _buildCarrierCard(context, carrierView);
    } else if (requesterView != null) {
      return _buildRequesterCard(context, requesterView);
    }

    return const SizedBox.shrink();
  }

  Widget _buildRequesterCard(BuildContext context, RequesterSavings savings) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: FSpace.md, vertical: FSpace.sm),
      padding: const EdgeInsets.all(FSpace.md),
      decoration: BoxDecoration(
        color: FColors.successTint,
        borderRadius: BorderRadius.circular(FRadius.lg),
        border: Border.all(color: FColors.success, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fees avoided this month',
                    style: FType.caption.copyWith(color: FColors.success),
                  ),
                  const SizedBox(height: 4),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: savings.feesAvoidedThisMonth),
                    duration: const Duration(milliseconds: 800),
                    builder: (context, value, child) {
                      return Text(
                        money(value),
                        style: FType.display.copyWith(color: FColors.success),
                      );
                    },
                  ),
                ],
              ),
              Icon(
                CupertinoIcons.arrow_down_circle_fill,
                color: FColors.success,
                size: 40,
              ),
            ],
          ),
          if (savings.tripsUsedThisMonth > 0) ...[
            const SizedBox(height: FSpace.sm),
            Text(
              '${savings.tripsUsedThisMonth} ${plural(savings.tripsUsedThisMonth, 'trip', 'trips')} this month',
              style: FType.caption.copyWith(color: FColors.success),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCarrierCard(BuildContext context, CarrierSavings savings) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: FSpace.md, vertical: FSpace.sm),
      padding: const EdgeInsets.all(FSpace.md),
      decoration: BoxDecoration(
        color: FColors.blueTint,
        borderRadius: BorderRadius.circular(FRadius.lg),
        border: Border.all(color: FColors.blue, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Earned this month',
                    style: FType.caption.copyWith(color: FColors.blue),
                  ),
                  const SizedBox(height: 4),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: savings.totalEarnedThisMonth),
                    duration: const Duration(milliseconds: 800),
                    builder: (context, value, child) {
                      return Text(
                        money(value),
                        style: FType.display.copyWith(color: FColors.blue),
                      );
                    },
                  ),
                ],
              ),
              Icon(
                CupertinoIcons.arrow_up_circle_fill,
                color: FColors.blue,
                size: 40,
              ),
            ],
          ),
          const SizedBox(height: FSpace.xs),
          Text(
            '${money(savings.perksEarnedThisMonth)} perks + ${money(savings.bulkSavingsThisMonth)} bulk savings',
            style: FType.caption.copyWith(color: FColors.blue),
          ),
          if (savings.tripsCarriedThisMonth > 0) ...[
            const SizedBox(height: FSpace.xs),
            Text(
              '${savings.tripsCarriedThisMonth} ${plural(savings.tripsCarriedThisMonth, 'trip', 'trips')} carried',
              style: FType.caption.copyWith(color: FColors.blue),
            ),
          ],
        ],
      ),
    );
  }
}
