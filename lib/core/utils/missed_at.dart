/// Canonical codec for the task `missed_at` field.
///
/// The persisted format is a UTC minute without a zone suffix for compatibility
/// with released clients. A suffix-bearing value is accepted at boundaries and
/// normalized back to that same wire/storage shape.
abstract final class MissedAtCodec {
  static final RegExp _naiveMinute = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$',
  );
  static final RegExp _zoned = RegExp(
    r'T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:\d{2})$',
  );

  /// Parses a marker as an instant, interpreting the documented zone-less
  /// minute representation as UTC exactly once.
  static DateTime? parse(String? value) {
    if (value == null) return null;
    final naive = _naiveMinute.firstMatch(value);
    if (naive != null) {
      final year = int.parse(naive.group(1)!);
      final month = int.parse(naive.group(2)!);
      final day = int.parse(naive.group(3)!);
      final hour = int.parse(naive.group(4)!);
      final minute = int.parse(naive.group(5)!);
      final parsed = DateTime.tryParse('$value:00Z');
      if (parsed == null ||
          parsed.year != year ||
          parsed.month != month ||
          parsed.day != day ||
          parsed.hour != hour ||
          parsed.minute != minute) {
        return null;
      }
      return parsed;
    }
    if (!_zoned.hasMatch(value)) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  /// Returns the established UTC-minute representation, or null for malformed
  /// input. Null input remains null.
  static String? normalize(String? value) {
    final parsed = parse(value);
    if (parsed == null) return null;
    return parsed.toUtc().toIso8601String().substring(0, 16);
  }

  static String formatUtcMinute(DateTime instant) =>
      instant.toUtc().toIso8601String().substring(0, 16);
}
