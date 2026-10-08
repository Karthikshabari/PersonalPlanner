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

/// Words offered under "How did the week feel?".
const List<String> weeklyFeelingWords = [
  'Focused',
  'Calm',
  'Energised',
  'Busy',
  'Tired',
  'Proud',
];

/// The feeling text after tapping [word], or null when the tap is ignored
/// because the result would exceed [maxWeeklyFeelingLength] (spec 3.6).
///
/// * empty field (or only whitespace): the word as written;
/// * text ending in whitespace: the word in lower case, no extra space;
/// * text ending in `.`, `!`, `?` or `,`: one space, then the word in lower
///   case;
/// * any other ending: `, ` then the word in lower case (WD20).
String? appendFeelingWord(String current, String word) {
  final String next;
  if (current.trim().isEmpty) {
    next = word;
  } else {
    final last = String.fromCharCode(current.runes.last);
    final lower = word.toLowerCase();
    if (RegExp(r'\s').hasMatch(last)) {
      next = '$current$lower';
    } else if (const {'.', '!', '?', ','}.contains(last)) {
      next = '$current $lower';
    } else {
      next = '$current, $lower';
    }
  }
  return next.runes.length > maxWeeklyFeelingLength ? null : next;
}

/// A starter chip of the "Next week" tab: [label] is shown, [insert] is
/// written into the empty note field.
class WeeklyNoteStarter {
  const WeeklyNoteStarter(this.label, this.insert);

  final String label;
  final String insert;
}

const List<WeeklyNoteStarter> weeklyNoteStarters = [
  WeeklyNoteStarter('Start with…', 'Start with '),
  WeeklyNoteStarter('Protect time for…', 'Protect time for '),
  WeeklyNoteStarter('Say no to…', 'Say no to '),
  WeeklyNoteStarter('Keep doing…', 'Keep doing '),
];

/// The note after tapping a starter: [insert] when the field is empty (or
/// only whitespace), otherwise null (the tap does nothing; WD21).
String? applyNoteStarter(String current, String insert) =>
    current.trim().isEmpty ? insert : null;
