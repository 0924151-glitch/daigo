import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Matrix-style falling "rune code" rain, tinted cyan/violet.
/// Sits behind the machine. Speeds up while [intense].
class CodeRain extends StatefulWidget {
  final bool intense;
  const CodeRain({super.key, required this.intense});

  @override
  State<CodeRain> createState() => _CodeRainState();
}

class _CodeRainState extends State<CodeRain>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final List<_Column> _cols = [];
  final _rand = Random(7);
  double _time = 0;
  double _lastT = 0;
  Size _lastSize = Size.zero;

  static const _glyphs =
      'ᚠᚡᚢᚣᚤᚥᚦᚧᚨᚩᚪᚫᚬᚭᚮᚯᚰᚱᚲᚳᚴᚵᚶᚷᚸᚹᚺᚻᚼᚽᚾᚿᛀᛁᛂᛃᛄᛅᛆᛇᛈ0123456789ABCDEF§†‡Ψ∆∇';

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 10))
      ..addListener(_tick)
      ..repeat();
  }

  void _tick() {
    var dt = _ctrl.value - _lastT;
    if (dt < 0) dt += 1;
    _lastT = _ctrl.value;
    _time += dt * 10 * (widget.intense ? 2.2 : 1.0);
    if (mounted) setState(() {});
  }

  void _rebuild(Size size) {
    if ((size.width - _lastSize.width).abs() < 40 && _cols.isNotEmpty) return;
    _lastSize = size;
    _cols.clear();
    final n = (size.width / 26).ceil();
    for (var i = 0; i < n; i++) {
      _cols.add(_Column(
        x: i * 26.0 + _rand.nextDouble() * 8,
        speed: 40 + _rand.nextDouble() * 90,
        length: 6 + _rand.nextInt(14),
        offset: _rand.nextDouble() * 1200,
        chars: List.generate(
            24, (_) => _glyphs[_rand.nextInt(_glyphs.length)]),
        violet: _rand.nextDouble() < 0.22,
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
      child: LayoutBuilder(builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        _rebuild(size);
        return CustomPaint(
          size: size,
          painter: _RainPainter(
            cols: _cols,
            time: _time,
            intense: widget.intense,
          ),
        );
      }),
    );
  }
}

class _Column {
  final double x, speed, offset;
  final int length;
  final List<String> chars;
  final bool violet;
  _Column({
    required this.x,
    required this.speed,
    required this.length,
    required this.offset,
    required this.chars,
    required this.violet,
  });
}

class _RainPainter extends CustomPainter {
  final List<_Column> cols;
  final double time;
  final bool intense;
  _RainPainter({required this.cols, required this.time, required this.intense});

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 20.0;
    final baseAlpha = intense ? 0.30 : 0.16;
    for (final col in cols) {
      final headY =
          ((time * col.speed + col.offset) % (size.height + col.length * cell)) -
              col.length * cell;
      for (var i = 0; i < col.length; i++) {
        final y = headY + i * cell;
        if (y < -cell || y > size.height) continue;
        final frac = i / col.length; // 0 tail .. 1 head
        final isHead = i == col.length - 1;
        final color = isHead
            ? Colors.white.withValues(alpha: baseAlpha * 2.4)
            : (col.violet ? AppColors.violet : AppColors.cyan)
                .withValues(alpha: baseAlpha * frac * frac);
        final ch = col.chars[(i + (time * 3).floor()) % col.chars.length];
        final tp = TextPainter(
          text: TextSpan(
            text: ch,
            style: TextStyle(
              fontSize: 15,
              color: color,
              fontWeight: isHead ? FontWeight.bold : FontWeight.normal,
              shadows: isHead
                  ? [Shadow(color: AppColors.cyan.withValues(alpha: 0.8), blurRadius: 8)]
                  : null,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(col.x, y));
      }
    }
  }

  @override
  bool shouldRepaint(_RainPainter old) => old.time != time;
}
