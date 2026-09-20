import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/people.dart';
import '../widgets/recommendations.dart';
import '../widgets/surfaces.dart';

/// Enhanced request panel showing compatibility score as a trailing badge.
class RequestPanelEnhanced extends StatelessWidget {
  const RequestPanelEnhanced({
    super.key,
    required this.trip,
    required this.request,
    required this.member,
    required this.editable,
    required this.onTaking,
    this.compatibilityScore = 0.0,
    this.tripsWorkedTogether = 0,
  });

  final Trip trip;
  final TripRequest request;
  final Member member;
  final bool editable;
  final ValueChanged<bool> onTaking;
  final double compatibilityScore;
  final int tripsWorkedTogether;

  @override
  Widget build(BuildContext context) {
    final muted = !request.taking;
    return Opacity(
      opacity: muted ? 0.6 : 1,
      child: Panel(
        dividerIndent: 16,
        children: [
          PanelRow(
            leading: Avatar(member, size: 40),
            title: member.name,
            subtitle: muted
                ? 'Not taking this one'
                : '${plural(request.items.length, 'item')} · up to ${moneyShort(request.cappedTotal)}',
            trailing: editable
                ? Semantics(
                    label: 'Taking ${member.firstName} list',
                    child: Switch.adaptive(
                      value: request.taking,
                      activeTrackColor: FColors.blue,
                      onChanged: onTaking,
                    ),
                  )
                : compatibilityScore > 0
                ? CompatibilityBadge(
                    score: compatibilityScore,
                    tripCount: tripsWorkedTogether,
                  )
                : null,
          ),
          for (final item in request.items)
            PanelRow(
              minHeight: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              title: item.qty > 1
                  ? '${item.name} · ${item.qtyLabel}'
                  : item.name,
              titleStyle: FType.bodySmall,
              subtitle: item.note,
              subtitleStyle: FType.caption.copyWith(
                color: FColors.inkSecondary,
              ),
              value: item.maxPrice == null ? null : moneyShort(item.maxPrice!),
            ),
        ],
      ),
    );
  }
}
