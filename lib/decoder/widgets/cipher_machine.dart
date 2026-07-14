import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The cipher machine: ornate gothic frame, rotating rune ring,
/// metallic interlocking gears, pulsing energy core, indicator lamps
/// and electric arcs. The giant "hold here" element of the page.
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
  double _angle = 0; // accumulated gear angle (rad)
  double _lastT = 0;

  @override
  void initState() {
    super.initState();
    _spin =
        AnimationController(vsync: this, duration: const Duration(seconds: 8))
          ..addListener(_accumulate)
          ..repeat();
  }

  /// Accumulate rotation so gear speed changes are smooth (no jumps).
  void _accumulate() {
    var dt = _spin.value - _lastT;
    if (dt < 0) dt += 1;
    _lastT = _spin.value;
    final speed = widget.holding ? 4.0 : (widget.completed ? 0.4 : 0.6);
    _angle += dt * 2 * pi * speed;
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
          return CustomPaint(
            painter: _MachinePainter(
              t: _angle,
              wall: _spin.value * 2 * pi, // wall-clock angle for pulses
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
  final double t; // gear angle (accumulated)
  final double wall; // steady time angle
  final double progress;
  final bool holding;
  final bool completed;
  final bool spark;

  _MachinePainter({
    required this.t,
    required this.wall,
    required this.progress,
    required this.holding,
    required this.completed,
    required this.spark,
  });

  static const _runes = [
    'ᚠ', 'ᚢ', 'ᚦ', 'ᚨ', 'ᚱ', 'ᚲ', 'ᚷ', 'ᚹ', //
    'ᚺ', 'ᚾ', 'ᛁ', 'ᛃ', 'ᛇ', 'ᛈ', 'ᛉ', 'ᛊ',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;

    final glowColor = completed
        ? AppColors.amber
        : (spark ? AppColors.violet : AppColors.cyan);
    final pulse = 0.5 + 0.5 * sin(wall * 2.2);

    // ================= outer glow =================
    final glowStrength =
        completed ? 0.55 : (holding ? 0.32 + pulse * 0.12 : 0.15);
    canvas.drawCircle(
      center,
      r * 0.98,
      Paint()
        ..color = glowColor.withValues(alpha: glowStrength)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.15),
    );

    // ================= gothic outer frame =================
    // dark iron ring
    canvas.drawCircle(
      center,
      r * 0.90,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.055
        ..shader = ui.Gradient.linear(
          center.translate(-r, -r),
          center.translate(r, r),
          [
            const Color(0xFF3E3E52),
            const Color(0xFF1A1A26),
            const Color(0xFF34344A),
            const Color(0xFF15151F),
          ],
          [0.0, 0.4, 0.7, 1.0],
        ),
    );
    // rivets on frame
    final rivetPaint = Paint()..color = const Color(0xFF57576E);
    final rivetHi = Paint()..color = const Color(0xFF8A8AA5);
    for (int i = 0; i < 16; i++) {
      final a = i * pi / 8;
      final p = center + Offset(cos(a), sin(a)) * r * 0.90;
      canvas.drawCircle(p, r * 0.014, rivetPaint);
      canvas.drawCircle(
          p.translate(-r * 0.004, -r * 0.004), r * 0.006, rivetHi);
    }
    // ornate spikes at cardinal points (gothic cross tips)
    final spikePaint = Paint()..color = const Color(0xFF2C2C3E);
    for (int i = 0; i < 4; i++) {
      final a = i * pi / 2 - pi / 2;
      final dir = Offset(cos(a), sin(a));
      final normal = Offset(-dir.dy, dir.dx);
      final base = center + dir * r * 0.925;
      final tip = center + dir * r * 1.0;
      final path = Path()
        ..moveTo(base.dx + normal.dx * r * 0.035,
            base.dy + normal.dy * r * 0.035)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(base.dx - normal.dx * r * 0.035,
            base.dy - normal.dy * r * 0.035)
        ..close();
      canvas.drawPath(path, spikePaint);
      canvas.drawCircle(center + dir * r * 0.975, r * 0.012,
          Paint()..color = glowColor.withValues(alpha: 0.5 + pulse * 0.3));
    }

    // ================= rotating rune ring =================
    final runeRadius = r * 0.795;
    for (int i = 0; i < _runes.length; i++) {
      final a = -t * 0.15 + i * 2 * pi / _runes.length;
      final lit = ((a % (2 * pi)) / (2 * pi)) < progress;
      final tp = TextPainter(
        text: TextSpan(
          text: _runes[i],
          style: TextStyle(
            fontSize: r * 0.075,
            color: lit
                ? glowColor.withValues(alpha: 0.85)
                : const Color(0xFF4A4A5E),
            shadows: lit
                ? [Shadow(color: glowColor, blurRadius: 8)]
                : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final pos = center + Offset(cos(a), sin(a)) * runeRadius;
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(a + pi / 2);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    // ================= machine body =================
    final body = Paint()
      ..shader = ui.Gradient.radial(
        center.translate(-r * 0.15, -r * 0.18),
        r * 0.72,
        [
          const Color(0xFF232330),
          const Color(0xFF15151E),
          const Color(0xFF0C0C12),
        ],
        [0.0, 0.6, 1.0],
      );
    canvas.drawCircle(center, r * 0.70, body);
    // inner rim with metallic sheen
    canvas.drawCircle(
      center,
      r * 0.70,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.016
        ..shader = ui.Gradient.sweep(
          center,
          [
            const Color(0xFF52526B),
            const Color(0xFF23232F),
            const Color(0xFF6A6A86),
            const Color(0xFF23232F),
            const Color(0xFF52526B),
          ],
          [0.0, 0.25, 0.5, 0.75, 1.0],
        ),
    );

    // faint radial panel lines inside body
    final panelPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.04);
    for (int i = 0; i < 6; i++) {
      final a = i * pi / 3 + 0.26;
      canvas.drawLine(
        center + Offset(cos(a), sin(a)) * r * 0.30,
        center + Offset(cos(a), sin(a)) * r * 0.68,
        panelPaint,
      );
    }

    // ================= gears =================
    // large background gear (counter-clockwise)
    _drawGear(canvas, center, r * 0.56, 14, -t * 0.5,
        const Color(0xFF262634), const Color(0xFF3A3A4E), r * 0.10);
    // main gear (clockwise)
    _drawGear(canvas, center, r * 0.40, 10, t, const Color(0xFF34344A),
        const Color(0xFF4E4E68), r * 0.085);
    // satellite gears
    final sat1 = center + Offset(cos(-0.8), sin(-0.8)) * r * 0.47;
    _drawGear(canvas, sat1, r * 0.14, 8, -t * 2.6, const Color(0xFF2C2C3E),
        const Color(0xFF44445A), r * 0.045);
    final sat2 = center + Offset(cos(2.5), sin(2.5)) * r * 0.50;
    _drawGear(canvas, sat2, r * 0.10, 6, t * 3.4, const Color(0xFF29293A),
        const Color(0xFF404056), r * 0.035);

    // ================= energy core =================
    final coreR = r * 0.185;
    // outer aura
    canvas.drawCircle(
      center,
      coreR * (1.25 + pulse * 0.15),
      Paint()
        ..color = glowColor
            .withValues(alpha: holding || completed ? 0.35 : 0.15)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, coreR * 0.6),
    );
    // core sphere
    canvas.drawCircle(
      center,
      coreR,
      Paint()
        ..shader = ui.Gradient.radial(
          center.translate(-coreR * 0.3, -coreR * 0.3),
          coreR * 1.4,
          [
            Colors.white.withValues(
                alpha: holding || completed ? 0.95 : 0.55),
            glowColor.withValues(
                alpha: holding || completed ? 0.85 : 0.4),
            glowColor.withValues(alpha: 0.05),
          ],
          [0.0, 0.35, 1.0],
        ),
    );
    // iris ring inside core
    canvas.drawCircle(
      center,
      coreR * 0.62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.008
        ..color = Colors.black.withValues(alpha: 0.5),
    );
    // rotating iris blades
    final irisPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.010
      ..color = const Color(0xFF0C0C14).withValues(alpha: 0.85);
    for (int i = 0; i < 6; i++) {
      final a = t * 0.8 + i * pi / 3;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: coreR * 0.62),
        a,
        pi / 5,
        false,
        irisPaint,
      );
    }

    // ================= indicator lamps (progress thirds) =================
    // 3 lamps arranged below the core, like IdentityV cipher lights
    for (int i = 0; i < 3; i++) {
      final lit = progress >= (i + 1) / 3 - 0.001;
      final lx = center.dx + (i - 1) * r * 0.14;
      final ly = center.dy + r * 0.335;
      final lampC = Offset(lx, ly);
      // socket
      canvas.drawCircle(
          lampC, r * 0.036, Paint()..color = const Color(0xFF0A0A10));
      canvas.drawCircle(
        lampC,
        r * 0.036,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.008
          ..color = const Color(0xFF4A4A60),
      );
      // bulb
      if (lit) {
        canvas.drawCircle(
          lampC,
          r * 0.05,
          Paint()
            ..color = AppColors.amber.withValues(alpha: 0.45)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.04),
        );
      }
      canvas.drawCircle(
        lampC,
        r * 0.024,
        Paint()
          ..color = lit
              ? AppColors.amber
              : const Color(0xFF2A2A38),
      );
    }

    // ================= progress ring =================
    final ringRect = Rect.fromCircle(center: center, radius: r * 0.955);
    // tick marks
    final tickPaint = Paint()..strokeWidth = r * 0.006;
    for (int i = 0; i < 60; i++) {
      final a = -pi / 2 + i * pi / 30;
      final frac = i / 60;
      final lit = frac <= progress;
      tickPaint.color = lit
          ? glowColor.withValues(alpha: 0.8)
          : Colors.white.withValues(alpha: 0.10);
      final inner = r * (i % 5 == 0 ? 0.915 : 0.93);
      canvas.drawLine(
        center + Offset(cos(a), sin(a)) * inner,
        center + Offset(cos(a), sin(a)) * r * 0.955,
        tickPaint,
      );
    }
    // track
    canvas.drawArc(
      ringRect,
      -pi / 2,
      2 * pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.040
        ..color = Colors.white.withValues(alpha: 0.06),
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
          ..strokeWidth = r * 0.040
          ..shader = SweepGradient(
            startAngle: -pi / 2,
            endAngle: 3 * pi / 2,
            colors: [glowColor.withValues(alpha: 0.55), glowColor],
            transform: const GradientRotation(-pi / 2),
          ).createShader(ringRect),
      );
      // leading comet head
      final ang = -pi / 2 + 2 * pi * progress;
      final dot = center + Offset(cos(ang), sin(ang)) * r * 0.955;
      canvas.drawCircle(
        dot,
        r * 0.045,
        Paint()
          ..color = glowColor.withValues(alpha: 0.55)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.04),
      );
      canvas.drawCircle(dot, r * 0.018, Paint()..color = Colors.white);
    }

    // ================= electric arcs while holding =================
    if (holding && !completed) {
      final rand = Random((wall * 30).floor());
      for (int i = 0; i < (spark ? 5 : 3); i++) {
        final a0 = rand.nextDouble() * 2 * pi;
        final path = Path();
        var p = center + Offset(cos(a0), sin(a0)) * coreR;
        path.moveTo(p.dx, p.dy);
        for (int s = 0; s < 5; s++) {
          final rr = r * (0.22 + 0.46 * (s + 1) / 5);
          final aa = a0 + (rand.nextDouble() - 0.5) * 0.9;
          p = center + Offset(cos(aa), sin(aa)) * rr;
          path.lineTo(p.dx, p.dy);
        }
        // glow pass + core pass
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5
            ..color = glowColor.withValues(alpha: 0.25)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = Colors.white.withValues(alpha: 0.75),
        );
      }

      // spark particles flying off the ring head
      final ang = -pi / 2 + 2 * pi * progress;
      final head = center + Offset(cos(ang), sin(ang)) * r * 0.955;
      for (int i = 0; i < 6; i++) {
        final sa = rand.nextDouble() * 2 * pi;
        final sd = rand.nextDouble() * r * 0.09;
        canvas.drawCircle(
          head + Offset(cos(sa), sin(sa)) * sd,
          rand.nextDouble() * r * 0.010 + 1,
          Paint()
            ..color =
                glowColor.withValues(alpha: 0.4 + rand.nextDouble() * 0.5),
        );
      }
    }

    // ================= completed: golden shimmer sweep =================
    if (completed) {
      final sweepA = wall * 0.7;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r * 0.70),
        sweepA,
        pi / 3,
        true,
        Paint()
          ..shader = ui.Gradient.sweep(
            center,
            [
              Colors.transparent,
              AppColors.amber.withValues(alpha: 0.10),
              Colors.transparent,
            ],
            [0.0, 0.5, 1.0],
            TileMode.clamp,
            sweepA,
            sweepA + pi / 3,
          ),
      );
    }
  }

  void _drawGear(Canvas canvas, Offset center, double radius, int teeth,
      double rotation, Color color, Color hiColor, double toothLen) {
    // metallic body gradient
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        center.translate(-radius, -radius),
        center.translate(radius, radius),
        [hiColor, color, Color.lerp(color, Colors.black, 0.35)!],
        [0.0, 0.5, 1.0],
      );
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
      path.lineTo(
          center.dx + outer * cos(aMid1), center.dy + outer * sin(aMid1));
      path.lineTo(
          center.dx + radius * cos(aMid2), center.dy + radius * sin(aMid2));
      path.lineTo(
          center.dx + radius * cos(aNext), center.dy + radius * sin(aNext));
    }
    path.close();
    canvas.drawPath(path, paint);
    // subtle top-edge highlight
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = hiColor.withValues(alpha: 0.35),
    );

    // gear hole
    canvas.drawCircle(
        center, radius * 0.35, Paint()..color = const Color(0xFF0E0E16));
    canvas.drawCircle(
      center,
      radius * 0.35,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.05
        ..color = hiColor.withValues(alpha: 0.4),
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
    // hub bolt
    canvas.drawCircle(
        center, radius * 0.10, Paint()..color = hiColor.withValues(alpha: 0.7));
  }

  @override
  bool shouldRepaint(covariant _MachinePainter old) => true;
}
