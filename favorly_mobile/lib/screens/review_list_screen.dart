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
import '../widgets/page.dart';
import '../widgets/people.dart';
import '../widgets/surfaces.dart';
import 'attached_screen.dart';

/// Human review of the parsed list. Only uncertain rows are highlighted.
class ReviewListScreen extends ConsumerStatefulWidget {
  const ReviewListScreen({
    super.key,
    required this.tripId,
    required this.drafts,
    required this.source,
  });

  final String tripId;
  final List<ItemDraft> drafts;
  final IntakeSource source;

  @override
  ConsumerState<ReviewListScreen> createState() => _ReviewListScreenState();
}

class _ReviewListScreenState extends ConsumerState<ReviewListScreen> {
  late List<ItemDraft> _items = List.of(widget.drafts);
  bool _reading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(
      Duration(milliseconds: widget.source == IntakeSource.text ? 700 : 1500),
      () {
        if (mounted) setState(() => _reading = false);
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _edit(int? index) async {
    final result = await showFavorlySheet<ItemEditResult>(
      context,
      builder: (_) => ItemEditSheet(draft: index == null ? null : _items[index]),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.removed) {
        _items.removeAt(index!);
      } else if (index == null) {
        _items = [..._items, result.draft!];
      } else {
        _items[index] = result.draft!;
      }
    });
  }

  void _confirm(int index) {
    setState(() {
      _items[index] = _items[index].copyWith(needsConfirmation: false, hint: null);
    });
  }

  void _attach() {
    ref.read(storeProvider).attachRequest(widget.tripId, _items);
    push(context, AttachedScreen(tripId: widget.tripId));
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final trip = store.tripById(widget.tripId);
    final shopper = store.memberById(trip.shopperId);
    final caps = trip.caps;
    final flagged = _items.where((d) => d.needsConfirmation).length;
    final estimate = store.estimatedMax(_items);
    final overItems = _items.length > caps.maxItemsPerPerson;
    final overDollars = estimate > caps.maxDollarsPerPerson;
    final canAttach =
        !_reading && _items.isNotEmpty && flagged == 0 && !overItems && !overDollars;

    final sourceLabel = switch (widget.source) {
      IntakeSource.text => 'your list',
      IntakeSource.voice => 'your voice note',
      IntakeSource.photo => 'your photo',
    };
    final subtitle = _reading
        ? 'Reading $sourceLabel…'
        : _items.isEmpty
            ? 'We couldn’t find any items. Add them below.'
            : flagged > 0
                ? '${plural(_items.length, 'item')} found. '
                    '${plural(flagged, 'needs a look', 'need a look')}.'
                : '${plural(_items.length, 'item')} found. Everything looks clear.';

    return FavorlyPage(
      topBar: const FTopBar(title: 'Check your list'),
      children: [
        PageTitle('Check your list', subtitle: subtitle),
        if (_reading)
          const ShimmerRows(count: 5)
        else ...[
          Panel(
            children: [
              for (var i = 0; i < _items.length; i++)
                _DraftRow(
                  draft: _items[i],
                  onTap: () => _edit(i),
                  onConfirm: () => _confirm(i),
                ),
              PanelRow(
                leading: const Icon(CupertinoIcons.plus_circle_fill, size: 24, color: FColors.blue),
                title: 'Add item',
                titleStyle: FType.bodyStrong.copyWith(color: FColors.blue),
                chevron: false,
                onTap: () => _edit(null),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Panel(
            color: FColors.surface,
            outlined: false,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Estimated max',
                      style: FType.bodySmall.copyWith(color: FColors.inkSecondary),
                    ),
                  ),
                  Text(moneyShort(estimate), style: FType.money),
                ],
              ),
            ],
          ),
          if (overItems || overDollars) ...[
            const SizedBox(height: 10),
            Notice(
              'Over ${shopper.firstName}’s cap of '
              '${overItems ? plural(caps.maxItemsPerPerson, 'item') : moneyShort(caps.maxDollarsPerPerson)}. '
              'Trim the list to attach.',
              kind: NoticeKind.attention,
            ),
          ],
        ],
      ],
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_reading && flagged > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Check the highlighted ${flagged == 1 ? 'item' : 'items'} first.',
                textAlign: TextAlign.center,
                style: FType.caption.copyWith(color: FColors.inkSecondary),
              ),
            ),
          FButton(
            label: _items.isEmpty ? 'Attach list' : 'Attach ${plural(_items.length, 'item')}',
            onPressed: canAttach ? _attach : null,
          ),
        ],
      ),
    );
  }
}

