/// Bottom sheet for displaying details about selected map entities.
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/map_models.dart';
import '../../models/models.dart';
import '../../state/demo_store.dart';
import '../../theme/tokens.dart';
import '../buttons.dart';

/// Displays details about a selected map entity (member, trip, or favor).
class MapBottomSheet extends ConsumerWidget {
  const MapBottomSheet({required this.entity, super.key});

  final MapEntity entity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DraggableScrollableSheet(
      initialChildSize: 0.35,
      minChildSize: 0.2,
      maxChildSize: 0.75,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: FColors.canvas,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(FRadius.lg),
              topRight: Radius.circular(FRadius.lg),
            ),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Padding(
              padding: const EdgeInsets.all(FSpace.lg),
              child: _buildContent(context, ref, entity),
            ),
          ),
        );
      },
    );
  }

  /// Build content based on entity type.
  Widget _buildContent(BuildContext context, WidgetRef ref, MapEntity entity) {
    return switch (entity) {
      MemberPin() => _buildMemberContent(context, entity),
      TripPin() => _buildTripContent(context, ref, entity),
      FavorPin() => _buildFavorContent(context, entity),
    };
  }

  /// Build member card content.
  Widget _buildMemberContent(BuildContext context, MemberPin pin) {
    final member = pin.member;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tintBgColor(member.tint),
              ),
              alignment: Alignment.center,
              child: Text(
                member.name[0].toUpperCase(),
                style: FType.title.copyWith(color: tintFgColor(member.tint)),
              ),
            ),
            const SizedBox(width: FSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(member.name, style: FType.body),
                  if (member.bio != null && member.bio!.isNotEmpty)
                    Text(
                      member.bio!,
                      style: FType.caption.copyWith(
                        color: FColors.inkSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: FSpace.lg),

        // Availability
        Text('Availability', style: FType.eyebrow),
        const SizedBox(height: FSpace.sm),
        Wrap(
          spacing: FSpace.sm,
          runSpacing: FSpace.sm,
          children: [
            for (final avail in member.availability)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: FSpace.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: FColors.surface,
                  borderRadius: BorderRadius.circular(FRadius.sm),
                ),
                child: Text(
                  avail,
                  style: FType.caption.copyWith(color: FColors.inkSecondary),
                ),
              ),
          ],
        ),

        // Preferences
        if (member.stores.isNotEmpty) ...[
          const SizedBox(height: FSpace.lg),
          Text('Preferred Stores', style: FType.eyebrow),
          const SizedBox(height: FSpace.sm),
          Wrap(
            spacing: FSpace.sm,
            runSpacing: FSpace.sm,
            children: [
              for (final store in member.stores)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FSpace.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: FColors.surface,
                    borderRadius: BorderRadius.circular(FRadius.sm),
                  ),
                  child: Text(
                    store,
                    style: FType.caption.copyWith(color: FColors.inkSecondary),
                  ),
                ),
            ],
          ),
        ],

        // Dietary
        if (member.dietary.isNotEmpty) ...[
          const SizedBox(height: FSpace.lg),
          Text('Dietary', style: FType.eyebrow),
          const SizedBox(height: FSpace.sm),
          Wrap(
            spacing: FSpace.sm,
            runSpacing: FSpace.sm,
            children: [
              for (final diet in member.dietary)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FSpace.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: FColors.surface,
                    borderRadius: BorderRadius.circular(FRadius.sm),
                  ),
                  child: Text(
                    diet,
                    style: FType.caption.copyWith(color: FColors.inkSecondary),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// Build trip card content.
  Widget _buildTripContent(BuildContext context, WidgetRef ref, TripPin pin) {
    final trip = pin.trip;
    final shopper = ref
        .read(storeProvider)
        .members
        .firstWhere((m) => m.id == trip.shopperId);
    final departAtText = trip.departAt.toString().split(
      '.',
    )[0]; // "2025-09-20 14:30:00"

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: store + status
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(trip.store, style: FType.body),
                  const SizedBox(height: FSpace.xs),
                  Text(
                    departAtText,
                    style: FType.caption.copyWith(color: FColors.inkSecondary),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: FSpace.sm,
                vertical: FSpace.xs,
              ),
              decoration: BoxDecoration(
                color: _statusColor(trip.status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(FRadius.sm),
                border: Border.all(color: _statusColor(trip.status)),
              ),
              child: Text(
                trip.status.name.toUpperCase(),
                style: FType.caption.copyWith(
                  color: _statusColor(trip.status),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: FSpace.lg),

        // Shopper info
        Text('Shopper', style: FType.eyebrow),
        const SizedBox(height: FSpace.sm),
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tintBgColor(shopper.tint),
              ),
              alignment: Alignment.center,
              child: Text(
                shopper.name[0].toUpperCase(),
                style: FType.body.copyWith(color: tintFgColor(shopper.tint)),
              ),
            ),
            const SizedBox(width: FSpace.md),
            Text(shopper.name, style: FType.body),
          ],
        ),
        const SizedBox(height: FSpace.lg),

        // Spots & items
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${pin.spotsLeft}', style: FType.title),
                Text('spots left', style: FType.caption),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${trip.items.length}', style: FType.title),
                Text('items', style: FType.caption),
              ],
            ),
          ],
        ),
        const SizedBox(height: FSpace.lg),

        // Action button
        if (pin.spotsLeft > 0)
          SizedBox(
            width: double.infinity,
            child: FButton(
              label: 'Add my list',
              onPressed: () {
                context.pop(); // Close bottom sheet
                context.push('/trip/${trip.id}/add-list');
              },
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: FSpace.md,
              vertical: FSpace.md,
            ),
            decoration: BoxDecoration(
              color: FColors.surface,
              borderRadius: BorderRadius.circular(FRadius.md),
            ),
            child: Center(
              child: Text(
                'This trip is full',
                style: FType.caption.copyWith(color: FColors.inkSecondary),
              ),
            ),
          ),
      ],
    );
  }

  /// Build favor card content (Phase 3).
  Widget _buildFavorContent(BuildContext context, FavorPin pin) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(pin.title, style: FType.body),
        const SizedBox(height: FSpace.md),
        Text(pin.requesterName, style: FType.caption),
        const SizedBox(height: FSpace.lg),
        FButton(
          label: 'See details',
          onPressed: () {
            context.pop();
            // Navigation to favor detail will be added in Phase 3
          },
        ),
      ],
    );
  }

  Color _statusColor(TripStatus status) {
    return switch (status) {
      TripStatus.open => const Color(0xFF4a86e8),
      TripStatus.shopping => const Color(0xFF16a765),
      TripStatus.settling => const Color(0xFFffa500),
      TripStatus.done => const Color(0xFF9e9e9e),
    };
  }
}
