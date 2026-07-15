import 'package:flutter/material.dart';

/// Visual design preset for the cipher machine.
///
/// The machine itself is always the same "antique typewriter on a wooden
/// crate" silhouette (Identity V style); each preset only swaps materials:
/// body metal, crate wood, key caps, paper and lamp colors.
///
/// Keep the keys in sync with server/store.py VALID_DESIGNS.
class MachineDesign {
  /// Stable key stored on the server (e.g. "classic").
  final String key;

  /// Japanese display name for the dashboard.
  final String label;

  /// Short description shown in the design picker.
  final String description;

  // ---- machine body (typewriter) ----
  /// Main body metal color (upper shell).
  final Color body;

  /// Darker shade of the body (sides / shadowed faces).
  final Color bodyDark;

  /// Lighter shade of the body (top highlights).
  final Color bodyLight;

  /// Key caps color.
  final Color keyCap;

  /// Key cap legend (letter) color.
  final Color keyLegend;

  /// Platen (roller) color.
  final Color platen;

  /// Paper sheet color.
  final Color paper;

  /// Small dial / wheel accent color on the body.
  final Color dial;

  // ---- crate (wooden box under the machine) ----
  /// Crate plank base color.
  final Color crate;

  /// Crate plank dark edge / cross brace color.
  final Color crateDark;

  // ---- lights ----
  /// Indicator lamp color while decoding.
  final Color lampActive;

  /// Indicator lamp color when completed.
  final Color lampDone;

  /// Progress ink color (progress bar on the paper).
  final Color ink;

  const MachineDesign({
    required this.key,
    required this.label,
    required this.description,
    required this.body,
    required this.bodyDark,
    required this.bodyLight,
    required this.keyCap,
    required this.keyLegend,
    required this.platen,
    required this.paper,
    required this.dial,
    required this.crate,
    required this.crateDark,
    required this.lampActive,
    required this.lampDone,
    required this.ink,
  });
}

/// The 5 selectable presets. Order defines display order in the picker.
const List<MachineDesign> kMachineDesigns = [
  // 1. Classic black iron typewriter on dark oak - the reference image look.
  MachineDesign(
    key: 'classic',
    label: 'クラシック',
    description: '黒鉄のタイプライター。定番の姿。',
    body: Color(0xFF35322E),
    bodyDark: Color(0xFF211F1C),
    bodyLight: Color(0xFF4C4842),
    keyCap: Color(0xFF171614),
    keyLegend: Color(0xFFCFC9B8),
    platen: Color(0xFF141312),
    paper: Color(0xFFE8E2D0),
    dial: Color(0xFF8A8378),
    crate: Color(0xFF4A3C2E),
    crateDark: Color(0xFF32281D),
    lampActive: Color(0xFFD9A441),
    lampDone: Color(0xFF7FB069),
    ink: Color(0xFFD9A441),
  ),

  // 2. Mahogany & cream - warm wooden body like an old radio.
  MachineDesign(
    key: 'mahogany',
    label: 'マホガニー',
    description: '赤茶の木目とクリーム色の鍵盤。',
    body: Color(0xFF5C3226),
    bodyDark: Color(0xFF3D2018),
    bodyLight: Color(0xFF7A4634),
    keyCap: Color(0xFFE3D9BE),
    keyLegend: Color(0xFF4A3222),
    platen: Color(0xFF2A1B14),
    paper: Color(0xFFF0EAD8),
    dial: Color(0xFFC8A96A),
    crate: Color(0xFF6B4B33),
    crateDark: Color(0xFF4A3220),
    lampActive: Color(0xFFE0B054),
    lampDone: Color(0xFF8DBB74),
    ink: Color(0xFF9C4A3A),
  ),

  // 3. Military olive - field cipher unit, WW2 mood.
  MachineDesign(
    key: 'military',
    label: 'ミリタリー',
    description: '野戦仕様のオリーブ色の暗号機。',
    body: Color(0xFF4A4E38),
    bodyDark: Color(0xFF2F3324),
    bodyLight: Color(0xFF636A4C),
    keyCap: Color(0xFF23261B),
    keyLegend: Color(0xFFD5D2B8),
    platen: Color(0xFF1B1D15),
    paper: Color(0xFFDCD8C0),
    dial: Color(0xFF9A9878),
    crate: Color(0xFF54513B),
    crateDark: Color(0xFF383626),
    lampActive: Color(0xFFC9B458),
    lampDone: Color(0xFF86A65C),
    ink: Color(0xFF7C8354),
  ),

  // 4. Brass & copper - polished steampunk laboratory instrument.
  MachineDesign(
    key: 'brass',
    label: 'ブラス',
    description: '真鍮と銅の輝く実験装置。',
    body: Color(0xFF8A6B3A),
    bodyDark: Color(0xFF5E4726),
    bodyLight: Color(0xFFB08D4E),
    keyCap: Color(0xFF3C2E1A),
    keyLegend: Color(0xFFE8D9A8),
    platen: Color(0xFF4A3520),
    paper: Color(0xFFF2E9CE),
    dial: Color(0xFFD8B76A),
    crate: Color(0xFF5C4630),
    crateDark: Color(0xFF3E2F1F),
    lampActive: Color(0xFFE8C05C),
    lampDone: Color(0xFF9CBC6E),
    ink: Color(0xFFB0803A),
  ),

  // 5. Noir - almost monochrome, pale grey like the reference sketch.
  MachineDesign(
    key: 'noir',
    label: 'ノワール',
    description: '灰白のモノトーン。素描のような静けさ。',
    body: Color(0xFF6E6E70),
    bodyDark: Color(0xFF4A4A4C),
    bodyLight: Color(0xFF919194),
    keyCap: Color(0xFF2E2E30),
    keyLegend: Color(0xFFD8D8DA),
    platen: Color(0xFF252527),
    paper: Color(0xFFEDEDEA),
    dial: Color(0xFFAAAAAC),
    crate: Color(0xFF5A5654),
    crateDark: Color(0xFF3C3937),
    lampActive: Color(0xFFC8C0A8),
    lampDone: Color(0xFF9CB894),
    ink: Color(0xFF8E8E90),
  ),
];

/// Look up a design by key; unknown keys fall back to the first (classic).
MachineDesign machineDesignByKey(String key) {
  for (final d in kMachineDesigns) {
    if (d.key == key) return d;
  }
  return kMachineDesigns.first;
}
