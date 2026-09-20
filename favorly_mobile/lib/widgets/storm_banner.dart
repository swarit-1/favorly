import 'dart:math' as math;
import 'package:flutter/cupertino.dart';

import '../theme/tokens.dart';

/// Displays a storm mode banner when active.
/// Shows animated snowflakes and "Storm Mode" messaging.
class StormBanner extends StatelessWidget {
  const StormBanner({
    required this.onDismiss,
    super.key,
  });

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FSpace.md),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1a2a3a), Color(0xFF0d1f2d)],
        ),
        borderRadius: BorderRadius.circular(FRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'STORM MODE ACTIVE',
                    style: FType.eyebrow.copyWith(
                      color: const Color(0xFF4dd0ff),
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '7 neighbors covered',
                    style: FType.title.copyWith(color: FColors.canvas),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Carries count 2x karma',
                    style: FType.body.copyWith(color: const Color(0xFFb3e5fc)),
                  ),
                ],
              ),
              Icon(
                CupertinoIcons.cloud_snow_fill,
                color: const Color(0xFF4dd0ff),
                size: 48,
              ),
            ],
          ),
          const SizedBox(height: FSpace.md),
          SizedBox(
            height: 60,
            child: _SnowfallEffect(),
          ),
        ],
      ),
    );
  }
}

/// Animated snowflake particles falling down.
class _SnowfallEffect extends StatefulWidget {
  const _SnowfallEffect();

  @override
  State<_SnowfallEffect> createState() => _SnowfallEffectState();
}

class _SnowfallEffectState extends State<_SnowfallEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _SnowfallPainter(_controller.value),
          size: const Size(double.infinity, 60),
        );
      },
    );
  }
}

/// Paints falling snowflake particles.
class _SnowfallPainter extends CustomPainter {
  final double progress;

  _SnowfallPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF4dd0ff).withOpacity(0.6)
      ..strokeWidth = 2;

    // Draw snowflakes at different positions
    final snowflakes = [
      (x: 0.2, y: 0.3),
      (x: 0.4, y: 0.6),
      (x: 0.6, y: 0.1),
      (x: 0.8, y: 0.5),
      (x: 0.1, y: 0.8),
      (x: 0.9, y: 0.2),
    ];

    for (final flake in snowflakes) {
      final dx = size.width * flake.x;
      final dy = size.height * ((flake.y + progress) % 1.0);

      // Draw a simple snowflake shape
      _drawSnowflake(canvas, paint, dx, dy, 4);
    }
  }

  void _drawSnowflake(Canvas canvas, Paint paint, double x, double y, double size) {
    // Draw 6-pointed star
    for (int i = 0; i < 6; i++) {
      final angle = (i * 60) * math.pi / 180;
      final x1 = x + size * 0.5 * math.cos(angle);
      final y1 = y + size * 0.5 * math.sin(angle);
      canvas.drawLine(Offset(x, y), Offset(x1, y1), paint);
    }
  }

  @override
  bool shouldRepaint(_SnowfallPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
