import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../decoder_controller.dart';

/// Identity V style skill check: circular gauge with a sweeping needle
/// and a highlighted success zone. Player must hit SPACE / tap when the
/// needle is inside the zone.
class SkillCheckWidget extends StatelessWidget {
  final SkillCheck skill;
  const SkillCheckWidget({super.key, required this.skill});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      height: 190,
      child: CustomPaint(
        painter: _SkillPainter(skill),
        child: Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.55),
              border: Border.all(
                color: AppColors.bone.withValues(alpha: 0.6),
              ),
            ),
            child: const Center(
              child: Text(
                'SPACE',
                style: TextStyle(
                  color: AppColors.bone,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SkillPainter extends CustomPainter {
  final SkillCheck skill;
  _SkillPainter(this.skill);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2 - 8;
    const startAngle = -pi / 2;

    // backdrop disc
    canvas.drawCircle(
      center,
      r + 6,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // track
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      0,
      2 * pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = Colors.white.withValues(alpha: 0.14),
    );

    // success zone
    final zonePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = AppColors.amber;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      startAngle + skill.zoneStart * 2 * pi,
      skill.zoneWidth * 2 * pi,
      false,
      zonePaint,
    );
    // perfect zone (center of success zone, brighter)
    final perfectStart =
        skill.zoneStart + skill.zoneWidth / 2 - skill.zoneWidth * 0.18;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      startAngle + perfectStart * 2 * pi,
      skill.zoneWidth * 0.36 * 2 * pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = Colors.white,
    );

    // needle
    final needleAngle = startAngle + skill.needle * 2 * pi;
    final tip = center + Offset(cos(needleAngle), sin(needleAngle)) * (r + 4);
    final base = center + Offset(cos(needleAngle), sin(needleAngle)) * (r - 16);
    canvas.drawLine(
      base,
      tip,
      Paint()
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..color = AppColors.blood,
    );
    canvas.drawCircle(
      tip,
      4,
      Paint()
        ..color = AppColors.blood
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  @override
  bool shouldRepaint(covariant _SkillPainter old) => true;
}
