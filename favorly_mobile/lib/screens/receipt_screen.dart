import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../state/demo_store.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../util/nav.dart';
import '../widgets/buttons.dart';
import '../widgets/capture.dart';
import '../widgets/chips.dart';
import '../widgets/page.dart';
import '../widgets/people.dart';
import '../widgets/surfaces.dart';

enum _Stage { capture, reading, review }

/// Receipt split. The shopper reviews exceptions, never the whole table.
class ReceiptScreen extends ConsumerStatefulWidget {
  const ReceiptScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  _Stage _stage = _Stage.capture;
  Timer? _timer;
  bool _matchesOpen = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _scan() {
    setState(() => _stage = _Stage.reading);
    _timer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      ref.read(storeProvider).scanReceipt(widget.tripId);
      setState(() => _stage = _Stage.review);
    });
  }

  void _confirm() {
    final settlements = ref.read(storeProvider).confirmSplit(widget.tripId);
    final messenger = ScaffoldMessenger.of(context);
    popToTrip(context, widget.tripId);
    messenger.showSnackBar(SnackBar(
      content: Text('Split sent to ${plural(settlements.length, 'neighbor')}.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final trip = store.tripById(widget.tripId);
    final split = store.receiptFor(widget.tripId) ?? store.buildReceipt(widget.tripId);

    if (_stage != _Stage.review) {
      return FavorlyPage(
        topBar: const FTopBar(title: 'Receipt'),
        children: [
          const PageTitle(
            'Scan the receipt',
            subtitle: 'Fit the whole receipt in frame. Favorly matches each line to a neighbor.',
            padding: EdgeInsets.only(top: 4, bottom: 16),
          ),
          Viewfinder(
            hint: 'Hold steady',
            status: _stage == _Stage.reading ? 'Reading the receipt…' : null,
            child: MockReceipt(split: split),
          ),
        ],
        bottom: FButton(
          label: 'Scan receipt',
          icon: CupertinoIcons.camera_fill,
          busy: _stage == _Stage.reading,
          onPressed: _scan,
        ),
      );
    }

    final review = split.needsReview;
    final matched = split.matched;
    return FavorlyPage(
      topBar: const FTopBar(title: 'Receipt'),
      children: [
        PageTitle(
          'Check the receipt',
          subtitle: review.isEmpty
              ? 'All ${plural(split.lines.length, 'line')} matched.'
              : '${plural(matched.length, 'line')} matched. '
                  '${plural(review.length, 'needs you', 'need you')}.',
        ),
        Panel(
          color: FColors.surface,
          outlined: false,
          dividers: false,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          children: [
            Row(
              children: [
                const LeadingIcon(CupertinoIcons.cart, background: FColors.canvas),
                const SizedBox(width: 12),
                Text(split.store, style: FType.subheading),
              ],
            ),
            const SizedBox(height: 10),
            KeyValueRow('Subtotal', money(split.subtotal)),
            KeyValueRow('Tax', money(split.tax)),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Divider(color: FColors.hairlineStrong),
            ),
            KeyValueRow('Total', money(split.total), strong: true),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(CupertinoIcons.checkmark_circle_fill, size: 16, color: FColors.success),
                const SizedBox(width: 6),
                Text('Totals add up', style: FType.captionStrong.copyWith(color: FColors.success)),
              ],
            ),
          ],
        ),
        if (review.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: FColors.attentionTint,
              borderRadius: BorderRadius.circular(FRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Eyebrow(
                  'Needs review',
                  icon: CupertinoIcons.exclamationmark_circle_fill,
                  color: FColors.attention,
                ),
                for (final line in review) ...[
                  const SizedBox(height: 14),
                  _AmbiguousLine(
                    line: line,
                    shopperId: trip.shopperId,
                    nameFor: (id) => store.memberById(id).firstName,
                    onPick: (id) => store.assignLine(widget.tripId, line.lineNo, id),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Panel(
          children: [
            PanelRow(
              leading: const Icon(CupertinoIcons.checkmark_circle_fill, size: 22, color: FColors.success),
              title: '${plural(matched.length, 'match', 'matches')} look right',
              trailing: Icon(
                _matchesOpen ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
                size: 18,
                color: FColors.inkTertiary,
              ),
              chevron: false,
              onTap: () => setState(() => _matchesOpen = !_matchesOpen),
            ),
            if (_matchesOpen)
              for (final line in matched)
                PanelRow(
                  minHeight: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  title: line.description,
                  titleStyle: FType.bodySmallStrong,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (line.assignedTo == trip.shopperId)
                        Text('Mine', style: FType.caption.copyWith(color: FColors.inkSecondary))
                      else if (line.assignedTo != null)
                        MemberChip(store.memberById(line.assignedTo!)),
                      const SizedBox(width: 12),
                      Text(money(line.total), style: FType.moneySmall),
                    ],
                  ),
                ),
          ],
        ),
      ],
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!split.resolved)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Pick who the highlighted line was for.',
                textAlign: TextAlign.center,
                style: FType.caption.copyWith(color: FColors.inkSecondary),
              ),
            ),
          FButton(label: 'Confirm split', onPressed: split.resolved ? _confirm : null),
        ],
      ),
    );
  }
}

class _AmbiguousLine extends StatelessWidget {
  const _AmbiguousLine({
    required this.line,
    required this.shopperId,
    required this.nameFor,
    required this.onPick,
  });

  final ReceiptLine line;
  final String shopperId;
  final String Function(String memberId) nameFor;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(line.description, style: FType.bodyStrong)),
            Text(money(line.total), style: FType.money),
          ],
        ),
        const SizedBox(height: 4),
        Text('Who was this for?', style: FType.bodySmall.copyWith(color: FColors.inkSecondary)),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: CupertinoSlidingSegmentedControl<String>(
            groupValue: line.assignedTo,
            backgroundColor: FColors.canvas,
            thumbColor: FColors.blue,
            padding: const EdgeInsets.all(3),
            children: {
              for (final id in line.options)
                id: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Text(
                    id == shopperId ? 'Mine' : nameFor(id),
                    style: FType.captionStrong.copyWith(
                      color: line.assignedTo == id ? FColors.onAccent : FColors.ink,
                    ),
                  ),
                ),
            },
            onValueChanged: (v) {
              if (v != null) onPick(v);
            },
          ),
        ),
      ],
    );
  }
}
