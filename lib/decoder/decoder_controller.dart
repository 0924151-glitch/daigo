import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/machine.dart';
import '../services/socket_service.dart';

/// Connection phase of the decoder page.
enum DecoderPhase { connecting, ready, locked, notFound, deleted }

/// Decoding logic, separated from UI.
///
/// Interaction is intentionally simple:
/// hold the machine => progress advances; release => pause.
/// (The old skill-check QTE was removed by design.)
class DecoderController extends ChangeNotifier {
  final String machineId;

  Machine? machine;
  DecoderPhase phase = DecoderPhase.connecting;
  String? errorReason;

  // --- decode state ---
  double progress = 0; // 0..100
  bool holding = false;
  bool get completed => progress >= 100;

  SocketService? _socket;
  StreamSubscription? _msgSub;
  Timer? _ticker;

  DateTime _lastTick = DateTime.now();
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  DecoderController(this.machineId);

  double get durationSec =>
      (machine?.durationSec ?? 60).clamp(5, 3600).toDouble();

  /// Progress gained per second while holding.
  double get _ratePerSec => 100.0 / durationSec;

  // ------------------------------------------------------------------
  // lifecycle
  // ------------------------------------------------------------------
  void connect() {
    phase = DecoderPhase.connecting;
    notifyListeners();
    _socket = SocketService('/ws/machine/$machineId');
    _msgSub = _socket!.messages.listen(_onMessage);
    _socket!.connect();
  }

  void _onMessage(Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'init':
        machine = Machine.fromJson(msg['machine'] as Map<String, dynamic>);
        progress = machine!.progress;
        phase = DecoderPhase.ready;
        _startTicker();
        notifyListeners();
        break;
      case 'settings':
        // live settings update (name / duration / design)
        machine = Machine.fromJson(msg['machine'] as Map<String, dynamic>);
        notifyListeners();
        break;
      case 'reset':
        progress = 0;
        holding = false;
        _sendProgress('idle');
        notifyListeners();
        break;
      case 'deleted':
        phase = DecoderPhase.deleted;
        _stopAll();
        notifyListeners();
        break;
      case 'error':
        final reason = msg['reason'] as String?;
        if (reason == 'locked') {
          phase = DecoderPhase.locked;
        } else if (reason == 'not_found') {
          phase = DecoderPhase.notFound;
        }
        errorReason = reason;
        _stopAll();
        notifyListeners();
        break;
    }
  }

  // ------------------------------------------------------------------
  // hold to decode
  // ------------------------------------------------------------------
  void startHold() {
    if (phase != DecoderPhase.ready || completed) return;
    holding = true;
    _lastTick = DateTime.now();
    notifyListeners();
  }

  void endHold() {
    if (!holding) return;
    holding = false;
    _sendProgress(completed ? 'completed' : 'paused');
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    _lastTick = DateTime.now();
    _ticker = Timer.periodic(const Duration(milliseconds: 33), (_) => _tick());
  }

  void _tick() {
    if (!holding || completed) return;

    final now = DateTime.now();
    final dt = now.difference(_lastTick).inMilliseconds / 1000.0;
    _lastTick = now;

    progress = (progress + _ratePerSec * dt).clamp(0, 100);
    if (completed) {
      progress = 100;
      holding = false;
      _sendProgress('completed');
    } else {
      _throttledSend();
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // networking
  // ------------------------------------------------------------------
  void _throttledSend({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastSent).inMilliseconds < 200) return;
    _lastSent = now;
    _sendProgress(holding ? 'decoding' : 'paused');
  }

  void _sendProgress(String status) {
    _socket?.send({
      'type': 'progress',
      'progress': double.parse(progress.toStringAsFixed(2)),
      'status': status,
    });
  }

  void _stopAll() {
    _ticker?.cancel();
    holding = false;
  }

  @override
  void dispose() {
    _stopAll();
    _msgSub?.cancel();
    _socket?.dispose();
    super.dispose();
  }
}
