import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'buttons.dart';

/// Hairline-bordered group. Rows are separated by inset dividers.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.children,
    this.color = FColors.canvas,
    this.outlined = true,
    this.dividers = true,
    this.dividerIndent = 16,
    this.padding = EdgeInsets.zero,
    this.radius = FRadius.lg,
  });

  final List<Widget> children;
  final Color color;
  final bool outlined;
  final bool dividers;
  final double dividerIndent;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final kids = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      kids.add(children[i]);
      if (dividers && i < children.length - 1) {
        kids.add(Divider(indent: dividerIndent));
      }
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: outlined ? Border.all(color: FColors.hairline) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: kids,
      ),
    );
  }
}

/// One line inside a [Panel]: optional leading, title, subtitle, and a value
/// or trailing widget. Tappable rows get a chevron.
class PanelRow extends StatelessWidget {
  const PanelRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.value,
    this.onTap,
    this.chevron,
    this.titleStyle,
    this.subtitleStyle,
    this.background,
    this.minHeight = 56,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final String? value;
  final VoidCallback? onTap;
  final bool? chevron;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final Color? background;
  final double minHeight;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final showChevron = chevron ?? (onTap != null);
    final row = Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: titleStyle ?? FType.bodyStrong),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: subtitleStyle ??
                      FType.bodySmall.copyWith(color: FColors.inkSecondary),
                ),
              ],
            ],
          ),
        ),
        if (value != null) ...[
          const SizedBox(width: 12),
          Text(value!, style: FType.money.copyWith(color: FColors.inkSecondary)),
        ],
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        if (showChevron) ...[
          const SizedBox(width: 6),
          const Icon(CupertinoIcons.chevron_right, size: 18, color: FColors.inkTertiary),
        ],
      ],
    );
    final content = Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: padding,
      alignment: Alignment.centerLeft,
      child: row,
    );
    if (onTap == null) {
      return background == null ? content : ColoredBox(color: background!, child: content);
    }
    return Material(
      color: background ?? Colors.transparent,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

/// A tappable surface with press feedback and button semantics, for cards
/// that are not Material buttons.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.label,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? label;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.98 : 1,
          duration: FMotion.quick,
          curve: FMotion.curve,
          child: widget.child,
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.action,
    this.onAction,
    this.padding = const EdgeInsets.only(top: 28, bottom: 10),
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(child: Text(title, style: FType.subheading)),
          if (action != null) FTextButton(action!, onPressed: onAction),
        ],
      ),
    );
  }
}

/// Small uppercase label for store sections and similar groupings.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.label, {super.key, this.icon, this.color = FColors.inkSecondary});

  final String label;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
        ],
        Text(label.toUpperCase(), style: FType.eyebrow.copyWith(color: color)),
      ],
    );
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.hint});

  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(text, style: FType.bodySmallStrong),
          if (hint != null) ...[
            const SizedBox(width: 6),
            Text(hint!, style: FType.caption.copyWith(color: FColors.inkTertiary)),
          ],
        ],
      ),
    );
  }
}

enum NoticeKind { info, success, attention, critical, neutral }

/// Tinted strip with an icon and one line of text. Never the only carrier of
/// meaning: the icon and the words say it too.
class Notice extends StatelessWidget {
  const Notice(
    this.text, {
    super.key,
    this.kind = NoticeKind.info,
    this.icon,
    this.action,
    this.onAction,
  });

  final String text;
  final NoticeKind kind;
  final IconData? icon;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, IconData fallback) = switch (kind) {
      NoticeKind.info => (FColors.blueTint, FColors.blue, CupertinoIcons.info_circle_fill),
      NoticeKind.success => (FColors.successTint, FColors.success, CupertinoIcons.checkmark_circle_fill),
      NoticeKind.attention => (FColors.attentionTint, FColors.attention, CupertinoIcons.exclamationmark_circle_fill),
      NoticeKind.critical => (FColors.criticalTint, FColors.critical, CupertinoIcons.xmark_circle_fill),
      NoticeKind.neutral => (FColors.surface, FColors.inkSecondary, CupertinoIcons.sparkles),
    };
    return Container(
      padding: EdgeInsets.fromLTRB(14, 12, action == null ? 14 : 6, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(FRadius.md),
      ),
      child: Row(
        children: [
          Icon(icon ?? fallback, size: 20, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: FType.bodySmallStrong.copyWith(color: FColors.ink)),
          ),
          if (action != null) FTextButton(action!, onPressed: onAction, color: fg),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: FColors.surface,
        borderRadius: BorderRadius.circular(FRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(color: FColors.canvas, shape: BoxShape.circle),
            child: Icon(icon, size: 24, color: FColors.blue),
          ),
          const SizedBox(height: 16),
          Text(title, style: FType.heading),
          const SizedBox(height: 6),
          Text(body, style: FType.body.copyWith(color: FColors.inkSecondary)),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}

class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.value,
    this.height = 6,
    this.color = FColors.blue,
    this.label,
  });

  final double value;
  final double height;
  final Color color;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    return Semantics(
      label: label,
      value: '${(clamped * 100).round()} percent',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FRadius.pill),
        child: SizedBox(
          height: height,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: clamped),
            duration: FMotion.slow,
            curve: FMotion.curve,
            builder: (_, v, _) => Stack(
              fit: StackFit.expand,
              alignment: Alignment.centerLeft,
              children: [
                const ColoredBox(color: FColors.surfacePressed),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: v,
                  child: ColoredBox(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Label/value line for totals.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow(
    this.label,
    this.value, {
    super.key,
    this.strong = false,
    this.valueColor,
    this.padding = const EdgeInsets.symmetric(vertical: 6),
  });

  final String label;
  final String value;
  final bool strong;
  final Color? valueColor;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: strong
                  ? FType.bodyStrong
                  : FType.bodySmall.copyWith(color: FColors.inkSecondary),
            ),
          ),
          Text(
            value,
            style: strong
                ? FType.money.copyWith(fontSize: 20, fontWeight: FontWeight.w700)
                : FType.money.copyWith(color: valueColor ?? FColors.ink),
          ),
        ],
      ),
    );
  }
}

enum PillKind { neutral, info, success, attention, critical }

class StatusPill extends StatelessWidget {
  const StatusPill(
    this.label, {
    super.key,
    this.kind = PillKind.neutral,
    this.icon,
    this.onAccent = false,
  });

  final String label;
  final PillKind kind;
  final IconData? icon;
  final bool onAccent;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = onAccent
        ? (FColors.canvas.withValues(alpha: 0.2), FColors.canvas)
        : switch (kind) {
            PillKind.neutral => (FColors.surface, FColors.inkSecondary),
            PillKind.info => (FColors.blueTint, FColors.blue),
            PillKind.success => (FColors.successTint, FColors.success),
            PillKind.attention => (FColors.attentionTint, FColors.attention),
            PillKind.critical => (FColors.criticalTint, FColors.critical),
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(FRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label, style: FType.captionStrong.copyWith(color: fg)),
        ],
      ),
    );
  }
}
