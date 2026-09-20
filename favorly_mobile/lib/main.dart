import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/join_screen.dart';
import 'screens/shell.dart';
import 'state/demo_store.dart';
import 'theme/theme.dart';
import 'widgets/page.dart';

void main() {
  runApp(const ProviderScope(child: FavorlyApp()));
}

class FavorlyApp extends StatelessWidget {
  const FavorlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Favorly',
      debugShowCheckedModeBanner: false,
      theme: buildFavorlyTheme(),
      scrollBehavior: const _ScrollBehavior(),
      builder: (context, child) => WebFrame(child: child ?? const SizedBox.shrink()),
      home: const _Home(),
    );
  }
}

class _Home extends ConsumerWidget {
  const _Home();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final joined = ref.watch(storeProvider).joined;
    return joined ? const RootShell() : const JoinScreen();
  }
}

/// Lets the web build scroll with a mouse drag as well as a wheel.
class _ScrollBehavior extends MaterialScrollBehavior {
  const _ScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet();
}
