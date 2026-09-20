import 'package:flutter/material.dart';

/// Color tokens.
///
/// Neutrals and the accent follow Meta's public brand palette so the app reads
/// as native next to Meta's own surfaces: cobalt #0064E0, bright blue #0082FB,
/// ink #1C2B33 and the soft surface #F1F4F7. Contrast figures in the comments
/// are measured against the surface each token is meant to sit on.
abstract final class FColors {
  // Surfaces
  static const canvas = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF1F4F7);
  static const surfacePressed = Color(0xFFE3E8ED);
  static const hairline = Color(0xFFDEE3E9);
  static const hairlineStrong = Color(0xFFCED0D4);
  static const scrim = Color(0x991C2B33);

  // Content
  static const ink = Color(0xFF1C2B33); // 13.9:1 on canvas
  static const inkSecondary = Color(0xFF465A69); // 7.2:1 on canvas
  static const inkTertiary = Color(0xFF5A6B7A); // 5.5:1 on canvas
  static const inkDisabled = Color(0xFFA5AFB8);
  static const onAccent = Color(0xFFFFFFFF);

  // Accent: Meta cobalt
  static const blue = Color(0xFF0064E0); // 5.4:1 on canvas, white on it 5.4:1
  static const bluePressed = Color(0xFF0457CB);
  static const blueBright = Color(0xFF0082FB); // gradient end only, never text
  static const blueTint = Color(0xFFE8F1FE); // blue text on it 4.8:1
  static const blueTintStrong = Color(0xFFD2E4FC);

  // Signals
  static const success = Color(0xFF1B7434); // 5.8:1 on canvas, 5.2:1 on tint
  static const successTint = Color(0xFFE6F5EA);
  static const attention = Color(0xFF9A5B00); // 5.4:1 on canvas, 4.9:1 on tint
  static const attentionIcon = Color(0xFFF2A918);
  static const attentionTint = Color(0xFFFFF4D6);
  static const critical = Color(0xFFE41E3F); // 4.6:1 on canvas
  static const criticalTint = Color(0xFFFDE8EC);
  static const plum = Color(0xFF6B4A99); // 6.9:1 on canvas
  static const plumTint = Color(0xFFF0E9F7);
}

/// Spacing scale, 4pt based.
abstract final class FSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;
}

/// Corner radii. Pills are Meta's signature shape for controls.
abstract final class FRadius {
  static const double pill = 100;
  static const double xl = 24;
  static const double lg = 18;
  static const double md = 12;
  static const double sm = 8;
}

/// Type scale.
///
/// Figtree is the closest open typeface to Meta's Optimistic: friendly,
/// geometric, with generous x-height. Body stays at 17pt, the mobile default.
abstract final class FType {
  static const family = 'Figtree';
  static const handwriting = 'Caveat';

  static const _tabular = <FontFeature>[FontFeature.tabularFigures()];

  static const display = TextStyle(
    fontFamily: family,
    fontSize: 34,
    height: 40 / 34,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
    color: FColors.ink,
    fontFeatures: _tabular,
  );
  static const title = TextStyle(
    fontFamily: family,
    fontSize: 28,
    height: 34 / 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: FColors.ink,
  );
  static const heading = TextStyle(
    fontFamily: family,
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: FColors.ink,
  );
  static const subheading = TextStyle(
    fontFamily: family,
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    color: FColors.ink,
  );
  static const body = TextStyle(
    fontFamily: family,
    fontSize: 17,
    height: 24 / 17,
    fontWeight: FontWeight.w400,
    color: FColors.ink,
  );
  static const bodyStrong = TextStyle(
    fontFamily: family,
    fontSize: 17,
    height: 24 / 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    color: FColors.ink,
  );
  static const bodySmall = TextStyle(
    fontFamily: family,
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w400,
    color: FColors.ink,
  );
  static const bodySmallStrong = TextStyle(
    fontFamily: family,
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w600,
    color: FColors.ink,
  );
  static const caption = TextStyle(
    fontFamily: family,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w500,
    color: FColors.ink,
  );
  static const captionStrong = TextStyle(
    fontFamily: family,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w600,
    color: FColors.ink,
  );
  static const eyebrow = TextStyle(
    fontFamily: family,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
    color: FColors.inkSecondary,
  );
  static const button = TextStyle(
    fontFamily: family,
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );
  static const money = TextStyle(
    fontFamily: family,
    fontSize: 17,
    height: 24 / 17,
    fontWeight: FontWeight.w600,
    color: FColors.ink,
    fontFeatures: _tabular,
  );
  static const moneySmall = TextStyle(
    fontFamily: family,
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w600,
    color: FColors.ink,
    fontFeatures: _tabular,
  );
}

/// Motion: brief, one curve, cancellable.
abstract final class FMotion {
  static const quick = Duration(milliseconds: 140);
  static const normal = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 420);
  static const curve = Curves.easeOutCubic;
  static const emphasized = Cubic(0.32, 0.72, 0, 1);
}
