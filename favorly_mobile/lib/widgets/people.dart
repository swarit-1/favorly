import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/tokens.dart';
import 'buttons.dart';

class Avatar extends StatelessWidget {
  const Avatar(this.member, {super.key, this.size = 32, this.onAccent = false});

  final Member member;
  final double size;
  final bool onAccent;

  static (Color, Color) colorsFor(MemberTint tint) => switch (tint) {
        MemberTint.blue => (FColors.blueTint, FColors.blue),
        MemberTint.green => (FColors.successTint, FColors.success),
        MemberTint.amber => (FColors.attentionTint, FColors.attention),
        MemberTint.plum => (FColors.plumTint, FColors.plum),
      };

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = onAccent ? (FColors.canvas, FColors.blue) : colorsFor(member.tint);
    return Semantics(
      label: member.name,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Text(
          member.initials,
          style: TextStyle(
            fontFamily: FType.family,
            fontSize: size * 0.38,
            fontWeight: FontWeight.w700,
            color: fg,
            letterSpacing: -0.3,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// Requester tag: avatar plus first name in a soft pill.
class MemberChip extends StatelessWidget {
  const MemberChip(
    this.member, {
    super.key,
    this.label,
    this.selected = false,
    this.onTap,
  });

  final Member member;
  final String? label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? FColors.blueTint : FColors.surface;
    final child = Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Avatar(member, size: 20),
          const SizedBox(width: 6),
          Text(
            label ?? member.firstName,
            style: FType.captionStrong.copyWith(
              color: selected ? FColors.blue : FColors.ink,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(FRadius.pill),
        ),
        child: child,
      );
    }
    return Material(
      color: bg,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: child),
    );
  }
}

/// Minus / value / plus. Each control has a 48pt tap target.
class QtyStepper extends StatelessWidget {
  const QtyStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 30,
    this.step = 1,
    this.format,
    this.semanticLabel,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final int step;
  final String Function(int)? format;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final text = format?.call(value) ?? '$value';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FIconButton(
          icon: CupertinoIcons.minus,
          label: 'Decrease ${semanticLabel ?? ''}'.trim(),
          filled: true,
          size: 36,
          iconSize: 16,
          onPressed: value - step >= min ? () => onChanged(value - step) : null,
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 56),
          child: Text(text, textAlign: TextAlign.center, style: FType.money),
        ),
        FIconButton(
          icon: CupertinoIcons.plus,
          label: 'Increase ${semanticLabel ?? ''}'.trim(),
          filled: true,
          size: 36,
          iconSize: 16,
          onPressed: value + step <= max ? () => onChanged(value + step) : null,
        ),
      ],
    );
  }
}
