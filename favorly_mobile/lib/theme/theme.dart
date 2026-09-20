import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildFavorlyTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: FColors.blue,
    onPrimary: FColors.onAccent,
    secondary: FColors.blue,
    onSecondary: FColors.onAccent,
    error: FColors.critical,
    onError: FColors.onAccent,
    surface: FColors.canvas,
    onSurface: FColors.ink,
    surfaceContainerHighest: FColors.surface,
    onSurfaceVariant: FColors.inkSecondary,
    outline: FColors.hairlineStrong,
    outlineVariant: FColors.hairline,
  );

  const textTheme = TextTheme(
    displayLarge: FType.display,
    headlineLarge: FType.title,
    headlineMedium: FType.heading,
    titleLarge: FType.heading,
    titleMedium: FType.subheading,
    titleSmall: FType.bodySmallStrong,
    bodyLarge: FType.body,
    bodyMedium: FType.bodySmall,
    bodySmall: FType.caption,
    labelLarge: FType.button,
    labelMedium: FType.captionStrong,
    labelSmall: FType.eyebrow,
  );

  final fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(FRadius.md),
    borderSide: BorderSide.none,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: FType.family,
    textTheme: textTheme,
    scaffoldBackgroundColor: FColors.canvas,
    canvasColor: FColors.canvas,
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: FColors.ink.withValues(alpha: 0.06),
    hoverColor: FColors.ink.withValues(alpha: 0.03),
    focusColor: FColors.blue.withValues(alpha: 0.12),
    dividerTheme: const DividerThemeData(
      color: FColors.hairline,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: FColors.canvas,
      foregroundColor: FColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      titleTextStyle: FType.subheading,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: FColors.surface,
      border: fieldBorder,
      enabledBorder: fieldBorder,
      disabledBorder: fieldBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FRadius.md),
        borderSide: const BorderSide(color: FColors.blue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FRadius.md),
        borderSide: const BorderSide(color: FColors.critical, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FRadius.md),
        borderSide: const BorderSide(color: FColors.critical, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: FType.body.copyWith(color: FColors.inkTertiary),
      errorStyle: FType.caption.copyWith(color: FColors.critical),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: FColors.ink,
      contentTextStyle: FType.bodySmallStrong.copyWith(color: FColors.onAccent),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FRadius.md),
      ),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actionTextColor: const Color(0xFF8FC1FF),
      elevation: 0,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: FColors.canvas,
      modalBackgroundColor: FColors.canvas,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: FColors.hairlineStrong,
      dragHandleSize: Size(40, 4),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(FRadius.xl)),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.fuchsia: CupertinoPageTransitionsBuilder(),
      },
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(FColors.canvas),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? FColors.blue
            : FColors.hairlineStrong,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: FColors.blue,
      selectionColor: FColors.blueTintStrong,
      selectionHandleColor: FColors.blue,
    ),
    cupertinoOverrideTheme: const CupertinoThemeData(
      primaryColor: FColors.blue,
      brightness: Brightness.light,
      textTheme: CupertinoTextThemeData(
        textStyle: FType.body,
        actionTextStyle: FType.bodyStrong,
        pickerTextStyle: FType.body,
        dateTimePickerTextStyle: FType.body,
      ),
    ),
  );
}
