import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../theme/app_theme.dart';

/// Admin panel for the 3D mini-game: live status via /ws/game/spectate,
/// CPU difficulty slider, auto-start toggle, force start / end buttons.
/// Self-contained (own controller) so dashboard_page stays clean.
class GamePanel extends StatefulWidget {
  const GamePanel({super.key});

  @override
  State<GamePanel> createState() => _GamePanelState();
}

class _GamePanelState extends State<GamePanel> {
  SocketService? _socket;
  StreamSubscription? _sub;
  Timer? _pollTimer;

  Map<String, dynamic>? _status;
  double? _pendingDifficulty; // while user drags the slider
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _socket = SocketService('/ws/game/spectate', autoReconnect: true);
    _sub = _socket!.messages.listen((msg) {
      if (msg['type'] == 'game_status') {
        setState(() => _status = msg);
      }
    });
    _socket!.connect();
    _fetchOnce();
    // gentle REST fallback in case WS drops
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!(_socket?.isConnected ?? false)) _fetchOnce();
    });
  }

  Future<void> _fetchOnce() async {
    try {
      final s = await ApiService.instance.gameStatus();
      if (mounted) setState(() => _status = s);
    } catch (_) {}
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _sub?.cancel();
    _socket?.dispose();
    super.dispose();
  }

  // ---------------- actions ----------------

  Future<void> _applyDifficulty(double v) async {
    setState(() => _pendingDifficulty = null);
    try {
      await ApiService.instance.setGameConfig(difficulty: v);
    } catch (_) {}
  }

  Future<void> _toggleAutoStart(bool v) async {
    try {
      await ApiService.instance.setGameConfig(autoStart: v);
      _fetchOnce();
    } catch (_) {}
  }

  Future<void> _forceStart() async {
    setState(() => _busy = true);
    try {
      await ApiService.instance.gameForceStart();
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _forceEnd() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('試合を強制終了しますか？'),
            content: const Text('進行中の試合が即座に終了します。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('キャンセル')),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.dashRed),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('強制終了'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await ApiService.instance.gameForceEnd();
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  // ---------------- helpers ----------------

  Map<String, dynamic> get _config =>
      (_status?['config'] as Map<String, dynamic>?) ?? const {};

  double get _difficulty =>
      _pendingDifficulty ??
      ((_config['difficulty'] as num?)?.toDouble() ?? 0.5);

  String get _phase => (_status?['phase'] as String?) ?? '...';

  (String, Color) get _phaseLabel {
    switch (_phase) {
      case 'lobby':
        return ('ロビー待機中', AppColors.dashGrey);
      case 'countdown':
        return ('開始カウントダウン', AppColors.dashAmber);
      case 'running':
        return ('試合進行中', AppColors.dashGreen);
      case 'result':
        return ('リザルト表示中', AppColors.dashBlue);
      default:
        return ('接続中...', AppColors.dashGrey);
    }
  }

  String get _difficultyLabel {
    final d = _difficulty;
    if (d < 0.2) return 'とてもやさしい';
    if (d < 0.4) return 'やさしい';
    if (d < 0.6) return 'ふつう';
    if (d < 0.8) return 'つよい';
    return 'ナイトメア';
  }

  Color get _difficultyColor {
    final d = _difficulty;
    if (d < 0.4) return AppColors.dashGreen;
    if (d < 0.7) return AppColors.dashAmber;
    return AppColors.dashRed;
  }

  @override
  Widget build(BuildContext context) {
    final (phaseText, phaseColor) = _phaseLabel;
    final players = (_status?['players'] as List?)?.cast<String>() ?? const [];
    final running = _phase == 'running';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.dashSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dashLine),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- header row ----
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1035),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.sports_esports,
                    color: Color(0xFF52E0D8), size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                '3Dミニゲーム「追走の霧」',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 12),
              _PhaseChip(text: phaseText, color: phaseColor),
              const Spacer(),
              TextButton.icon(
                onPressed: () =>
                    _showGameQr(context, ApiService.instance.gameUrl()),
                icon: const Icon(Icons.qr_code_2, size: 18),
                label: const Text('QR / URL'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '待ち時間に遊べる非対称対戦。同時に1試合のみ・途中参加不可。空き枠はCPUが自動補充します。',
            style: TextStyle(fontSize: 12.5, color: AppColors.dashGrey),
          ),
          const SizedBox(height: 20),

          // ---- live status ----
          Wrap(
            spacing: 28,
            runSpacing: 12,
            children: [
              _MiniStat(
                label: '参加プレイヤー',
                value: players.isEmpty ? 'なし' : players.join(', '),
              ),
              _MiniStat(
                  label: '通算試合数', value: '${_status?['match_no'] ?? 0}'),
              if (running) ...[
                _MiniStat(
                    label: '解読完了',
                    value: '${_status?['ciphers_done'] ?? 0} / 3 台'),
                _MiniStat(
                    label: '生存者', value: '${_status?['alive'] ?? '-'} 人'),
                _MiniStat(
                    label: '残り時間',
                    value: _fmtTime(_status?['time_left'])),
              ],
            ],
          ),
          const SizedBox(height: 20),
          const Divider(height: 1, color: AppColors.dashLine),
          const SizedBox(height: 16),

          // ---- CPU difficulty ----
          Row(
            children: [
              const Icon(Icons.psychology, size: 18, color: AppColors.dashGrey),
              const SizedBox(width: 8),
              const Text('CPUの強さ',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _difficultyColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _difficultyLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _difficultyColor,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _difficultyColor,
              thumbColor: _difficultyColor,
              inactiveTrackColor: AppColors.dashLine,
              overlayColor: _difficultyColor.withValues(alpha: 0.12),
              trackHeight: 4,
            ),
            child: Slider(
              value: _difficulty.clamp(0.0, 1.0),
              onChanged: (v) => setState(() => _pendingDifficulty = v),
              onChangeEnd: _applyDifficulty,
            ),
          ),
          Row(
            children: const [
              Text('やさしい',
                  style: TextStyle(fontSize: 11, color: AppColors.dashGrey)),
              Spacer(),
              Text('ナイトメア',
                  style: TextStyle(fontSize: 11, color: AppColors.dashGrey)),
            ],
          ),
          const SizedBox(height: 8),
          // derived stats preview
          Text(
            'ハンター速度 ${_config['hunter_speed'] ?? '-'} ／ 索敵範囲 ${_config['hunter_vision'] ?? '-'}m ／ 攻撃間隔 ${_config['hunter_attack_cooldown'] ?? '-'}s',
            style: const TextStyle(fontSize: 11.5, color: AppColors.dashGrey),
          ),
          const SizedBox(height: 16),

          // ---- controls row ----
          Row(
            children: [
              Switch(
                value: (_config['auto_start'] as bool?) ?? true,
                activeThumbColor: AppColors.dashBlue,
                onChanged: _toggleAutoStart,
              ),
              const SizedBox(width: 4),
              const Text('自動マッチ開始',
                  style: TextStyle(fontSize: 13, color: AppColors.dashInk)),
              const Spacer(),
              if (_phase == 'lobby' || _phase == 'countdown')
                FilledButton.icon(
                  onPressed: _busy ? null : _forceStart,
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.dashGreen),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('今すぐ開始'),
                ),
              if (running) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _forceEnd,
                  style:
                      FilledButton.styleFrom(backgroundColor: AppColors.dashRed),
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('強制終了'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _fmtTime(dynamic sec) {
    final s = (sec as num?)?.toInt() ?? 0;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------

class _PhaseChip extends StatelessWidget {
  final String text;
  final Color color;
  const _PhaseChip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11.5, color: AppColors.dashGrey)),
        const SizedBox(height: 3),
        Text(value,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.dashInk)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// QR dialog for the game lobby URL (reuses same pattern as machine QR).
// ---------------------------------------------------------------------------
void _showGameQr(BuildContext context, String url) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('3Dミニゲームへのリンク',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.dashLine),
                ),
                child: QrImageView(
                  data: url,
                  version: QrVersions.auto,
                  size: 210,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.circle,
                    color: Color(0xFF202124),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.circle,
                    color: Color(0xFF202124),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SelectableText(url,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.dashGrey)),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('閉じる'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
