import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Calm completion overlay: dark veil, soft lamp glow, message.
/// No fireworks - matches the quiet workshop mood.
class CompletedOverlay extends StatefulWidget {
  final String machineName;

  const CompletedOverlay({super.key, required this.machineName});

  @override
  State<CompletedOverlay> createState() => _CompletedOverlayState();
}

class _CompletedOverlayState extends State<CompletedOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _fade;
  late final Animation<double> _rise;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
    _fade = CurvedAnimation(
      parent: _anim,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    _rise = Tween<double>(begin: 24, end: 0).animate(
      CurvedAnimation(
        parent: _anim,
        curve: const Interval(0.15, 0.8, curve: Curves.easeOutCubic),
      ),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        return IgnorePointer(
          child: Container(
            color: Colors.black.withValues(alpha: 0.55 * _fade.value),
            child: Center(
              child: Opacity(
                opacity: _fade.value,
                child: Transform.translate(
                  offset: Offset(0, _rise.value),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // green lamp with soft halo
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.lamp.withValues(alpha: 0.18),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.lamp.withValues(alpha: 0.35),
                              blurRadius: 40,
                              spreadRadius: 6,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: AppColors.lamp,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        '解読完了',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 12,
                          color: AppColors.bone,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        widget.machineName,
                        style: TextStyle(
                          fontSize: 15,
                          letterSpacing: 4,
                          color: AppColors.boneDim.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '— DECODED —',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 6,
                          color: AppColors.amber.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
