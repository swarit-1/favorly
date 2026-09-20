import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../screens/survey_screen.dart';
import '../state/demo_store.dart';
import '../util/format.dart';
import '../widgets/buttons.dart';
import '../widgets/capture.dart';
import '../widgets/page.dart';
import '../widgets/people.dart';
import '../widgets/surfaces.dart';

class HandoffScreen extends ConsumerStatefulWidget {
  const HandoffScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<HandoffScreen> createState() => _HandoffScreenState();
}

class _HandoffScreenState extends ConsumerState<HandoffScreen> {
  bool _photo = false;

  void _deliver() {
    ref.read(storeProvider).confirmHandoff(widget.tripId);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SurveyScreen(tripId: widget.tripId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final trip = store.tripById(widget.tripId);
    final requests = trip.requests.where((r) => r.taking).toList();

    return FavorlyPage(
      topBar: const FTopBar(title: 'Handoff'),
      children: [
        const PageTitle(
          'Confirm handoff',
          subtitle: 'Everything dropped off? This closes the trip and updates the ledger.',
        ),
        if (requests.isEmpty)
          const Notice('No neighbor lists on this trip.', kind: NoticeKind.neutral)
        else
          Panel(
            dividerIndent: 68,
            children: [
              for (final r in requests) _HandoffRow(request: r, store: store, tripId: widget.tripId),
            ],
          ),
        const SizedBox(height: 20),
        if (!_photo)
          FButton(
            label: 'Add a doorstep photo',
            icon: CupertinoIcons.camera,
            kind: FButtonKind.secondary,
            onPressed: () => setState(() => _photo = true),
          )
        else ...[
          const Viewfinder(
            hint: 'Optional. Handy if you leave it at the door.',
            aspectRatio: 16 / 10,
            child: Center(
              child: Icon(CupertinoIcons.cube_box, size: 56, color: Color(0x99FFFFFF)),
            ),
          ),
        ],
      ],
      bottom: FButton(label: 'Mark delivered', onPressed: _deliver),
    );
  }
}

class _HandoffRow extends StatelessWidget {
  const _HandoffRow({required this.request, required this.store, required this.tripId});

  final TripRequest request;
  final DemoStore store;
  final String tripId;

  @override
  Widget build(BuildContext context) {
    final member = store.memberById(request.requesterId);
    final settlement = store.settlementFor(tripId, member.id);
    final carried = request.items
        .where((i) => i.status == ItemStatus.got || i.status == ItemStatus.substituted)
        .length;
    return PanelRow(
      leading: Avatar(member, size: 40),
      title: member.name,
      subtitle: carried == 0
          ? 'Nothing carried'
          : '${plural(carried, 'item')}'
              '${settlement == null ? '' : ' · ${money(settlement.total)}'}',
      trailing: settlement?.paid == true
          ? const StatusPill('Paid', kind: PillKind.success, icon: CupertinoIcons.checkmark_alt)
          : null,
    );
  }
}
