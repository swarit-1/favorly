import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../state/demo_store.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/page.dart';
import '../widgets/people.dart';
import '../widgets/surfaces.dart';

class YouScreen extends ConsumerWidget {
  const YouScreen({super.key});

  Future<void> _editVenmo(BuildContext context, DemoStore store) async {
    final handle = await showFavorlySheet<String>(
      context,
      builder: (_) => _VenmoSheet(initial: store.me.venmoHandle),
    );
    if (handle == null || handle.trim().isEmpty) return;
    store.updateVenmo(handle);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final store = ref.watch(storeProvider);
    final me = store.me;

    // Use auth name if available, fall back to demo
    final displayName = authState.name ?? me.name;
    final displayCircle = authState.circleId != null ? 'Your Circle' : DemoStore.circleName;

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
                  Text(displayName, style: FType.heading),
                  const SizedBox(height: 2),
                  Text(
                    displayCircle,
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
        const SizedBox(height: 20),
        Center(
          child: FTextButton(
            'Leave circle',
            color: FColors.critical,
            onPressed: () {
              // Logout from both auth provider and demo store
              ref.read(authProvider.notifier).logout();
              store.signOut();
            },
          ),
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
