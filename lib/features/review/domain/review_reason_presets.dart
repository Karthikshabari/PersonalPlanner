import 'dart:convert';

const String reviewReasonPresetsSettingKey = 'review_reason_presets';
const List<String> defaultReviewReasonPresets = [
  'Ran out of time',
  'Interrupted',
  'Lower priority',
  'Blocked',
  'Low energy',
];
const int maxReviewReasonPresets = 6;
const int maxReviewReasonPresetLength = 28;
const int maxReviewReasonLength = 140;

/// Pure rules for the user-defined quick reasons.
abstract final class ReviewReasonPresets {
  /// Absent or invalid storage yields the defaults; a stored empty list stays
  /// empty. Entries are capped at 6 and 28 characters.
  static List<String> decode(String? raw) {
    if (raw == null) return List.of(defaultReviewReasonPresets);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.any((item) => item is! String)) {
        return List.of(defaultReviewReasonPresets);
      }
      return [
        for (final value in decoded.cast<String>().take(maxReviewReasonPresets))
          value.length > maxReviewReasonPresetLength
              ? value.substring(0, maxReviewReasonPresetLength)
              : value,
      ];
    } on FormatException {
      return List.of(defaultReviewReasonPresets);
    }
  }

  static String encode(List<String> presets) => jsonEncode(presets);

  /// The chips shown under a reason field: non-blank, trimmed.
  static List<String> chips(List<String> presets) => [
    for (final preset in presets)
      if (preset.trim().isNotEmpty) preset.trim(),
  ];

  static bool canSaveAsPreset(List<String> presets, String text) {
    final value = text.trim();
    if (value.isEmpty || value.length > maxReviewReasonPresetLength) {
      return false;
    }
    if (chips(presets).length >= maxReviewReasonPresets) return false;
    final lower = value.toLowerCase();
    return !presets.any((preset) => preset.trim().toLowerCase() == lower);
  }

  /// Fills the first blank slot, or appends.
  static List<String> withSaved(List<String> presets, String text) {
    final value = text.trim();
    final next = List.of(presets);
    final blank = next.indexWhere((preset) => preset.trim().isEmpty);
    if (blank >= 0) {
      next[blank] = value;
    } else {
      next.add(value);
    }
    return next;
  }
}
