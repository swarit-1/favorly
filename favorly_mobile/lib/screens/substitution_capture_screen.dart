import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../state/demo_store.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/buttons.dart';
import '../widgets/capture.dart';
import '../widgets/page.dart';
import '../widgets/surfaces.dart';
import 'substitution_choice_sheet.dart';

enum _Stage { capture, reading, waiting }

/// Shopper side of the substitution beat: snap the shelf, then wait for the
/// requester's answer.
class SubstitutionCaptureScreen extends ConsumerStatefulWidget {
  const SubstitutionCaptureScreen({
    super.key,
    required this.tripId,
    required this.itemId,
  });

  final String tripId;
  final String itemId;

  @override
  ConsumerState<SubstitutionCaptureScreen> createState() =>
      _SubstitutionCaptureScreenState();
}

class _SubstitutionCaptureScreenState
    extends ConsumerState<SubstitutionCaptureScreen> {
  _Stage _stage = _Stage.capture;
  String? _promptId;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _scan() {
    setState(() => _stage = _Stage.reading);
    _timer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      final prompt =
          ref.read(storeProvider).askForSubstitute(widget.tripId, widget.itemId);
      setState(() {
        _promptId = prompt.id;
        _stage = _Stage.waiting;
      });
    });
  }

  void _skip() {
    final store = ref.read(storeProvider);
    final item = store.itemById(widget.tripId, widget.itemId);
    store.skipItem(widget.tripId, widget.itemId);
    _leave('Skipped ${item.name.toLowerCase()}');
  }

  void _leave(String message) {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _onResolved(DemoStore store) {
    final item = store.itemById(widget.tripId, widget.itemId);
    final requester = store.memberById(item.requesterId);
    final message = item.status == ItemStatus.substituted
        ? '${requester.firstName} chose ${item.substituteName}'
        : '${requester.firstName} skipped ${item.name.toLowerCase()}';
    _promptId = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _leave(message);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<DemoStore>(storeProvider, (_, store) {
      if (_promptId != null && store.pendingPrompt?.id != _promptId) {
        _onResolved(store);
      }
    });

    final store = ref.watch(storeProvider);
    final item = store.itemById(widget.tripId, widget.itemId);
    final requester = store.memberById(item.requesterId);
    final prompt = store.pendingPrompt;
    final details = [
      'For ${requester.firstName}',
      if (item.maxPrice != null) 'up to ${moneyShort(item.maxPrice!)}',
      if (item.note != null) item.note!,
    ].join(' · ');

    return FavorlyPage(
      topBar: const FTopBar(title: 'Find a substitute'),
      children: [
        PageTitle(
          item.name,
          subtitle: details,
          padding: const EdgeInsets.only(top: 4, bottom: 16),
        ),
        if (_stage != _Stage.waiting)
          Viewfinder(
            hint: 'Fit the shelf and price tags in frame',
            status: _stage == _Stage.reading ? 'Reading the shelf…' : null,
            child: const MockShelf(prices: [4.49, 5.29, 5.99, 4.79, 5.49, 6.29]),
          )
        else if (prompt != null && prompt.id == _promptId) ...[
          Notice(
            'Asking ${requester.firstName}. Your list updates when they answer.',
            icon: CupertinoIcons.person_crop_circle_badge_checkmark,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(child: Text('What we found', style: FType.subheading)),
              CountdownRing(
                expiresAt: prompt.expiresAt,
                window: DemoStore.substitutionWindow,
                onExpired: () => store.resolveSubstitution(prompt.id),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Panel(
            children: [
              for (final c in prompt.candidates)
                PanelRow(
                  title: c.name,
                  subtitle: '${c.size} · ${c.reason}',
                  value: money(c.price),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${requester.firstName} picks one or skips. If they don’t answer in time, the item is skipped.',
            style: FType.caption.copyWith(color: FColors.inkSecondary),
          ),
        ],
      ],
      bottom: switch (_stage) {
        _Stage.capture => BottomActions(
            children: [
              FButton(label: 'Scan shelf', icon: CupertinoIcons.camera_fill, onPressed: _scan),
              FButton(label: 'Skip this item', kind: FButtonKind.tertiary, onPressed: _skip),
            ],
          ),
        _Stage.reading => const FButton(label: 'Scan shelf', busy: true),
        _Stage.waiting => BottomActions(
            children: [
              FButton(
                label: 'Skip instead',
                kind: FButtonKind.secondary,
                onPressed: () => store.resolveSubstitution(_promptId!),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const StatusPill('Demo'),
                  const SizedBox(width: 4),
                  FTextButton(
                    'Answer as ${requester.firstName}',
                    onPressed: () => showSubstitutionChoiceSheet(context, _promptId!),
                  ),
                ],
              ),
            ],
          ),
      },
    );
  }
}