class _DraftRow extends StatelessWidget {
  const _DraftRow({
    required this.draft,
    required this.onTap,
    required this.onConfirm,
  });

  final ItemDraft draft;
  final VoidCallback onTap;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final flagged = draft.needsConfirmation;
    return Material(
      color: flagged ? FColors.attentionTint : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(draft.name, style: FType.bodyStrong),
                        if (draft.note != null)
                          Text(
                            draft.note!,
                            style: FType.bodySmall.copyWith(color: FColors.inkSecondary),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: flagged ? FColors.canvas : FColors.surface,
                      borderRadius: BorderRadius.circular(FRadius.sm),
                    ),
                    child: Text(draft.qtyLabel, style: FType.captionStrong),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 48,
                    child: Text(
                      draft.maxPrice == null ? 'no cap' : moneyShort(draft.maxPrice!),
                      textAlign: TextAlign.right,
                      style: draft.maxPrice == null
                          ? FType.caption.copyWith(color: FColors.inkTertiary)
                          : FType.money.copyWith(color: FColors.inkSecondary),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(CupertinoIcons.chevron_right, size: 18, color: FColors.inkTertiary),
                ],
              ),
              if (flagged) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(CupertinoIcons.exclamationmark_circle_fill,
                        size: 16, color: FColors.attention),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Check this${draft.hint == null ? '' : ' · ${draft.hint}'}',
                        style: FType.captionStrong.copyWith(color: FColors.attention),
                      ),
                    ),
                    FTextButton('Looks right', onPressed: onConfirm, color: FColors.attention),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ItemEditResult {
  const ItemEditResult.saved(this.draft) : removed = false;
  const ItemEditResult.remove()
      : draft = null,
        removed = true;

  final ItemDraft? draft;
  final bool removed;
}

class ItemEditSheet extends StatefulWidget {
  const ItemEditSheet({super.key, this.draft});

  final ItemDraft? draft;

  @override
  State<ItemEditSheet> createState() => _ItemEditSheetState();
}

class _ItemEditSheetState extends State<ItemEditSheet> {
  late final _name = TextEditingController(text: widget.draft?.name ?? '');
  late final _unit = TextEditingController(text: widget.draft?.unit ?? '');
  late final _note = TextEditingController(text: widget.draft?.note ?? '');
  late final _price = TextEditingController(
    text: widget.draft?.maxPrice == null
        ? ''
        : moneyShort(widget.draft!.maxPrice!).replaceFirst('\$', ''),
  );
  late int _qty = widget.draft?.qty ?? 1;

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _note.dispose();
    _price.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final unit = _unit.text.trim();
    final note = _note.text.trim();
    final price = double.tryParse(_price.text.trim());
    Navigator.of(context).pop(ItemEditResult.saved(ItemDraft(
      name: name[0].toUpperCase() + name.substring(1),
      qty: _qty,
      unit: unit.isEmpty ? null : unit,
      note: note.isEmpty ? null : note,
      maxPrice: price,
    )));
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.draft != null;
    return SheetBody(
      children: [
        SheetTitle(existing ? 'Edit item' : 'Add item'),
        const FieldLabel('Item'),
        TextField(
          controller: _name,
          autofocus: !existing,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(hintText: 'Oat milk'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        const FieldLabel('Quantity'),
        Row(
          children: [
            QtyStepper(
              value: _qty,
              max: 30,
              semanticLabel: 'quantity',
              onChanged: (v) => setState(() => _qty = v),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _unit,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: 'unit, optional'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const FieldLabel('Note', hint: 'optional'),
        TextField(
          controller: _note,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(hintText: 'ripe, unsalted, any brand…'),
        ),
        const SizedBox(height: 16),
        const FieldLabel('Max price', hint: 'optional'),
        TextField(
          controller: _price,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: '6', prefixText: '\$ '),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 8),
      ],
      bottom: BottomActions(
        children: [
          FButton(
            label: existing ? 'Save' : 'Add item',
            onPressed: _name.text.trim().isEmpty ? null : _save,
          ),
          if (existing)
            FButton(
              label: 'Remove item',
              kind: FButtonKind.destructive,
              onPressed: () => Navigator.of(context).pop(const ItemEditResult.remove()),
            ),
        ],
      ),
    );
  }
}
