import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'decoder_controller.dart';
import 'widgets/atmosphere.dart';
import 'widgets/cipher_machine.dart';
import 'widgets/code_rain.dart';
import 'widgets/holo_hud.dart';
import 'widgets/overlays.dart';
import 'widgets/skill_check_widget.dart';

/// Full-screen decoder page. Sized for PC displays but works on mobile.
///
/// Interaction:
///  - Hold mouse / touch on the machine  => decode
///  - SPACE key or tap during skill check => QTE hit
class DecoderPage extends StatefulWidget {
  final String machineId;
  const DecoderPage({super.key, required this.machineId});

  @override
  State<DecoderPage> createState() => _DecoderPageState();
}

class _DecoderPageState extends State<DecoderPage>
    with SingleTickerProviderStateMixin {
  late final DecoderController _ctrl;
  final FocusNode _focusNode = FocusNode();
  late final AnimationController _shake;
  bool _wasShocking = false;

  @override
  void initState() {
    super.initState();
    _ctrl = DecoderController(widget.machineId);
    _ctrl.connect();
    _shake = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _ctrl.addListener(_onCtrlChanged);
  }

  void _onCtrlChanged() {
    // trigger screen shake when a shock starts
    if (_ctrl.shockActive && !_wasShocking) {
      _shake.forward(from: 0);
    }
    _wasShocking = _ctrl.shockActive;
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onCtrlChanged);
    _ctrl.dispose();
    _focusNode.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _onKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.space) {
      _ctrl.hitSkillCheck();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.decoder(),
      child: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKey,
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
      ),
    );
  }

  Widget _buildGame(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final machineSize = (size.shortestSide * 0.62).clamp(280.0, 560.0);

    return GestureDetector(
      // tap anywhere = skill check hit (when active)
      onTapDown: (_) {
        if (_ctrl.skill != null) _ctrl.hitSkillCheck();
      },
      child: AnimatedBuilder(
        animation: _shake,
        builder: (context, child) {
          // decaying random shake while shock plays
          final v = _shake.isAnimating ? (1 - _shake.value) : 0.0;
          final rnd = Random((_shake.value * 100).floor());
          final dx = (rnd.nextDouble() - 0.5) * 22 * v;
          final dy = (rnd.nextDouble() - 0.5) * 16 * v;
          return Transform.translate(offset: Offset(dx, dy), child: child);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            AtmosphereBackground(intense: _ctrl.holding),
            CodeRain(intense: _ctrl.holding),
            HoloHud(
              progress: _ctrl.progress,
              holding: _ctrl.holding,
              completed: _ctrl.completed,
            ),

            // ---- header ----
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 26),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ornamental divider above title
                      const _OrnamentDivider(width: 200),
                      const SizedBox(height: 10),
                      GlitchText(
                        text: _ctrl.machine?.name ?? '',
                        style: TextStyle(
                          fontSize: 32,
                          letterSpacing: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.bone,
                          shadows: [
                            Shadow(
                              color: AppColors.cyan.withValues(alpha: 0.5),
                              blurRadius: 18,
                            ),
                            const Shadow(
                              color: Colors.black,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '— CIPHER MACHINE —',
                        style: TextStyle(
                          fontSize: 12,
                          letterSpacing: 7,
                          color: AppColors.boneDim.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const _OrnamentDivider(width: 140, flip: true),
                    ],
                  ),
                ),
              ),
            ),

            // ---- machine (hold target) ----
            Center(
              child: Listener(
                onPointerDown: (_) {
                  if (_ctrl.skill != null) {
                    _ctrl.hitSkillCheck();
                  } else {
                    _ctrl.startHold();
                  }
                },
                onPointerUp: (_) => _ctrl.endHold(),
                onPointerCancel: (_) => _ctrl.endHold(),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: AnimatedScale(
                    scale: _ctrl.holding ? 1.03 : 1.0,
                    duration: const Duration(milliseconds: 250),
                    child: SizedBox(
                      width: machineSize,
                      height: machineSize,
                      child: CipherMachine(
                        progress: _ctrl.progress,
                        holding: _ctrl.holding,
                        completed: _ctrl.completed,
                        sparkActive: _ctrl.sparkActive,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ---- progress % ----
            IgnorePointer(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: machineSize * 0.09),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_ctrl.progress.floor()}',
                        style: TextStyle(
                          fontSize: machineSize * 0.145,
                          fontWeight: FontWeight.bold,
                          height: 1,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: _ctrl.completed
                              ? AppColors.amber
                              : Colors.white.withValues(alpha: 0.92),
                          shadows: [
                            Shadow(
                              color: (_ctrl.completed
                                      ? AppColors.amber
                                      : AppColors.cyan)
                                  .withValues(alpha: 0.7),
                              blurRadius: 22,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '%',
                        style: TextStyle(
                          fontSize: machineSize * 0.045,
                          color: AppColors.boneDim,
                          letterSpacing: 3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ---- skill check ----
            if (_ctrl.skill != null && !_ctrl.skill!.resolved)
              Align(
                alignment: const Alignment(0, -0.55),
                child: SkillCheckWidget(skill: _ctrl.skill!),
              ),

            // ---- footer hint ----
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 28),
                  child: AnimatedOpacity(
                    opacity: _ctrl.completed ? 0 : 1,
                    duration: const Duration(milliseconds: 400),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_ctrl.sparkActive)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 10),
                            child: Text(
                              '⚡ 火花ブースト発動中！解読速度アップ ⚡',
                              style: TextStyle(
                                color: AppColors.violet,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                        _PulsingHint(
                          text: _ctrl.holding
                              ? '解読中... 針が白いゾーンに入ったら SPACE / タップ！'
                              : '暗号機を長押しして解読せよ',
                          active: !_ctrl.holding,
                        ),
                        const SizedBox(height: 12),
                        _StatsRow(ctrl: _ctrl),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ---- perfect flash ----
            if (_ctrl.perfectFlash)
              IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.12),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: const Align(
                    alignment: Alignment(0, -0.3),
                    child: Text(
                      'PERFECT!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                        shadows: [
                          Shadow(color: Colors.white, blurRadius: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // ---- shock overlay ----
            if (_ctrl.shockActive) const ShockOverlay(),

            // ---- completed overlay ----
            if (_ctrl.completed)
              CompletedOverlay(machineName: _ctrl.machine?.name ?? ''),
          ],
        ),
      ),
    );
  }
}

/// Small gothic ornament: line - diamond - line.
class _OrnamentDivider extends StatelessWidget {
  final double width;
  final bool flip;
  const _OrnamentDivider({required this.width, this.flip = false});

  @override
  Widget build(BuildContext context) {
    final line = Container(
      width: (width - 30) / 2,
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: flip
              ? [
                  AppColors.boneDim.withValues(alpha: 0.6),
                  Colors.transparent,
                ]
              : [
                  Colors.transparent,
                  AppColors.boneDim.withValues(alpha: 0.6),
                ],
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Transform.rotate(
            angle: pi / 4,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppColors.amber.withValues(alpha: 0.8),
                  width: 1.2,
                ),
              ),
            ),
          ),
        ),
        Transform.flip(flipX: true, child: line),
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
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
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
        final alpha =
            widget.active ? 0.5 + 0.45 * _ctrl.value : 0.8;
        return Text(
          widget.text,
          style: TextStyle(
            color: AppColors.bone.withValues(alpha: alpha),
            fontSize: 15,
            letterSpacing: 3,
          ),
        );
      },
    );
  }
}

/// Bottom stats: combo / success / miss.
class _StatsRow extends StatelessWidget {
  final DecoderController ctrl;
  const _StatsRow({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    TextStyle style(Color c) => TextStyle(
          color: c.withValues(alpha: 0.85),
          fontSize: 12,
          letterSpacing: 1.5,
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('COMBO ${ctrl.comboSuccess}', style: style(AppColors.cyan)),
        const SizedBox(width: 18),
        Text('成功 ${ctrl.skillSuccessCount}', style: style(AppColors.amber)),
        const SizedBox(width: 18),
        Text('失敗 ${ctrl.skillMissCount}', style: style(AppColors.blood)),
      ],
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
        const AtmosphereBackground(),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              spin
                  ? const SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                        color: AppColors.cyan,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Icon(icon,
                      size: 64,
                      color: AppColors.blood.withValues(alpha: 0.9)),
              const SizedBox(height: 28),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 26,
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
