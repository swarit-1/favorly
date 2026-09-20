import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import 'people.dart';
import 'surfaces.dart';

/// The app's one saturated surface. It follows a trip through the feed,
/// the detail screen, and shopping, so people always know which trip they
/// are looking at.
class TripHero extends StatelessWidget {
  const TripHero({
    super.key,
    required this.trip,
    required this.shopper,
    required this.isMine,
    this.badge,
    this.action,
    this.onTap,
  });

  final Trip trip;
  final Member shopper;
  final bool isMine;
  final String? badge;
  final Widget? action;
  final VoidCallback? onTap;

  String get _status => switch (trip.status) {
        TripStatus.open => leavesLabel(trip.departAt),
        TripStatus.shopping => 'Shopping now',
        TripStatus.settling => 'Settling up',
        TripStatus.done => 'Delivered',
      };

  @override
  Widget build(BuildContext context) {
    final who = isMine ? 'You’re going' : '${shopper.firstName} is going';
    const white = FColors.onAccent;
    final card = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FRadius.xl),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [FColors.bluePressed, FColors.blue, FColors.blueBright],
          stops: [0, 0.55, 1],
        ),
      ),
      child: Stack(
        children: [
          const Positioned(
            right: -70,
            top: -100,
            child: Orb(size: 230, opacity: 0.12),
          ),
          const Positioned(
            right: 30,
            bottom: -140,
            child: Orb(size: 210, opacity: 0.08),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _status.toUpperCase(),
                            style: FType.eyebrow
                                .copyWith(color: white.withValues(alpha: 0.88)),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            trip.store,
                            style: FType.heading.copyWith(
                              color: white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 12),
                      StatusPill(badge!, onAccent: true),
                    ],
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Avatar(shopper, size: 28, onAccent: true),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        who,
                        style: FType.bodySmallStrong.copyWith(color: white),
                      ),
                    ),
                    Text(
                      whenLabel(trip.departAt),
                      style: FType.captionStrong
                          .copyWith(color: white.withValues(alpha: 0.88)),
                    ),
                  ],
                ),
                if (action != null) ...[const SizedBox(height: 18), action!],
              ],
            ),
          ),
        ],
      ),
    );
    return Pressable(
      onTap: onTap,
      label: onTap == null ? null : '${trip.store} trip, $_status',
      child: card,
    );
  }
}
