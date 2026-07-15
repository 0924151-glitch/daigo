import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'decoder_controller.dart';
import 'widgets/cipher_machine.dart';
import 'widgets/machine_designs.dart';
import 'widgets/overlays.dart';
import 'widgets/workshop_background.dart';

/// Full-screen decoder page - quiet workshop style.
///
/// Interaction: hold (mouse / touch) on the machine to decode. That's all.
class DecoderPage extends StatefulWidget {
  final String machineId;
  const DecoderPage({super.key, required this.machineId});

  @override
  State<DecoderPage> createState() => _DecoderPageState();
}

class _DecoderPageState extends State<DecoderPage> {
  late final DecoderController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = DecoderController(widget.machineId);
    _ctrl.connect();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.decoder(),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            switch (_ctrl.phase) {
              case DecoderPhase.connecting:
                return const _MessageView(
                  icon: Icons.sync,
                  title: '接続中...',
                  subtitle: '荘園のサーバーに接続しています',
                  spin: true,
                );
              case DecoderPhase.locked:
                return const _MessageView(
                  icon: Icons.lock,
                  title: 'この暗号機は使用中です',
                  subtitle: '他の画面でこの暗号機が開かれています。\n1台の暗号機は同時に1画面しか開けません。',
                );
              case DecoderPhase.notFound:
                return const _MessageView(
                  icon: Icons.help_outline,
                  title: '暗号機が見つかりません',
                  subtitle: 'この暗号機は撤去されたか、URLが間違っています。',
                );
              case DecoderPhase.deleted:
                return const _MessageView(
                  icon: Icons.delete_outline,
                  title: '暗号機が撤去されました',
                  subtitle: '運営によりこの暗号機は撤去されました。',
                );
              case DecoderPhase.ready:
                return _buildGame(context);
            }
          },
        ),
      ),
    );
  }

  Widget _buildGame(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final machineSize = (size.shortestSide * 0.70).clamp(300.0, 620.0);
    final design = machineDesignByKey(_ctrl.machine?.design ?? 'classic');

    return Stack(
      fit: StackFit.expand,
      children: [
        WorkshopBackground(active: _ctrl.holding),

        // ---- header: machine name ----
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _ctrl.machine?.name ?? '',
                    style: const TextStyle(
                      fontSize: 28,
                      letterSpacing: 8,
                      fontWeight: FontWeight.w600,
                      color: AppColors.bone,
                      shadows: [
                        Shadow(
                          color: Colors.black,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '— CIPHER MACHINE —',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 6,
                      color: AppColors.boneDim.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ---- machine (hold target) ----
        Center(
          child: Listener(
            onPointerDown: (_) => _ctrl.startHold(),
            onPointerUp: (_) => _ctrl.endHold(),
            onPointerCancel: (_) => _ctrl.endHold(),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: AnimatedScale(
                scale: _ctrl.holding ? 1.02 : 1.0,
                duration: const Duration(milliseconds: 250),
                child: SizedBox(
                  width: machineSize,
                  height: machineSize,
                  child: CipherMachine(
                    progress: _ctrl.progress,
                    holding: _ctrl.holding,
                    completed: _ctrl.completed,
                    design: design,
                  ),
                ),
              ),
            ),
          ),
        ),

        // ---- footer: progress + hint ----
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 30),
              child: AnimatedOpacity(
                opacity: _ctrl.completed ? 0 : 1,
                duration: const Duration(milliseconds: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ProgressReadout(
                      progress: _ctrl.progress,
                      accent: design.lampActive,
                    ),
                    const SizedBox(height: 16),
                    _PulsingHint(
                      text: _ctrl.holding ? '解読中...' : '暗号機を長押しして解読せよ',
                      active: !_ctrl.holding,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ---- completed overlay ----
        if (_ctrl.completed)
          CompletedOverlay(machineName: _ctrl.machine?.name ?? ''),
      ],
    );
  }
}

/// Progress bar + percentage, styled like a brass gauge strip.
class _ProgressReadout extends StatelessWidget {
  final double progress; // 0..100
  final Color accent;

  const _ProgressReadout({required this.progress, required this.accent});

  @override
  Widget build(BuildContext context) {
    const barWidth = 260.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${progress.floor()}%',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: AppColors.bone,
            shadows: [
              Shadow(
                color: accent.withValues(alpha: 0.4),
                blurRadius: 12,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: barWidth,
          height: 5,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: barWidth * (progress / 100).clamp(0.0, 1.0),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.5),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Hint text that slowly pulses to attract attention when idle.
class _PulsingHint extends StatefulWidget {
  final String text;
  final bool active;
  const _PulsingHint({required this.text, required this.active});

  @override
  State<_PulsingHint> createState() => _PulsingHintState();
}

class _PulsingHintState extends State<_PulsingHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final alpha = widget.active ? 0.45 + 0.4 * _ctrl.value : 0.75;
        return Text(
          widget.text,
          style: TextStyle(
            color: AppColors.bone.withValues(alpha: alpha),
            fontSize: 14,
            letterSpacing: 3,
          ),
        );
      },
    );
  }
}

/// Simple centered message screen for lock / error states.
class _MessageView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool spin;

  const _MessageView({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.spin = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const WorkshopBackground(),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              spin
                  ? const SizedBox(
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(
                        color: AppColors.amber,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Icon(
                      icon,
                      size: 60,
                      color: AppColors.blood.withValues(alpha: 0.9),
                    ),
              const SizedBox(height: 26),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  color: AppColors.bone,
                  letterSpacing: 4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.8,
                  color: AppColors.boneDim.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
