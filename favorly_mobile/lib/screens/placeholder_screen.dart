import 'package:flutter/material.dart';

import '../theme.dart';

/// Stand-in for tabs that have no comps yet.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.greenTintDeep),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Not designed yet', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
