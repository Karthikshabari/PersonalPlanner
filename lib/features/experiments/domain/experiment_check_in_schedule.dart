import 'package:intl/intl.dart';

import '../../../core/utils/date_utils.dart';

/// The only check-in slot implementation in the app (section 2.4, R19, R20).
///
/// Slot k (1, 2, 3, ...) is due on `start + k * frequency - 1` days, as long
/// as that date is not after the end date. Every sum is calendar-day
/// arithmetic through [addDays]; a 24-hour duration is never added. Dates are
/// `yyyy-MM-dd` text, which sorts the same as the dates it names.

/// The slot dates of an experiment, earliest first. Empty when the window is
/// shorter than the first slot.
List<String> experimentSlotDates({
  required String startDate,
  required String endDate,
  required int checkInEveryDays,
}) {
  if (checkInEveryDays < 1) {
    throw ArgumentError.value(
      checkInEveryDays,
      'checkInEveryDays',
      'must be at least 1',
    );
  }
  final start = parseIsoDate(startDate);
  final slots = <String>[];
  for (var k = 1; ; k++) {
    final due = isoDateString(addDays(start, k * checkInEveryDays - 1));
    if (due.compareTo(endDate) > 0) break;
    slots.add(due);
  }
  return slots;
}

/// What is owed and what comes next, given which slots are already written.
class ExperimentCheckInStatus {
  const ExperimentCheckInStatus({
    required this.pendingDates,
    required this.missedCount,
    required this.dueToday,
    required this.nextSlot,
  });

  /// Slots dated today or earlier with no check-in, earliest first.
  final List<String> pendingDates;

  /// Pending slots dated before today.
  final int missedCount;

  /// Whether a pending slot is dated today.
  final bool dueToday;

  /// The earliest slot dated after today, or null.
  final String? nextSlot;
}

/// Builds the [ExperimentCheckInStatus] for [today] (a `yyyy-MM-dd` date).
ExperimentCheckInStatus experimentCheckInStatus({
  required String startDate,
  required String endDate,
  required int checkInEveryDays,
  required Iterable<String> writtenSlotDates,
  required String today,
}) {
  final slots = experimentSlotDates(
    startDate: startDate,
    endDate: endDate,
    checkInEveryDays: checkInEveryDays,
  );
  final written = writtenSlotDates.toSet();
  final pending = <String>[];
  String? next;
  for (final slot in slots) {
    if (slot.compareTo(today) <= 0) {
      if (!written.contains(slot)) pending.add(slot);
    } else {
      next = slot;
      break;
    }
  }
  return ExperimentCheckInStatus(
    pendingDates: List.unmodifiable(pending),
    missedCount: pending.where((d) => d.compareTo(today) < 0).length,
    dueToday: pending.contains(today),
    nextSlot: next,
  );
}

/// The "Check-ins" statistic (R23, ED31): "{n} written", then " · {m} missed"
/// when [missed] is above 0, then " · next {Mon d}" only when none are missed,
/// the experiment is [running] and a future slot ([nextSlot], `yyyy-MM-dd`)
/// exists.
String experimentCheckInStatistic({
  required int written,
  required int missed,
  required bool running,
  required String? nextSlot,
}) {
  final text = StringBuffer('$written written');
  if (missed > 0) {
    text.write(' · $missed missed');
  } else if (running && nextSlot != null) {
    text.write(' · next ${DateFormat('MMM d').format(parseIsoDate(nextSlot))}');
  }
  return text.toString();
}
