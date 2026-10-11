import 'dart:convert';

import '../../../core/models/day_context.dart';

const String dayContextPresetsSettingKey = 'day_context_presets';
const int maxDayContextPresets = 8;
const int maxDayContextPresetNameLength = 24;

/// One choice in the "Add day context" dialog. [isBreak] marks a break day:
/// it is left out of every daily and weekly figure (see `BreakDayRule`).
class DayContextPreset {
  const DayContextPreset(this.name, {this.isBreak = false});

  final String name;
  final bool isBreak;

  DayContextPreset copyWith({String? name, bool? isBreak}) =>
      DayContextPreset(name ?? this.name, isBreak: isBreak ?? this.isBreak);

  @override
  bool operator ==(Object other) =>
      other is DayContextPreset &&
      other.name == name &&
      other.isBreak == isBreak;

  @override
  int get hashCode => Object.hash(name, isBreak);
}

const List<DayContextPreset> defaultDayContextPresets = [
  DayContextPreset('Office Day'),
  DayContextPreset('Work From Home'),
  DayContextPreset('Holiday / Festival', isBreak: true),
  DayContextPreset('Leave', isBreak: true),
  DayContextPreset('Travel'),
  DayContextPreset('Rest Day', isBreak: true),
];

/// Pure rules for the user's day context presets. Stored per device in
/// `app_settings`; not synced and not part of portable backup.
abstract final class DayContextPresets {
  /// The form names are compared in: case and spaces ignored.
  static String normalize(String name) =>
      name.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  /// Absent or invalid storage yields the defaults. Blank, too long and
  /// duplicate entries are dropped; at most 8 are kept.
  static List<DayContextPreset> decode(String? raw) {
    if (raw == null) return List.of(defaultDayContextPresets);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return List.of(defaultDayContextPresets);
      final result = <DayContextPreset>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final name = item['name'];
        if (name is! String) continue;
        final trimmed = name.trim();
        if (validateName(result, trimmed) != null) continue;
        result.add(DayContextPreset(trimmed, isBreak: item['break'] == true));
        if (result.length == maxDayContextPresets) break;
      }
      return result.isEmpty ? List.of(defaultDayContextPresets) : result;
    } on FormatException {
      return List.of(defaultDayContextPresets);
    }
  }

  static String encode(List<DayContextPreset> presets) => jsonEncode([
    for (final preset in presets)
      {'name': preset.name, 'break': preset.isBreak},
  ]);

  /// Null when [name] can be used; otherwise the message to show. [exceptIndex]
  /// is the preset being renamed, which may keep its own name.
  static String? validateName(
    List<DayContextPreset> presets,
    String name, {
    int? exceptIndex,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Enter a name';
    if (trimmed.length > maxDayContextPresetNameLength) {
      return 'Use $maxDayContextPresetNameLength characters or fewer';
    }
    final key = normalize(trimmed);
    for (var i = 0; i < presets.length; i++) {
      if (i == exceptIndex) continue;
      if (normalize(presets[i].name) == key) return 'Already in the list';
    }
    return null;
  }

  static bool canAdd(List<DayContextPreset> presets) =>
      presets.length < maxDayContextPresets;

  /// The stored kind for a preset name: a built-in kind when the name is that
  /// kind's label (so the default presets keep their existing rows), else
  /// custom with the name as its label.
  static DayContextKind kindForName(String name) {
    final key = normalize(name);
    for (final kind in DayContextKind.values) {
      if (kind != DayContextKind.custom && normalize(kind.label) == key) {
        return kind;
      }
    }
    return DayContextKind.custom;
  }

  /// The preset a day's label belongs to, or -1 (an old custom label, or a
  /// preset since renamed or deleted).
  static int indexOfLabel(List<DayContextPreset> presets, String label) {
    final key = normalize(label);
    return presets.indexWhere((preset) => normalize(preset.name) == key);
  }
}
