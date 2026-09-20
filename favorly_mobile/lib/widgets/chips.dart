import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Selectable pill for quick picks (store names, times).
class SelectChip extends StatelessWidget {
  const SelectChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? FColors.blue : FColors.ink;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? FColors.blueTint : FColors.surface,
        shape: StadiumBorder(
          side: selected
              ? const BorderSide(color: FColors.blue, width: 1.5)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(label, style: FType.bodySmallStrong.copyWith(color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon in a soft circle, used as the leading element of rows.
class LeadingIcon extends StatelessWidget {
  const LeadingIcon(
    this.icon, {
    super.key,
    this.size = 36,
    this.color = FColors.inkSecondary,
    this.background = FColors.surface,
  });

  final IconData icon;
  final double size;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(icon, size: size * 0.5, color: color),
    );
  }
}
