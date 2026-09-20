import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../state/demo_store.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../util/nav.dart';
import '../widgets/buttons.dart';
import '../widgets/page.dart';
import '../widgets/people.dart';
import '../widgets/surfaces.dart';
import 'receipt_screen.dart';
import 'substitution_capture_screen.dart';

/// The merged, aisle-ordered list. One tap marks an item got; "Not here"
/// starts the substitution beat.
class ShoppingScreen extends ConsumerWidget {
  const ShoppingScreen({super.key, required this.tripId});

  final String tripId;

  void _scanReceipt(BuildContext context, DemoStore store, Trip trip) {
    final open = trip.items.where((i) => i.isOpen).length;
    if (open == 0) {
      push(context, ReceiptScreen(tripId: tripId));
      return;
    }
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text('${plural(open, 'item is', 'items are')} still open'),
        message: const Text('Skip them and scan the receipt?'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(ctx).pop();
              store.skipRemaining(tripId);
              push(context, ReceiptScreen(tripId: tripId));
            },
            child: const Text('Skip them and scan'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Keep shopping'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    final trip = store.tripById(tripId);
    final items = trip.items;
    final done = items.where((i) => !i.isOpen).length;
    final neighbors = trip.requests.where((r) => r.taking).length;

    return FavorlyPage(
      topBar: const FTopBar(title: 'Shopping'),
      children: [
        PageTitle(
          trip.store,
          subtitle: '$done of ${items.length} done · ${plural(neighbors, 'neighbor')}',
          padding: const EdgeInsets.only(top: 4, bottom: 14),
        ),
        ProgressBar(
          value: items.isEmpty ? 0 : done / items.length,
          label: 'Shopping progress',
        ),
        if (items.isEmpty) ...[
          const SizedBox(height: 24),
          const EmptyState(
            icon: CupertinoIcons.doc_text,
            title: 'Nothing to carry',
            body: 'No neighbor added a list. You can still scan the receipt for your own basket.',
          ),
        ],
        for (final section in StoreSection.values)
          ..._section(context, store, trip, section, items),
      ],
      bottom: FButton(
        label: 'Scan receipt',
        icon: CupertinoIcons.camera_fill,
        onPressed: () => _scanReceipt(context, store, trip),
      ),
    );
  }

  List<Widget> _section(
    BuildContext context,
    DemoStore store,
    Trip trip,
    StoreSection section,
    List<TripItem> items,
  ) {
    final rows = items.where((i) => i.section == section).toList();
    if (rows.isEmpty) return const [];
    return [
      const SizedBox(height: 24),
      Eyebrow(section.label),
      const SizedBox(height: 8),
      Panel(
        dividerIndent: 56,
        children: [
          for (final item in rows)
            _ShopRow(
              item: item,
              requester: store.memberById(item.requesterId),
              onToggle: () => store.toggleGot(tripId, item.id),
              onNotHere: () => push(
                context,
                SubstitutionCaptureScreen(tripId: tripId, itemId: item.id),
              ),
            ),
        ],
      ),
    ];
  }
}

class _ShopRow extends StatelessWidget {
  const _ShopRow({
    required this.item,
    required this.requester,
    required this.onToggle,
    required this.onNotHere,
  });

  final TripItem item;
  final Member requester;
  final VoidCallback onToggle;
  final VoidCallback onNotHere;

  @override
  Widget build(BuildContext context) {
    final open = item.isOpen;
    final got = item.status == ItemStatus.got;
    final title = item.status == ItemStatus.substituted
        ? item.substituteName!
        : (item.qty > 1 ? '${item.name} · ${item.qtyLabel}' : item.name);
    final subtitle = switch (item.status) {
      ItemStatus.substituted =>
        'Instead of ${item.name.toLowerCase()} · ${requester.firstName} chose it',
      ItemStatus.skipped => 'Skipped',
      _ => item.note,
    };
    final (String? pill, PillKind pillKind) = switch (item.status) {
      ItemStatus.got => ('Got it', PillKind.success),
      ItemStatus.substituted => ('Swapped', PillKind.info),
      ItemStatus.skipped => ('Skipped', PillKind.neutral),
      ItemStatus.pending => (null, PillKind.neutral),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CheckControl(
            status: item.status,
            label: item.displayName,
            onTap: open || got ? onToggle : null,
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: FType.bodyStrong.copyWith(
                            color: open ? FColors.ink : FColors.inkSecondary,
                            decoration: item.status == ItemStatus.skipped
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      if (item.maxPrice != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          moneyShort(item.maxPrice!),
                          style: FType.moneySmall.copyWith(color: FColors.inkSecondary),
                        ),
                      ],
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: FType.bodySmall.copyWith(color: FColors.inkSecondary)),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      MemberChip(requester),
                      const Spacer(),
                      if (open)
                        Semantics(
                          container: true,
                          label: 'Not here, ${item.name}',
                          child: _SmallButton(label: 'Not here', onPressed: onNotHere),
                        )
                      else if (pill != null)
                        StatusPill(pill, kind: pillKind),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckControl extends StatelessWidget {
  const _CheckControl({
    required this.status,
    required this.label,
    required this.onTap,
  });

  final ItemStatus status;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color border, IconData? icon, Color iconColor) = switch (status) {
      ItemStatus.pending => (Colors.transparent, FColors.hairlineStrong, null, Colors.transparent),
      ItemStatus.got => (FColors.blue, FColors.blue, CupertinoIcons.checkmark_alt, Colors.white),
      ItemStatus.substituted => (FColors.success, FColors.success, CupertinoIcons.arrow_2_squarepath, Colors.white),
      ItemStatus.skipped => (FColors.surface, FColors.surface, CupertinoIcons.minus, FColors.inkTertiary),
    };
    return Semantics(
      button: onTap != null,
      checked: status == ItemStatus.got,
      label: 'Got $label',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: AnimatedContainer(
                duration: FMotion.quick,
                curve: FMotion.curve,
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: bg,
                  shape: BoxShape.circle,
                  border: Border.all(color: border, width: 2),
                ),
                child: icon == null ? null : Icon(icon, size: 15, color: iconColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: FColors.ink,
        backgroundColor: FColors.surface,
        textStyle: FType.captionStrong,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        minimumSize: const Size(0, 34),
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: const StadiumBorder(),
        splashFactory: NoSplash.splashFactory,
      ),
      child: Text(label),
    );
  }
}
