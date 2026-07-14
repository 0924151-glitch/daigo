import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/machine.dart';
import '../services/socket_service.dart';

/// Connection phase of the decoder page.
enum DecoderPhase { connecting, ready, locked, notFound, deleted }

/// Skill check (QTE) state.
class SkillCheck {
  /// Needle angle 0..1 (one full sweep).
  double needle = 0;

  /// Success zone start (0..1) and width (fraction).
  final double zoneStart;
  final double zoneWidth;

  /// Sweep duration.
  final Duration sweep;

  bool resolved = false;

  SkillCheck({
    required this.zoneStart,
    required this.zoneWidth,
    required this.sweep,
  });

  bool get needleInZone =>
      needle >= zoneStart && needle <= zoneStart + zoneWidth;
}

/// All decoding game logic, separated from UI.
///
/// - Hold to decode: progress advances while holding.
/// - Random skill checks: tap (release & re-press quickly is NOT needed;
///   we use a dedicated tap while holding = SPACE key or second tap).
/// - Miss => progress penalty + electric shock effect.
class DecoderController extends ChangeNotifier {
  final String machineId;

  Machine? machine;
  DecoderPhase phase = DecoderPhase.connecting;
  String? errorReason;

  // --- decode state ---
  double progress = 0; // 0..100
  bool holding = false;
  bool get completed => progress >= 100;

  // --- skill check ---
  SkillCheck? skill;
  int comboSuccess = 0;
  bool shockActive = false; // electric shock overlay
  bool perfectFlash = false; // perfect zone flash
  int skillSuccessCount = 0;
  int skillMissCount = 0;

  // --- calibration (fun extra): occasional "sparks" boost ---
  bool sparkActive = false;

  SocketService? _socket;
  StreamSubscription? _msgSub;
  Timer? _ticker;
  Timer? _skillTimer;
  Timer? _shockTimer;
  Timer? _sparkTimer;
  final _rand = Random();

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
        skillSuccessCount = machine!.skillSuccess;
        skillMissCount = machine!.skillMiss;
        phase = DecoderPhase.ready;
        _startTicker();
        notifyListeners();
        break;
      case 'settings':
        final updated = Machine.fromJson(msg['machine'] as Map<String, dynamic>);
        machine = updated;
        notifyListeners();
        break;
      case 'reset':
        progress = 0;
        comboSuccess = 0;
        skillSuccessCount = 0;
        skillMissCount = 0;
        skill = null;
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
    _scheduleSkillCheck();
    notifyListeners();
  }

  void endHold() {
    if (!holding) return;
    holding = false;
    _skillTimer?.cancel();
    // releasing during an active skill check = miss
    if (skill != null && !skill!.resolved) {
      _resolveSkill(false);
    }
    _sendProgress(completed ? 'completed' : 'paused');
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    _lastTick = DateTime.now();
    _ticker = Timer.periodic(const Duration(milliseconds: 33), (_) => _tick());
  }

  void _tick() {
    final now = DateTime.now();
    final dt = now.difference(_lastTick).inMilliseconds / 1000.0;
    _lastTick = now;

    bool dirty = false;

    // advance skill check needle
    if (skill != null && !skill!.resolved) {
      skill!.needle += dt / (skill!.sweep.inMilliseconds / 1000.0);
      if (skill!.needle >= 1.0) {
        _resolveSkill(false); // needle passed the zone -> miss
      }
      dirty = true;
    }

    if (holding && !completed && (skill == null || skill!.resolved)) {
      double rate = _ratePerSec;
      if (sparkActive) rate *= 1.6; // spark boost
      progress = (progress + rate * dt).clamp(0, 100);
      if (completed) {
        progress = 100;
        holding = false;
        _skillTimer?.cancel();
        _sendProgress('completed');
      } else {
        _throttledSend();
      }
      dirty = true;
    }

    if (dirty) notifyListeners();
  }

  // ------------------------------------------------------------------
  // skill check (QTE)
  // ------------------------------------------------------------------
  void _scheduleSkillCheck() {
    _skillTimer?.cancel();
    // first check comes 3-8s after starting to hold, then keeps rolling
    final delayMs = 3000 + _rand.nextInt(5000);
    _skillTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!holding || completed || phase != DecoderPhase.ready) return;
      _spawnSkillCheck();
    });
  }

  void _spawnSkillCheck() {
    // zone placed in latter 40-80% of sweep, width ~12-18%
    final zoneStart = 0.45 + _rand.nextDouble() * 0.3;
    final zoneWidth = 0.12 + _rand.nextDouble() * 0.06;
    skill = SkillCheck(
      zoneStart: zoneStart,
      zoneWidth: zoneWidth,
      sweep: Duration(milliseconds: 1100 + _rand.nextInt(300)),
    );
    notifyListeners();
  }

  /// Called by UI when player taps / presses SPACE during a skill check.
  void hitSkillCheck() {
    final s = skill;
    if (s == null || s.resolved) return;
    _resolveSkill(s.needleInZone, perfect: _isPerfect(s));
  }

  bool _isPerfect(SkillCheck s) {
    final center = s.zoneStart + s.zoneWidth / 2;
    return (s.needle - center).abs() < s.zoneWidth * 0.18;
  }

  void _resolveSkill(bool success, {bool perfect = false}) {
    final s = skill;
    if (s == null || s.resolved) return;
    s.resolved = true;

    if (success) {
      comboSuccess++;
      skillSuccessCount++;
      if (perfect) {
        progress = (progress + 3).clamp(0, 100); // perfect bonus
        perfectFlash = true;
        Timer(const Duration(milliseconds: 600), () {
          perfectFlash = false;
          notifyListeners();
        });
      } else {
        progress = (progress + 1).clamp(0, 100);
      }
      _socket?.send({'type': 'skill', 'success': true});
      // random spark boost after 3+ combo
      if (comboSuccess >= 3 && _rand.nextDouble() < 0.35) {
        _activateSpark();
      }
    } else {
      comboSuccess = 0;
      skillMissCount++;
      progress = (progress - 8).clamp(0, 100); // penalty
      shockActive = true;
      _socket?.send({'type': 'skill', 'success': false});
      _shockTimer?.cancel();
      _shockTimer = Timer(const Duration(milliseconds: 900), () {
        shockActive = false;
        notifyListeners();
      });
    }

    if (completed) {
      progress = 100;
      holding = false;
      _sendProgress('completed');
    } else {
      _throttledSend(force: true);
    }

    // remove skill widget shortly after resolve, then schedule next
    Timer(const Duration(milliseconds: 350), () {
      skill = null;
      notifyListeners();
      if (holding && !completed) _scheduleSkillCheck();
    });
    notifyListeners();
  }

  void _activateSpark() {
    sparkActive = true;
    notifyListeners();
    _sparkTimer?.cancel();
    _sparkTimer = Timer(const Duration(seconds: 4), () {
      sparkActive = false;
      notifyListeners();
    });
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
    _skillTimer?.cancel();
    holding = false;
  }

  @override
  void dispose() {
    _stopAll();
    _shockTimer?.cancel();
    _sparkTimer?.cancel();
    _msgSub?.cancel();
    _socket?.dispose();
    _ticker?.cancel();
    super.dispose();
  }
}
