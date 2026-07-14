import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/machine.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

/// Dashboard state: live machine list + event feed via WebSocket,
/// CRUD via REST. Auto-reconnects.
class DashboardController extends ChangeNotifier {
  List<Machine> machines = [];
  List<MachineEvent> events = [];
  bool allCompleted = false;
  bool connected = false;
  bool loading = true;
  String? error;

  SocketService? _socket;
  StreamSubscription? _msgSub;
  StreamSubscription? _statusSub;

  void init() {
    _socket = SocketService('/ws/dashboard', autoReconnect: true);
    _msgSub = _socket!.messages.listen(_onMessage);
    _statusSub = _socket!.connectionStatus.listen((ok) {
      connected = ok;
      notifyListeners();
    });
    _socket!.connect();
    // REST fallback for the initial paint
    _loadOnce();
  }

  Future<void> _loadOnce() async {
    try {
      machines = await ApiService.instance.listMachines();
      loading = false;
      notifyListeners();
    } catch (e) {
      loading = false;
      error = '$e';
      notifyListeners();
    }
  }

  void _onMessage(Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'state':
        machines = (msg['machines'] as List)
            .map((e) => Machine.fromJson(e as Map<String, dynamic>))
            .toList();
        allCompleted = (msg['all_completed'] as bool?) ?? false;
        if (msg['events'] != null) {
          events = (msg['events'] as List)
              .map((e) => MachineEvent.fromJson(e as Map<String, dynamic>))
              .toList()
              .reversed
              .toList();
        }
        loading = false;
        notifyListeners();
        break;
      case 'event':
        final ev =
            MachineEvent.fromJson(msg['event'] as Map<String, dynamic>);
        events.insert(0, ev);
        if (events.length > 60) events = events.sublist(0, 60);
        notifyListeners();
        break;
    }
  }

  // ---------- aggregates ----------
  double get overallProgress {
    if (machines.isEmpty) return 0;
    final total = machines.fold<double>(0, (s, m) => s + m.progress);
    return total / machines.length;
  }

  int get completedCount => machines.where((m) => m.isCompleted).length;
  int get onlineCount => machines.where((m) => m.connected).length;

  // ---------- CRUD ----------
  Future<void> createMachine(String name, int durationSec) async {
    await ApiService.instance
        .createMachine(name: name, durationSec: durationSec);
  }

  Future<void> updateMachine(String id,
      {String? name, int? durationSec}) async {
    await ApiService.instance
        .updateMachine(id, name: name, durationSec: durationSec);
  }

  Future<void> deleteMachine(String id) async {
    await ApiService.instance.deleteMachine(id);
  }

  Future<void> resetMachine(String id) async {
    await ApiService.instance.resetMachine(id);
  }

  String machineUrl(String id) => ApiService.instance.machineUrl(id);

  @override
  void dispose() {
    _msgSub?.cancel();
    _statusSub?.cancel();
    _socket?.dispose();
    super.dispose();
  }
}
