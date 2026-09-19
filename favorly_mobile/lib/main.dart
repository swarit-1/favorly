import 'package:flutter/material.dart';

void main() {
  runApp(const FavorlyApp());
}

class FavorlyApp extends StatelessWidget {
  const FavorlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Favorly',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const RootShell(),
    );
  }
}

/// Bottom-nav shell. Tabs are placeholders — the real pages land here later.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static const _tabs = <_Tab>[
    _Tab('Trips', Icons.storefront_outlined, Icons.storefront),
    _Tab('Request', Icons.add_shopping_cart_outlined, Icons.add_shopping_cart),
    _Tab('Shop', Icons.checklist_outlined, Icons.checklist),
    _Tab('Ledger', Icons.receipt_long_outlined, Icons.receipt_long),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorly'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: IndexedStack(
        index: _index,
        children: [
          for (final tab in _tabs) _Placeholder(label: tab.label),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}

class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
