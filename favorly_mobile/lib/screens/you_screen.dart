import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../state/demo_store.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/page.dart';
import '../widgets/people.dart';
import '../widgets/surfaces.dart';

class YouScreen extends ConsumerWidget {
  const YouScreen({super.key});

  String _role(DemoStore store, Member m) {
    final trip = store.activeTrip;
    if (trip == null) return 'Neighbor';
    if (trip.shopperId == m.id) return 'Shopping at ${trip.store}';
    if (store.requestFor(trip, m.id) != null) return 'Has a list on the ${trip.store} trip';
    return 'Neighbor';
  }

  Future<void> _editVenmo(BuildContext context, DemoStore store) async {
    final handle = await showFavorlySheet<String>(
      context,
      builder: (_) => _VenmoSheet(initial: store.me.venmoHandle),
    );
    if (handle == null || handle.trim().isEmpty) return;
    store.updateVenmo(handle);
  }

  void _confirmReset(BuildContext context, DemoStore store) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Reset demo data?'),
        message: const Text('Trips, lists, and the ledger go back to the seeded state.'),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.of(ctx).pop();
              store.resetDemo();
            },
            child: const Text('Reset'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    final me = store.me;

    return FavorlyPage(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Row(
          children: [
            Avatar(me, size: 60),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(me.name, style: FType.heading),
                  const SizedBox(height: 2),
                  Text(
                    DemoStore.circleName,
                    style: FType.bodySmall.copyWith(color: FColors.inkSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SectionHeader('Payments'),
        Panel(
          children: [
            PanelRow(
              leading: const LeadingIcon(CupertinoIcons.creditcard),
              title: 'Venmo',
              subtitle: '@${me.venmoHandle}',
              onTap: () => _editVenmo(context, store),
            ),
          ],
        ),
        const SectionHeader('Notifications'),
        Panel(
          children: [
            PanelRow(
              leading: const LeadingIcon(CupertinoIcons.bell),
              title: 'Trip updates',
              subtitle: 'New trips, substitutions, receipts',
              trailing: Switch.adaptive(
                value: store.notificationsOn,
                activeTrackColor: FColors.blue,
                onChanged: store.setNotifications,
              ),
            ),
          ],
        ),
        const SectionHeader('Demo', padding: EdgeInsets.only(top: 28, bottom: 4)),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Switch neighbors to see the same trip from their side.',
            style: FType.caption.copyWith(color: FColors.inkSecondary),
          ),
        ),
        Panel(
          dividerIndent: 68,
          children: [
            for (final m in store.members)
              PanelRow(
                leading: Avatar(m, size: 40),
                title: m.name,
                subtitle: _role(store, m),
                trailing: m.id == store.meId
                    ? const Icon(CupertinoIcons.checkmark_circle_fill, size: 22, color: FColors.blue)
                    : null,
                chevron: false,
                onTap: () => store.viewAs(m.id),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Panel(
          children: [
            PanelRow(
              leading: const LeadingIcon(CupertinoIcons.arrow_counterclockwise),
              title: 'Reset demo data',
              chevron: false,
              onTap: () => _confirmReset(context, store),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Center(
          child: FTextButton('Leave circle', color: FColors.critical, onPressed: store.signOut),
        ),
      ],
    );
  }
}

class _VenmoSheet extends StatefulWidget {
  const _VenmoSheet({required this.initial});

  final String initial;

  @override
  State<_VenmoSheet> createState() => _VenmoSheetState();
}

class _VenmoSheetState extends State<_VenmoSheet> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return SheetBody(
      children: [
        const SheetTitle('Venmo handle', subtitle: 'Neighbors pay you here after a trip.'),
        TextField(
          controller: _controller,
          autofocus: true,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(prefixText: '@ ', hintText: 'your-handle'),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 8),
      ],
      bottom: FButton(label: 'Save', onPressed: _save),
    );
  }
}
