import 'dart:convert';

const String weeklyFeelingPresetsSettingKey = 'weekly_feeling_presets';
const List<String> defaultWeeklyFeelingPresets = [
  'Focused',
  'Calm',
  'Tired',
  'Proud',
];
const int weeklyFeelingPresetCount = 4;
const int maxWeeklyFeelingPresetLength = 14;

/// Pure rules for the four user-defined "How did the week feel?" words.
abstract final class WeeklyFeelingPresets {
  /// Always exactly [weeklyFeelingPresetCount] valid, distinct labels. Absent,
  /// invalid, blank, over-long or duplicate slots fall back to a default.
  static List<String> decode(String? raw) {
    var stored = const <Object?>[];
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) stored = decoded;
      } on FormatException {
        // Falls through to the defaults.
      }
    }
    final result = <String>[];
    bool taken(String value) =>
        result.any((item) => item.toLowerCase() == value.toLowerCase());
    for (var i = 0; i < weeklyFeelingPresetCount; i++) {
      final value = i < stored.length && stored[i] is String
          ? (stored[i] as String).trim()
          : '';
      final usable =
          value.isNotEmpty &&
          value.length <= maxWeeklyFeelingPresetLength &&
          !taken(value);
      result.add(usable ? value : '');
    }
    // Unset slots take the slot's own default, else the first unused one.
    for (var i = 0; i < weeklyFeelingPresetCount; i++) {
      if (result[i].isNotEmpty) continue;
      final own = defaultWeeklyFeelingPresets[i];
      result[i] = !taken(own)
          ? own
          : defaultWeeklyFeelingPresets.firstWhere((item) => !taken(item));
    }
    return result;
  }

  static String encode(List<String> presets) => jsonEncode(presets);

  /// Null when [text] can be stored in slot [index], else a short message.
  static String? validate(List<String> presets, int index, String text) {
    final value = text.trim();
    if (value.isEmpty) return 'Enter a word.';
    if (value.length > maxWeeklyFeelingPresetLength) {
      return 'Up to $maxWeeklyFeelingPresetLength characters.';
    }
    final lower = value.toLowerCase();
    for (var i = 0; i < presets.length; i++) {
      if (i != index && presets[i].trim().toLowerCase() == lower) {
        return 'Already used.';
      }
    }
    return null;
  }
}
