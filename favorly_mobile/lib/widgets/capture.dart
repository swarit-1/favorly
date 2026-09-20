import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/tokens.dart';
import '../util/format.dart';

/// Camera stand-in. The real app swaps [child] for a live preview; the
/// brackets, hint, and reading state stay the same.
class Viewfinder extends StatelessWidget {
  const Viewfinder({
    super.key,
    required this.hint,
    this.child,
    this.aspectRatio = 4 / 5,
    this.background = const Color(0xFF223440),
    this.status,
  });

  final String hint;
  final Widget? child;
  final double aspectRatio;
  final Color background;

  /// When set, the frame dims and shows this as a reading state.
  final String? status;

  @override
  Widget build(BuildContext context) {
    final reading = status != null;
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(FRadius.xl),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.2),
                  radius: 1.1,
                  colors: [
                    Colors.white.withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            ?child,
            const IgnorePointer(child: CustomPaint(painter: _BracketsPainter())),
            if (reading) ...[
              const ColoredBox(color: Color(0xB3172530)),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CupertinoActivityIndicator(color: Colors.white, radius: 12),
                    const SizedBox(height: 12),
                    Text(
                      status!,
                      style: FType.bodySmallStrong.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ] else
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xCC1C2B33),
                      borderRadius: BorderRadius.circular(FRadius.pill),
                    ),
                    child: Text(
                      hint,
                      textAlign: TextAlign.center,
                      style: FType.captionStrong.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BracketsPainter extends CustomPainter {
  const _BracketsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const inset = 16.0;
    const len = 22.0;
    final w = size.width;
    final h = size.height;
    void corner(double x, double y, double dx, double dy) {
      canvas.drawLine(Offset(x, y), Offset(x + dx * len, y), paint);
      canvas.drawLine(Offset(x, y), Offset(x, y + dy * len), paint);
    }

    corner(inset, inset, 1, 1);
    corner(w - inset, inset, -1, 1);
    corner(inset, h - inset, 1, -1);
    corner(w - inset, h - inset, -1, -1);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A handwritten list, as the camera would see it.
class PaperNote extends StatelessWidget {
  const PaperNote({super.key, required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Transform.rotate(
        angle: -0.06,
        child: Container(
          width: 190,
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 26),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFDF5),
            borderRadius: BorderRadius.circular(3),
            boxShadow: const [
              BoxShadow(color: Color(0x55000000), blurRadius: 24, offset: Offset(0, 12)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    l,
                    style: const TextStyle(
                      fontFamily: FType.handwriting,
                      fontSize: 27,
                      height: 1.15,
                      color: Color(0xFF2B3A6B),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A store shelf with price tags, as the camera would see it.
class MockShelf extends StatelessWidget {
  const MockShelf({super.key, required this.prices});

  final List<double> prices;

  @override
  Widget build(BuildContext context) {
    final rows = <List<double>>[];
    for (var i = 0; i < prices.length; i += 3) {
      rows.add(prices.sublist(i, math.min(i + 3, prices.length)));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 26, 14, 46),
      child: Column(
        children: [for (final r in rows) Expanded(child: _ShelfRow(prices: r))],
      ),
    );
  }
}

class _ShelfRow extends StatelessWidget {
  const _ShelfRow({required this.prices});

  final List<double> prices;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final p in prices)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.only(top: 10),
                            alignment: Alignment.bottomCenter,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xFFF7EBB8), Color(0xFFE9D68E)],
                              ),
                            ),
                            child: Container(
                              height: 12,
                              margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2F5FAE),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            money(p),
                            style: FType.captionStrong.copyWith(
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 9,
          decoration: BoxDecoration(
            color: const Color(0xFFB9B3A9),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

/// A printed receipt, as the camera would see it.
class MockReceipt extends StatelessWidget {
  const MockReceipt({super.key, required this.split});

  final ReceiptSplit split;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontFamily: FType.family,
      fontSize: 10.5,
      height: 1.5,
      color: Color(0xFF2B3238),
      fontFeatures: [FontFeature.tabularFigures()],
    );
    final bold = style.copyWith(fontWeight: FontWeight.w700);
    Widget line(String a, String b, {bool strong = false}) => Row(
          children: [
            Expanded(
              child: Text(
                a,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: strong ? bold : style,
              ),
            ),
            const SizedBox(width: 8),
            Text(b, style: strong ? bold : style),
          ],
        );
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          width: 214,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          decoration: const BoxDecoration(
            color: Color(0xFFFCFCFA),
            boxShadow: [
              BoxShadow(color: Color(0x55000000), blurRadius: 24, offset: Offset(0, 12)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                split.store.toUpperCase(),
                style: bold.copyWith(letterSpacing: 1.2, fontSize: 12),
              ),
              Text(
                'THANKS FOR SHOPPING WITH US',
                style: style.copyWith(fontSize: 8.5, letterSpacing: 0.4),
              ),
              const SizedBox(height: 8),
              for (final l in split.lines) line(l.description, l.total.toStringAsFixed(2)),
              const SizedBox(height: 4),
              Text(
                '— — — — — — — — — — — —',
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: style.copyWith(color: const Color(0xFF9AA3AB)),
              ),
              line('SUBTOTAL', split.subtotal.toStringAsFixed(2)),
              line('TAX', split.tax.toStringAsFixed(2)),
              line('TOTAL', split.total.toStringAsFixed(2), strong: true),
            ],
          ),
        ),
      ),
    );
  }
}

/// Five bars that move while the mic is open.
class ListeningWave extends StatefulWidget {
  const ListeningWave({
    super.key,
    this.color = FColors.blue,
    this.bars = 5,
    this.height = 36,
    this.active = true,
  });

