import 'package:flutter/material.dart';

import '../models/machine.dart';
import '../theme/app_theme.dart';
import 'dashboard_controller.dart';
import 'game_panel.dart';
import 'widgets/dialogs.dart';
import 'widgets/machine_card.dart';

/// Operator dashboard: Google-style minimal UI with live machine grid,
/// overall stats, event feed, and machine CRUD.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final DashboardController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = DashboardController()..init();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _addMachine() async {
    final result = await showMachineFormDialog(context);
    if (result == null) return;
    await _ctrl.createMachine(
      result.name,
      result.durationSec,
      design: result.design,
    );
  }

  Future<void> _editMachine(Machine m) async {
    final result = await showMachineFormDialog(context, existing: m);
    if (result == null) return;
    await _ctrl.updateMachine(
      m.id,
      name: result.name,
      durationSec: result.durationSec,
      design: result.design,
    );
  }

  Future<void> _deleteMachine(Machine m) async {
    final ok = await showDeleteConfirmDialog(context, machine: m);
    if (ok) await _ctrl.deleteMachine(m.id);
  }

  void _showQr(Machine m) {
    showQrDialog(context, machine: m, url: _ctrl.machineUrl(m.id));
  }

  void _openMachine(Machine m) {
    Navigator.of(context).pushNamed('/machine/${m.id}');
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.dashboard(),
      child: Scaffold(
        backgroundColor: AppColors.dashBg,
        body: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            return CustomScrollView(
              slivers: [
                // ---- app bar ----
                SliverAppBar(
                  pinned: true,
                  toolbarHeight: 64,
                  title: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.dashInk,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.memory,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Cipher Quest',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        '運営ダッシュボード',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.dashGrey,
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    _ConnBadge(connected: _ctrl.connected),
                    const SizedBox(width: 16),
                  ],
                ),

                // ---- stats header ----
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                    child: _StatsHeader(ctrl: _ctrl),
                  ),
                ),

                // ---- all completed banner ----
                if (_ctrl.allCompleted && _ctrl.machines.isNotEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
                      child: _AllCompletedBanner(),
                    ),
                  ),

                // ---- machine grid ----
                if (_ctrl.loading)
                  const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(
                          color: AppColors.dashBlue, strokeWidth: 2.5),
                    ),
                  )
                else if (_ctrl.machines.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(onAdd: _addMachine),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) {
                        final w = constraints.crossAxisExtent;
                        final cols = w > 1200
                            ? 4
                            : w > 850
                                ? 3
                                : w > 560
                                    ? 2
                                    : 1;
                        return SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            mainAxisExtent: 196,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              final m = _ctrl.machines[i];
                              return MachineCard(
                                key: ValueKey(m.id),
                                machine: m,
                                onQr: () => _showQr(m),
                                onEdit: () => _editMachine(m),
                                onReset: () => _ctrl.resetMachine(m.id),
                                onDelete: () => _deleteMachine(m),
                                onOpen: () => _openMachine(m),
                              );
                            },
                            childCount: _ctrl.machines.length,
                          ),
                        );
                      },
                    ),
                  ),

                // ---- 3D game admin panel ----
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: GamePanel(),
                  ),
                ),

                // ---- event feed ----
                if (_ctrl.events.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                      child: _EventFeed(events: _ctrl.events),
                    ),
                  ),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addMachine,
          backgroundColor: AppColors.dashBlue,
          foregroundColor: Colors.white,
          elevation: 2,
          icon: const Icon(Icons.add),
          label: const Text(
            '暗号機を追加',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

/// ---------- top stats ----------
class _StatsHeader extends StatelessWidget {
  final DashboardController ctrl;
  const _StatsHeader({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 640;
            final stats = [
              _StatItem(
                label: '暗号機',
                value: '${ctrl.machines.length}',
                unit: '台',
                color: AppColors.dashInk,
              ),
              _StatItem(
                label: 'オンライン',
                value: '${ctrl.onlineCount}',
                unit: '台',
                color: AppColors.dashGreen,
              ),
              _StatItem(
                label: '解読完了',
                value: '${ctrl.completedCount}',
                unit: '台',
                color: AppColors.dashBlue,
              ),
            ];
            final progress = _OverallProgress(value: ctrl.overallProgress);

            if (narrow) {
              return Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: stats,
                  ),
                  const SizedBox(height: 20),
                  progress,
                ],
              );
            }
            return Row(
              children: [
                ...stats.expand((s) => [s, const SizedBox(width: 48)]),
                Expanded(child: progress),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _StatItem({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppColors.dashGrey),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                height: 1,
                color: color,
              ),
            ),
            const SizedBox(width: 3),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                unit,
                style:
                    const TextStyle(fontSize: 13, color: AppColors.dashGrey),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OverallProgress extends StatelessWidget {
  final double value; // 0..100
  const _OverallProgress({required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '全体進捗',
              style: TextStyle(fontSize: 13, color: AppColors.dashGrey),
            ),
            const Spacer(),
            TweenAnimationBuilder<double>(
              tween: Tween(end: value),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Text(
                '${v.toStringAsFixed(1)}%',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.dashBlue,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TweenAnimationBuilder<double>(
          tween: Tween(end: value / 100),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: v,
              minHeight: 10,
              backgroundColor: AppColors.dashLine,
              valueColor: const AlwaysStoppedAnimation(AppColors.dashBlue),
            ),
          ),
        ),
      ],
    );
  }
}

