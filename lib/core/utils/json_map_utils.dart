import 'dart:convert';

/// Helpers for TEXT columns holding a JSON object of short user-written
/// reasons keyed by an ID (`daily_reviews.task_reasons_json`,
/// `tasks.plan_change_reasons_json`).
abstract final class JsonMapUtils {
  /// Defensive storage bound in UTF-16 code units. The UI limits input to
  /// 140 characters; one character can take several code units.
  static const int maxStoredReasonLength = 1000;

  /// Canonical text: keys sorted so equal maps encode identically.
  static String encode(Map<String, String> values) {
    final keys = values.keys.toList()..sort();
    return jsonEncode({for (final key in keys) key: values[key]});
  }

  /// Never throws. Malformed text decodes to an empty map; non-string
  /// entries are dropped.
  static Map<String, String> decode(String? json) {
    if (json == null || json.isEmpty) return const <String, String>{};
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map) {
        return {
          for (final entry in decoded.entries)
            if (entry.key is String && entry.value is String)
              entry.key as String: entry.value as String,
        };
      }
    } on FormatException {
      // Fall through to the empty map.
    }
    return const <String, String>{};
  }

  /// Strict check for persistence, sync and backup boundaries. Accepts JSON
  /// text or an already decoded map. Values must be trimmed and non-blank.
  static Map<String, String> parseReasons(Object? raw) {
    Object? decoded = raw;
    if (raw is String) {
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        throw const FormatException('Reasons must be a JSON object.');
      }
    }
    if (decoded is! Map) {
      throw const FormatException('Reasons must be a JSON object.');
    }
    final result = <String, String>{};
    for (final entry in decoded.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String ||
          key.isEmpty ||
          value is! String ||
          value.trim().isEmpty ||
          value != value.trim() ||
          value.length > maxStoredReasonLength) {
        throw const FormatException(
          'Reasons must map IDs to trimmed, non-blank text.',
        );
      }
      result[key] = value;
    }
    return result;
  }
}
