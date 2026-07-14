import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Red flash + lightning bolts shown when a skill check is missed.
class ShockOverlay extends StatefulWidget {
  const ShockOverlay({super.key});

  @override
  State<ShockOverlay> createState() => _ShockOverlayState();
}

class _ShockOverlayState extends State<ShockOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final v = _ctrl.value;
          final flash = (1 - v) * (0.5 + 0.5 * sin(v * 40));
          return Stack(
            fit: StackFit.expand,
            children: [
              Container(
                  color: AppColors.blood
                      .withValues(alpha: (flash * 0.35).clamp(0.0, 0.35))),
              CustomPaint(
                painter: _LightningPainter(progress: v),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LightningPainter extends CustomPainter {
  final double progress;
  _LightningPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress > 0.7) return;
    final rand = Random((progress * 12).floor());
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.white.withValues(alpha: 0.8 * (1 - progress));
    for (int i = 0; i < 3; i++) {
      final x0 = rand.nextDouble() * size.width;
      final path = Path()..moveTo(x0, 0);
      var x = x0;
      var y = 0.0;
      while (y < size.height) {
        y += 30 + rand.nextDouble() * 60;
        x += (rand.nextDouble() - 0.5) * 90;
        path.lineTo(x, y);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LightningPainter old) => true;
}

/// Golden burst + message shown when decoding reaches 100%.
class CompletedOverlay extends StatefulWidget {
  final String machineName;
  const CompletedOverlay({super.key, required this.machineName});

  @override
  State<CompletedOverlay> createState() => _CompletedOverlayState();
}

class _CompletedOverlayState extends State<CompletedOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final List<_Ray> _rays = [];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
    final rand = Random(3);
    for (int i = 0; i < 24; i++) {
      _rays.add(_Ray(
        angle: rand.nextDouble() * 2 * pi,
        length: 0.4 + rand.nextDouble() * 0.6,
        width: 1 + rand.nextDouble() * 3,
        speed: 0.5 + rand.nextDouble(),
      ));
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) => CustomPaint(
              painter: _RaysPainter(t: _ctrl.value, rays: _rays),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 340),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutBack,
                  builder: (context, v, child) => Transform.scale(
                    scale: v,
                    child: Opacity(opacity: v.clamp(0, 1), child: child),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'DECODED',
                        style: TextStyle(
                          fontSize: 46,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 12,
                          color: AppColors.amber,
                          shadows: [
                            Shadow(
                              color: AppColors.amber.withValues(alpha: 0.8),
                              blurRadius: 24,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${widget.machineName} の解読が完了しました',
                        style: const TextStyle(
                          color: AppColors.bone,
                          fontSize: 16,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Ray {
  final double angle, length, width, speed;
  _Ray({
    required this.angle,
    required this.length,
    required this.width,
    required this.speed,
  });
}

class _RaysPainter extends CustomPainter {
  final double t;
  final List<_Ray> rays;
  _RaysPainter({required this.t, required this.rays});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.shortestSide * 0.5;

    // pulsing golden glow
    final pulse = 0.5 + 0.5 * sin(t * 2 * pi);
    canvas.drawCircle(
      center,
      maxR * 0.5,
      Paint()
        ..color = AppColors.amber.withValues(alpha: 0.10 + pulse * 0.08)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, maxR * 0.25),
    );

    // rotating light rays
    for (final ray in rays) {
      final a = ray.angle + t * 2 * pi * 0.08 * ray.speed;
      final start = center + Offset(cos(a), sin(a)) * maxR * 0.25;
      final end = center + Offset(cos(a), sin(a)) * maxR * (0.35 + ray.length);
      canvas.drawLine(
        start,
        end,
        Paint()
          ..strokeWidth = ray.width
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(colors: [
            AppColors.amber.withValues(alpha: 0.5),
            Colors.transparent,
          ]).createShader(Rect.fromPoints(start, end)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RaysPainter old) => true;
}
