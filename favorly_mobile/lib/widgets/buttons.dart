import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum FButtonKind { primary, secondary, tertiary, onAccent, destructive }

/// Meta-style pill button. 52pt tall by default, full width on mobile, with a
/// small press scale so taps feel physical.
class FButton extends StatefulWidget {
  const FButton({
    super.key,
    required this.label,
    this.onPressed,
    this.kind = FButtonKind.primary,
    this.icon,
    this.expand = true,
    this.compact = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final FButtonKind kind;
  final IconData? icon;
  final bool expand;
  final bool compact;
  final bool busy;

  @override
  State<FButton> createState() => _FButtonState();
}

class _FButtonState extends State<FButton> {
  final _states = WidgetStatesController();
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _states.addListener(_sync);
  }

  void _sync() {
    final pressed = _states.value.contains(WidgetState.pressed);
    if (pressed != _pressed && mounted) setState(() => _pressed = pressed);
  }

  @override
  void dispose() {
    _states.removeListener(_sync);
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, Color pressedBg) = switch (widget.kind) {
      FButtonKind.primary => (FColors.blue, FColors.onAccent, FColors.bluePressed),
      FButtonKind.secondary => (FColors.surface, FColors.ink, FColors.surfacePressed),
      FButtonKind.tertiary => (Colors.transparent, FColors.blue, FColors.blueTint),
      FButtonKind.onAccent => (FColors.canvas, FColors.blue, FColors.blueTint),
      FButtonKind.destructive => (Colors.transparent, FColors.critical, FColors.criticalTint),
    };
    final filled = widget.kind == FButtonKind.primary ||
        widget.kind == FButtonKind.secondary ||
        widget.kind == FButtonKind.onAccent;
    final height = widget.compact ? 44.0 : 52.0;
    final focusRing = widget.kind == FButtonKind.primary ? FColors.ink : FColors.blue;

    final style = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) {
          return filled ? FColors.surface : Colors.transparent;
        }
        if (s.contains(WidgetState.pressed)) return pressedBg;
        return bg;
      }),
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled) ? FColors.inkDisabled : fg,
      ),
      iconColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled) ? FColors.inkDisabled : fg,
      ),
      overlayColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.hovered)
            ? fg.withValues(alpha: 0.06)
            : Colors.transparent,
      ),
      side: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.focused)
            ? BorderSide(color: focusRing, width: 2)
            : BorderSide.none,
      ),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      minimumSize: WidgetStatePropertyAll(
        Size(widget.expand ? double.infinity : 0, height),
      ),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: widget.compact ? 16 : 22),
      ),
      textStyle: WidgetStatePropertyAll(
        widget.compact ? FType.bodySmallStrong : FType.button,
      ),
      tapTargetSize: MaterialTapTargetSize.padded,
      splashFactory: NoSplash.splashFactory,
      animationDuration: FMotion.quick,
    );

    final Widget child;
    if (widget.busy) {
      child = SizedBox(
        height: 20,
        width: 20,
        child: CupertinoActivityIndicator(color: fg, radius: 9),
      );
    } else if (widget.icon != null) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(widget.icon, size: widget.compact ? 18 : 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      );
    } else {
      child = Text(
        widget.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      );
    }

    final VoidCallback? onPressed =
        widget.busy ? () {} : widget.onPressed;

    return AnimatedScale(
      scale: _pressed ? 0.97 : 1,
      duration: FMotion.quick,
      curve: FMotion.curve,
      child: FilledButton(
        onPressed: onPressed,
        statesController: _states,
        style: style,
        child: child,
      ),
    );
  }
}

/// Circular icon button with a 44pt target. `label` is read by screen readers.
class FIconButton extends StatelessWidget {
  const FIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.filled = false,
    this.color = FColors.ink,
    this.size = 44,
    this.iconSize = 22,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final Color color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: label,
      iconSize: iconSize,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        foregroundColor: color,
        disabledForegroundColor: FColors.inkDisabled,
        backgroundColor: filled ? FColors.surface : Colors.transparent,
        disabledBackgroundColor: filled ? FColors.surface : Colors.transparent,
        highlightColor:
            filled ? FColors.surfacePressed : FColors.ink.withValues(alpha: 0.06),
        minimumSize: Size(size, size),
        fixedSize: Size(size, size),
        padding: EdgeInsets.zero,
        shape: const CircleBorder(),
        tapTargetSize: size >= 44
            ? MaterialTapTargetSize.shrinkWrap
            : MaterialTapTargetSize.padded,
        splashFactory: NoSplash.splashFactory,
      ),
    );
  }
}

/// Small inline text action, e.g. "Edit" next to a section title.
class FTextButton extends StatelessWidget {
  const FTextButton(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.color = FColors.blue,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        disabledForegroundColor: FColors.inkDisabled,
        textStyle: FType.bodySmallStrong,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(44, 36),
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: const StadiumBorder(),
        splashFactory: NoSplash.splashFactory,
      ),
      child: icon == null
          ? Text(label)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16),
                const SizedBox(width: 6),
                Text(label),
              ],
            ),
    );
  }
}
