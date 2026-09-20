import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/demo_store.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../util/nav.dart';
import '../widgets/buttons.dart';
import '../widgets/capture.dart';
import '../widgets/chips.dart';
import '../widgets/page.dart';
import '../widgets/surfaces.dart';

class AttachedScreen extends ConsumerWidget {
  const AttachedScreen({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    final trip = store.tripById(tripId);
    final shopper = store.memberById(trip.shopperId);
    final request = store.myRequest(trip);
    final items = request?.items ?? const [];
    final estimate = items.fold<double>(
      0,
      (sum, i) => sum + (i.maxPrice ?? DemoStore.unitPriceFor(i.name) * i.qty),
    );

    return FavorlyPage(
      topBar: const FTopBar(showBack: false),
      children: [
        const SizedBox(height: 16),
        const Center(child: CheckBurst()),
        const SizedBox(height: 24),
        Text(
          'Your list is with ${shopper.firstName}',
          textAlign: TextAlign.center,
          style: FType.title,
        ),
        const SizedBox(height: 8),
        Text(
          '${plural(items.length, 'item')} · up to ${moneyShort(estimate)}',
          textAlign: TextAlign.center,
          style: FType.body.copyWith(color: FColors.inkSecondary),
        ),
        const SizedBox(height: 28),
        Panel(
          children: [
            PanelRow(
              leading: const LeadingIcon(CupertinoIcons.cart, size: 40),
              title: trip.store,
              subtitle: 'Leaves ${dayLabel(trip.departAt).toLowerCase()} at ${clock(trip.departAt)}',
            ),
          ],
        ),
        const SizedBox(height: 28),
        _Timeline(
          steps: [
            ('List attached', _StepState.done),
            ('${shopper.firstName} reviews it', _StepState.current),
            ('Shopping starts', _StepState.upcoming),
          ],
        ),
      ],
      bottom: BottomActions(
        children: [
          FButton(label: 'Done', onPressed: () => popToRoot(context)),
          FButton(
            label: 'Edit my list',
            kind: FButtonKind.tertiary,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

enum _StepState { done, current, upcoming }

class _Timeline extends StatelessWidget {
  const _Timeline({required this.steps});

  final List<(String, _StepState)> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                child: Column(
                  children: [
                    _Dot(state: steps[i].$2),
                    if (i < steps.length - 1)
                      Container(width: 2, height: 26, color: FColors.hairline),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  steps[i].$1,
                  style: steps[i].$2 == _StepState.upcoming
                      ? FType.bodySmall.copyWith(color: FColors.inkSecondary)
                      : FType.bodySmallStrong,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.state});

  final _StepState state;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      _StepState.done => Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(color: FColors.success, shape: BoxShape.circle),
          child: const Icon(CupertinoIcons.checkmark_alt, size: 14, color: Colors.white),
        ),
      _StepState.current => Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: FColors.blue, width: 3),
          ),
          child: Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: FColors.blue, shape: BoxShape.circle),
            ),
          ),
        ),
      _StepState.upcoming => Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: FColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: FColors.hairlineStrong),
          ),
        ),
    };
  }
}
