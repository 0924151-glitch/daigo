import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/machine.dart';
import '../../theme/app_theme.dart';

/// ---------- QR / URL dialog ----------
Future<void> showQrDialog(
  BuildContext context, {
  required Machine machine,
  required String url,
}) {
  return showDialog(
    context: context,
    builder: (context) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                machine.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '解読機ページへのアクセス',
                style: TextStyle(fontSize: 13, color: AppColors.dashGrey),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.dashLine),
                ),
                child: QrImageView(
                  data: url,
                  version: QrVersions.auto,
                  size: 220,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.circle,
                    color: AppColors.dashInk,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.circle,
                    color: AppColors.dashInk,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // URL row with copy button
              Container(
                padding: const EdgeInsets.only(left: 16, right: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F3F4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.dashGrey,
                        ),
                      ),
                    ),
                    _CopyButton(url: url),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('閉じる'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CopyButton extends StatefulWidget {
  final String url;
  const _CopyButton({required this.url});

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: widget.url));
        if (!mounted) return;
        setState(() => _copied = true);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _copied = false);
        });
      },
      icon: Icon(
        _copied ? Icons.check : Icons.copy,
        size: 16,
        color: _copied ? AppColors.dashGreen : AppColors.dashBlue,
      ),
      label: Text(
        _copied ? 'コピー済み' : 'コピー',
        style: TextStyle(
          fontSize: 13,
          color: _copied ? AppColors.dashGreen : AppColors.dashBlue,
        ),
      ),
    );
  }
}

/// ---------- create / edit machine dialog ----------
/// Returns (name, durationSec) or null when cancelled.
Future<({String name, int durationSec})?> showMachineFormDialog(
  BuildContext context, {
  Machine? existing,
}) {
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  final isEdit = existing != null;
  int duration = existing?.durationSec ?? 60;

  return showDialog<({String name, int durationSec})>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: Colors.white,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEdit ? '暗号機の設定を変更' : '暗号機を追加',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '暗号機の名前',
                      hintText: '例: 暗号機 A / 教室前 / 廊下1',
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      const Text(
                        '解読時間',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _fmtDuration(duration),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.dashBlue,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: duration.toDouble(),
                    min: 10,
                    max: 600,
                    divisions: 59,
                    activeColor: AppColors.dashBlue,
                    onChanged: (v) =>
                        setState(() => duration = (v / 10).round() * 10),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final preset in [30, 60, 120, 300])
                        _PresetChip(
                          label: _fmtDuration(preset),
                          selected: duration == preset,
                          onTap: () => setState(() => duration = preset),
                        ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'キャンセル',
                          style: TextStyle(color: AppColors.dashGrey),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          final name = nameCtrl.text.trim();
                          if (name.isEmpty) return;
                          Navigator.pop(
                            context,
                            (name: name, durationSec: duration),
                          );
                        },
                        child: Text(isEdit ? '保存' : '追加'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

String _fmtDuration(int sec) {
  if (sec < 60) return '$sec秒';
  final m = sec ~/ 60;
  final s = sec % 60;
  return s == 0 ? '$m分' : '$m分$s秒';
}

class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.dashBlue.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? AppColors.dashBlue : AppColors.dashLine,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? AppColors.dashBlue : AppColors.dashGrey,
            ),
          ),
        ),
      ),
    );
  }
}

/// ---------- delete confirm ----------
Future<bool> showDeleteConfirmDialog(
  BuildContext context, {
  required Machine machine,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: AppColors.dashRed, size: 26),
                  SizedBox(width: 12),
                  Text(
                    '暗号機を撤去',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '「${machine.name}」を撤去しますか？\n進捗データも削除され、開いている解読ページは使用できなくなります。',
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.7,
                  color: AppColors.dashGrey,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text(
                      'キャンセル',
                      style: TextStyle(color: AppColors.dashGrey),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.dashRed,
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('撤去する'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return result ?? false;
}
