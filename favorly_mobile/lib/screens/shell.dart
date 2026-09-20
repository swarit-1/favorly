import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/notification_provider.dart';
import '../state/demo_store.dart';
import '../theme/tokens.dart';
import 'circle_screen.dart';
import 'neighborhood_map_screen.dart';
import 'substitution_choice_sheet.dart';
import 'trips_screen.dart';
import 'you_screen.dart';

class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  String? _shownPromptId;

  // Order matters twice over: it is the tab bar, and FTab names these
  // positions for the screens that jump between them. Change one, change both.
  // "Home" is a label change only; the position is still FTab.trips.
  static const _tabs = [
    _TabSpec('Home', CupertinoIcons.house, CupertinoIcons.house_fill),
    _TabSpec('Circle', CupertinoIcons.person_2, CupertinoIcons.person_2_fill),
    _TabSpec(
      'Map',
      CupertinoIcons.map,
      CupertinoIcons.map_fill,
    ),
    _TabSpec(
      'You',
      CupertinoIcons.person_crop_circle,
      CupertinoIcons.person_crop_circle_fill,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(tabProvider);

    // Load notifications when user is authenticated
    ref.listen<AuthState>(authProvider, (_, auth) {
      if (auth.accessToken != null) {
        ref.read(notificationProvider.notifier).load(auth.accessToken!);
      }
    });

    // Realtime stand-in: when a substitution prompt lands for the person
    // holding this phone, the chooser slides up wherever they are.
    ref.listen<DemoStore>(storeProvider, (_, store) => _maybeShowPrompt(store));
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: const [TripsScreen(), CircleScreen(), NeighborhoodMapScreen(), YouScreen()],
      ),
      bottomNavigationBar: _TabBar(
        index: index,
        tabs: _tabs,
        onChanged: (i) => ref.read(tabProvider.notifier).state = i,
      ),
    );
  }

  void _maybeShowPrompt(DemoStore store) {
    final prompt = store.promptForMe;
    if (prompt == null || prompt.id == _shownPromptId) return;
    _shownPromptId = prompt.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showSubstitutionChoiceSheet(context, prompt.id);
    });
  }
}

class _TabSpec {
  const _TabSpec(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.index,
    required this.tabs,
    required this.onChanged,
  });

  final int index;
  final List<_TabSpec> tabs;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FColors.canvas,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: FColors.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(
                    child: _TabItem(
                      tab: tabs[i],
                      selected: i == index,
                      onTap: () => onChanged(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _TabSpec tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? FColors.blue : FColors.inkSecondary;
    return Semantics(
      selected: selected,
      button: true,
      label: '${tab.label} tab',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? tab.activeIcon : tab.icon, size: 24, color: color),
            const SizedBox(height: 3),
            Text(tab.label, style: FType.captionStrong.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}