  final Color color;
  final int bars;
  final double height;
  final bool active;

  @override
  State<ListeningWave> createState() => _ListeningWaveState();
}

class _ListeningWaveState extends State<ListeningWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant ListeningWave oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) _controller.repeat();
    if (!widget.active && _controller.isAnimating) _controller.stop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context) || !widget.active;
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < widget.bars; i++)
            Container(
              width: 5,
              height: widget.height *
                  (still
                      ? 0.5
                      : 0.3 +
                          0.7 *
                              (0.5 +
                                  0.5 *
                                      math.sin(2 *
                                          math.pi *
                                          (_controller.value + i / widget.bars)))),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(FRadius.pill),
              ),
            ),
        ],
      ),
    );
  }
}

/// Skeleton rows shaped like the list they stand in for.
class ShimmerRows extends StatefulWidget {
  const ShimmerRows({super.key, this.count = 4, this.rowHeight = 64});

  final int count;
  final double rowHeight;

  @override
  State<ShimmerRows> createState() => _ShimmerRowsState();
}

class _ShimmerRowsState extends State<ShimmerRows>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _bar(double width, double height) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: FColors.canvas.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(4),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) {
        final t = reduce ? 0.5 : _controller.value;
        return Column(
          children: [
            for (var i = 0; i < widget.count; i++)
              Container(
                height: widget.rowHeight,
                margin: EdgeInsets.only(bottom: i == widget.count - 1 ? 0 : 10),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(FRadius.lg),
                  gradient: LinearGradient(
                    begin: Alignment(-1.5 + t * 3, 0),
                    end: Alignment(-0.5 + t * 3, 0),
                    colors: const [FColors.surface, FColors.surfacePressed, FColors.surface],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bar(140, 12),
                    const SizedBox(height: 8),
                    _bar(220, 10),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Ring that drains as a substitution prompt runs out.
class CountdownRing extends StatefulWidget {
  const CountdownRing({
    super.key,
    required this.expiresAt,
    required this.window,
    this.size = 48,
    this.onExpired,
  });

  final DateTime expiresAt;
  final Duration window;
  final double size;
  final VoidCallback? onExpired;

  @override
  State<CountdownRing> createState() => _CountdownRingState();
}

class _CountdownRingState extends State<CountdownRing> {
  Timer? _timer;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    setState(() {});
    final left = widget.expiresAt.difference(DateTime.now());
    if (left.isNegative && !_fired) {
      _fired = true;
      widget.onExpired?.call();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.expiresAt.difference(DateTime.now());
    final fraction =
        (left.inMilliseconds / widget.window.inMilliseconds).clamp(0.0, 1.0);
    final color = left.inSeconds < 30 ? FColors.attention : FColors.blue;
    return Semantics(
      label: '${countdown(left)} left',
      excludeSemantics: true,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _RingPainter(fraction: fraction, color: color),
          child: Center(
            child: Text(
              countdown(left),
              style: FType.captionStrong.copyWith(
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(3);
    final track = Paint()
      ..color = FColors.hairline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, track);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * fraction, false, arc);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction || oldDelegate.color != color;
}

/// Success mark that scales in once.
class CheckBurst extends StatelessWidget {
  const CheckBurst({super.key, this.size = 88});

  final double size;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final mark = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: FColors.successTint, shape: BoxShape.circle),
      child: Icon(CupertinoIcons.checkmark_alt, size: size * 0.5, color: FColors.success),
    );
    if (reduce) return mark;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutBack,
      builder: (_, t, child) => Transform.scale(
        scale: 0.6 + 0.4 * t,
        child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
      ),
      child: mark,
    );
  }
}

/// Large round mic control for voice intake.
class MicButton extends StatelessWidget {
  const MicButton({super.key, required this.onPressed, this.listening = false});

  final VoidCallback? onPressed;
  final bool listening;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: listening ? 'Stop listening' : 'Start listening',
      child: Material(
        color: listening ? FColors.critical : FColors.blue,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 76,
            height: 76,
            child: Icon(
              listening ? CupertinoIcons.stop_fill : CupertinoIcons.mic_fill,
              color: Colors.white,
              size: 30,
            ),
          ),
        ),
      ),
    );
  }
}
