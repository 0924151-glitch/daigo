import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The cipher machine itself: rotating gears, progress ring, glow.
/// This is the giant "hold here" element in the center of the screen.
class CipherMachine extends StatefulWidget {
  final double progress; // 0..100
  final bool holding;
  final bool completed;
  final bool sparkActive;

  const CipherMachine({
    super.key,
    required this.progress,
    required this.holding,
    required this.completed,
    required this.sparkActive,
  });

  @override
  State<CipherMachine> createState() => _CipherMachineState();
}

class _CipherMachineState extends State<CipherMachine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: const Duration(seconds: 8))
      ..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _spin,
        builder: (context, _) {
          // gears speed up while holding
          final speed = widget.holding ? 4.0 : (widget.completed ? 0.4 : 0.6);
          return CustomPaint(
            painter: _MachinePainter(
              t: _spin.value * 2 * pi * speed,
              progress: widget.progress / 100,
              holding: widget.holding,
              completed: widget.completed,
              spark: widget.sparkActive,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _MachinePainter extends CustomPainter {
  final double t;
  final double progress;
  final bool holding;
  final bool completed;
  final bool spark;

  _MachinePainter({
    required this.t,
    required this.progress,
    required this.holding,
    required this.completed,
    required this.spark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;

    final glowColor = completed
        ? AppColors.amber
        : (spark ? AppColors.violet : AppColors.cyan);

    // ---- outer glow ----
    final glowStrength = completed ? 0.5 : (holding ? 0.4 : 0.18);
    canvas.drawCircle(
      center,
      r * 0.98,
      Paint()
        ..color = glowColor.withValues(alpha: glowStrength)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.14),
    );

    // ---- machine body ----
    final body = Paint()
      ..shader = RadialGradient(colors: [
        const Color(0xFF1E1E2A),
        const Color(0xFF101018),
      ]).createShader(Rect.fromCircle(center: center, radius: r * 0.88));
    canvas.drawCircle(center, r * 0.88, body);

    // rim
    canvas.drawCircle(
      center,
      r * 0.88,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.02
        ..color = const Color(0xFF3A3A4C),
    );

    // ---- background gear (large, slow, counter-clockwise) ----
    _drawGear(canvas, center, r * 0.62, 12, -t * 0.5,
        const Color(0xFF262634), r * 0.13);

    // ---- main gear (clockwise) ----
    _drawGear(canvas, center, r * 0.44, 10, t,
        const Color(0xFF34344A), r * 0.10);

    // small satellite gear
    final satCenter = center + Offset(r * 0.52 * cos(-0.8), r * 0.52 * sin(-0.8));
    _drawGear(canvas, satCenter, r * 0.16, 8, -t * 2.4,
        const Color(0xFF2C2C3E), r * 0.05);

    // ---- center hub ----
    canvas.drawCircle(
      center,
      r * 0.20,
      Paint()
        ..shader = RadialGradient(colors: [
          glowColor.withValues(alpha: holding || completed ? 0.9 : 0.45),
          glowColor.withValues(alpha: 0.05),
        ]).createShader(Rect.fromCircle(center: center, radius: r * 0.20)),
    );
    canvas.drawCircle(
      center,
      r * 0.13,
      Paint()..color = const Color(0xFF0C0C14),
    );

    // ---- progress ring ----
    final ringRect = Rect.fromCircle(center: center, radius: r * 0.94);
    // track
    canvas.drawArc(
      ringRect,
      -pi / 2,
      2 * pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.045
        ..color = Colors.white.withValues(alpha: 0.07),
    );
    // fill
    if (progress > 0) {
      canvas.drawArc(
        ringRect,
        -pi / 2,
        2 * pi * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = r * 0.045
          ..shader = SweepGradient(
            startAngle: -pi / 2,
            endAngle: 3 * pi / 2,
            colors: [glowColor.withValues(alpha: 0.6), glowColor],
            transform: const GradientRotation(-pi / 2),
          ).createShader(ringRect),
      );
      // leading dot glow
      final ang = -pi / 2 + 2 * pi * progress;
      final dot = center + Offset(cos(ang), sin(ang)) * r * 0.94;
      canvas.drawCircle(
        dot,
        r * 0.035,
        Paint()
          ..color = glowColor
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.03),
      );
    }

    // ---- electric arcs while holding ----
    if (holding && !completed) {
      final rand = Random((t * 30).floor());
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = glowColor.withValues(alpha: 0.7);
      for (int i = 0; i < (spark ? 4 : 2); i++) {
        final a0 = rand.nextDouble() * 2 * pi;
        final path = Path();
        var p = center + Offset(cos(a0), sin(a0)) * r * 0.20;
        path.moveTo(p.dx, p.dy);
        for (int s = 0; s < 4; s++) {
          final rr = r * (0.28 + 0.16 * (s + 1) / 4);
          final aa = a0 + (rand.nextDouble() - 0.5) * 0.8;
          p = center + Offset(cos(aa), sin(aa)) * rr;
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, arcPaint);
      }
    }
  }

  void _drawGear(Canvas canvas, Offset center, double radius, int teeth,
      double rotation, Color color, double toothLen) {
    final paint = Paint()..color = color;
    final path = Path();
    for (int i = 0; i < teeth; i++) {
      final a = rotation + i * 2 * pi / teeth;
      final aNext = rotation + (i + 1) * 2 * pi / teeth;
      final aMid1 = a + (aNext - a) * 0.25;
      final aMid2 = a + (aNext - a) * 0.5;
      final outer = radius + toothLen;
      if (i == 0) {
        path.moveTo(center.dx + radius * cos(a), center.dy + radius * sin(a));
      }
      path.lineTo(center.dx + outer * cos(a + (aNext - a) * 0.08),
          center.dy + outer * sin(a + (aNext - a) * 0.08));
      path.lineTo(center.dx + outer * cos(aMid1),
          center.dy + outer * sin(aMid1));
      path.lineTo(center.dx + radius * cos(aMid2),
          center.dy + radius * sin(aMid2));
      path.lineTo(center.dx + radius * cos(aNext),
          center.dy + radius * sin(aNext));
    }
    path.close();
    canvas.drawPath(path, paint);

    // gear hole
    canvas.drawCircle(
      center,
      radius * 0.35,
      Paint()..color = const Color(0xFF0E0E16),
    );
    // spokes
    final spoke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.09
      ..color = color;
    for (int i = 0; i < 3; i++) {
      final a = rotation + i * 2 * pi / 3;
      canvas.drawLine(
        center + Offset(cos(a), sin(a)) * radius * 0.35,
        center + Offset(cos(a), sin(a)) * radius * 0.9,
        spoke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MachinePainter old) => true;
}