/// ---------- all completed banner ----------
class _AllCompletedBanner extends StatelessWidget {
  const _AllCompletedBanner();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Transform.scale(
        scale: 0.95 + v * 0.05,
        child: Opacity(opacity: v.clamp(0, 1), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF188038), Color(0xFF34A853)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          children: [
            Icon(Icons.celebration, color: Colors.white, size: 28),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                '全ての暗号機の解読が完了しました！ ゲートが開きます！',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------- empty state ----------
class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F3F4),
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(Icons.memory,
                size: 44, color: AppColors.dashGrey),
          ),
          const SizedBox(height: 24),
          const Text(
            'まだ暗号機がありません',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            '暗号機を追加してQRコードを展示に設置しましょう',
            style: TextStyle(fontSize: 14, color: AppColors.dashGrey),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('最初の暗号機を追加'),
          ),
        ],
      ),
    );
  }
}

/// ---------- event feed ----------
class _EventFeed extends StatelessWidget {
  final List<MachineEvent> events;
  const _EventFeed({required this.events});

  IconData _icon(String type) {
    switch (type) {
      case 'completed':
        return Icons.check_circle_outline;
      case 'connected':
        return Icons.link;
      case 'disconnected':
        return Icons.link_off;
      case 'created':
        return Icons.add_circle_outline;
      case 'deleted':
        return Icons.delete_outline;
      case 'reset':
        return Icons.restart_alt;
      case 'skill_miss':
        return Icons.flash_on;
      default:
        return Icons.info_outline;
    }
  }

  Color _color(String type) {
    switch (type) {
      case 'completed':
        return AppColors.dashGreen;
      case 'connected':
        return AppColors.dashBlue;
      case 'disconnected':
      case 'skill_miss':
        return AppColors.dashAmber;
      case 'deleted':
        return AppColors.dashRed;
      default:
        return AppColors.dashGrey;
    }
  }

  String _time(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.history, size: 18, color: AppColors.dashGrey),
                SizedBox(width: 8),
                Text(
                  'アクティビティ',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...events.take(12).map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(_icon(e.type), size: 17, color: _color(e.type)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            e.message,
                            style: const TextStyle(fontSize: 13.5),
                          ),
                        ),
                        Text(
                          _time(e.at),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.dashGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// ---------- connection badge ----------
class _ConnBadge extends StatelessWidget {
  final bool connected;
  const _ConnBadge({required this.connected});

  @override
  Widget build(BuildContext context) {
    final color = connected ? AppColors.dashGreen : AppColors.dashAmber;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 8),
          Text(
            connected ? 'リアルタイム接続中' : '再接続中...',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
