/// Longest "How did the week feel?" answer, in Unicode code points. SQLite
/// `length()` and Postgres `char_length()` count the same unit.
const int maxWeeklyFeelingLength = 200;

/// Longest note for next week, in characters (UI limit only; WD8).
const int maxWeeklyNoteLength = 140;

/// Trimmed and clipped to [maxWeeklyFeelingLength] code points. Null stays
/// null ("no feeling saved"); an empty answer stays '' so a cleared feeling
/// is never mistaken for an older client's missing value (WD6).
String? normalizeWeeklyFeeling(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  final runes = trimmed.runes;
  if (runes.length <= maxWeeklyFeelingLength) return trimmed;
  return String.fromCharCodes(runes.take(maxWeeklyFeelingLength)).trimRight();
}
