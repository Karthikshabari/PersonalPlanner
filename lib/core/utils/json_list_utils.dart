import 'dart:convert';

/// Helpers for the `tags_json` / `exceptions_json` TEXT columns, which hold
/// a JSON array of strings (architecture.md §3).
abstract final class JsonListUtils {
  static String encode(List<String> values) => jsonEncode(values);

  /// Never throws; malformed or empty values decode to an empty list.
  static List<String> decode(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) return decoded.whereType<String>().toList();
    } catch (_) {}
    return const [];
  }
}
