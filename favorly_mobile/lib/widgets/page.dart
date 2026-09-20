import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'buttons.dart';

/// 52pt bar: back chevron, centered title, optional trailing control.
class FTopBar extends StatelessWidget {
  const FTopBar({
    super.key,
    this.title,
    this.showBack = true,
    this.onBack,
    this.trailing,
  });

  final String? title;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: showBack
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: FIconButton(
                        icon: CupertinoIcons.back,
                        label: 'Back',
                        onPressed:
                            onBack ?? () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  )
                : null,
          ),
          Expanded(
            child: Center(
              child: title == null
                  ? const SizedBox.shrink()
                  : Text(
                      title!,
                      style: FType.subheading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ),
          SizedBox(
            width: 64,
            child: trailing == null
                ? null
                : Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: trailing,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class PageTitle extends StatelessWidget {
  const PageTitle(
    this.title, {
    super.key,
    this.subtitle,
    this.padding = const EdgeInsets.only(top: 4, bottom: 22),
  });

  final String title;
  final String? subtitle;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: FType.title),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, style: FType.body.copyWith(color: FColors.inkSecondary)),
          ],
        ],
      ),
    );
  }
}

/// Standard screen: optional top bar, scrolling content, sticky bottom
/// actions that stay above the keyboard and the home indicator.
class FavorlyPage extends StatelessWidget {
  const FavorlyPage({
    super.key,
    this.topBar,
    required this.children,
    this.bottom,
    this.padding = const EdgeInsets.fromLTRB(20, 4, 20, 32),
    this.controller,
    this.background = FColors.canvas,
  });

  final Widget? topBar;
  final List<Widget> children;
  final Widget? bottom;
  final EdgeInsets padding;
  final ScrollController? controller;
  final Color background;

  @override
  Widget build(BuildContext context) {
    // With a bottom bar the Scaffold strips the body's bottom safe area, so
    // only pad the list when the bar is absent.
    final bottomInset = bottom == null ? MediaQuery.paddingOf(context).bottom : 0.0;
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ?topBar,
            Expanded(
              child: ListView(
                controller: controller,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: padding.copyWith(bottom: padding.bottom + bottomInset),
                children: children,
              ),
            ),
          ],
        ),
      ),
      // Living in the Scaffold's bottom slot keeps toasts above the actions
      // instead of on top of them.
      bottomNavigationBar: bottom == null ? null : BottomBar(child: bottom!),
    );
  }
}

/// Sticky action area. Rises above the keyboard and the home indicator.
class BottomBar extends StatelessWidget {
  const BottomBar({super.key, required this.child, this.divider = true});

  final Widget child;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FColors.canvas,
        border: divider ? const Border(top: BorderSide(color: FColors.hairline)) : null,
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Stacks bottom buttons with a consistent gap.
class BottomActions extends StatelessWidget {
  const BottomActions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final kids = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      kids.add(children[i]);
      if (i < children.length - 1) kids.add(const SizedBox(height: 8));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: kids,
    );
  }
}

Future<T?> showFavorlySheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isDismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    builder: builder,
  );
}

/// Sheet content that scrolls when tall and rises above the keyboard.
class SheetBody extends StatelessWidget {
  const SheetBody({super.key, required this.children, this.bottom});

  final List<Widget> children;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: ListView(
              shrinkWrap: true,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: children,
            ),
          ),
          if (bottom != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: bottom,
            ),
        ],
      ),
    );
  }
}

class SheetTitle extends StatelessWidget {
  const SheetTitle(this.title, {super.key, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: FType.heading),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: FType.bodySmall.copyWith(color: FColors.inkSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

/// On wide screens the app renders inside a phone-width column so one layout
/// serves mobile and web.
class WebFrame extends StatelessWidget {
  const WebFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) return child;
        return ColoredBox(
          color: FColors.surface,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: FColors.canvas,
                  border: Border.symmetric(
                    vertical: BorderSide(color: FColors.hairline),
                  ),
                ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
