import 'package:flutter/material.dart';

import 'screens/placeholder_screen.dart';
import 'screens/trips_screen.dart';
import 'theme.dart';

void main() {
  runApp(const FavorlyApp());
}

class FavorlyApp extends StatelessWidget {
  const FavorlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Favorly',
      theme: buildFavorlyTheme(),
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static const _tabs = <_TabSpec>[
    _TabSpec('Trips', Icons.home_outlined, Icons.home_rounded),
    _TabSpec('Circle', Icons.groups_outlined, Icons.groups_rounded),
    _TabSpec('You', Icons.person_outline_rounded, Icons.person_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          TripsScreen(),
          PlaceholderScreen(title: 'Circle', icon: Icons.groups_rounded),
          PlaceholderScreen(title: 'You', icon: Icons.person_rounded),
        ],
      ),
      bottomNavigationBar: _FavorlyNavBar(
        index: _index,
        tabs: _tabs,
        onChanged: (i) => setState(() => _index = i),
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// Custom bar: the comps use a green label with a short underline for the
/// active tab, which Material's NavigationBar pill indicator can't express.
class _FavorlyNavBar extends StatelessWidget {
  const _FavorlyNavBar({
    required this.index,
    required this.tabs,
    required this.onChanged,
  });

  final int index;
  final List<_TabSpec> tabs;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cream,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: _NavItem(
                    tab: tabs[i],
                    selected: i == index,
                    onTap: () => onChanged(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _TabSpec tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.green : AppColors.muted;

    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? tab.activeIcon : tab.icon, size: 26, color: color),
            const SizedBox(height: 4),
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: 2,
              width: 26,
              decoration: BoxDecoration(
                color: selected ? AppColors.green : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
