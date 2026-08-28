import 'package:rrule/rrule.dart';

import '../../../core/utils/date_utils.dart';

/// Which entry of the recurrence dropdown is selected.
enum RepeatPreset { never, daily, weekdays, weekly, monthly, custom }

/// Configuration captured by the custom recurrence dialog.
class CustomRecurrenceConfig {
  final Frequency frequency;
  final int interval;
  /// Weekdays (DateTime.monday..sunday) for weekly rules; empty otherwise.
  final Set<int> byWeekDays;
  /// Optional inclusive last date (`null` = never ends).
  final DateTime? endDate;

  const CustomRecurrenceConfig({
    required this.frequency,
    this.interval = 1,
    this.byWeekDays = const {},
    this.endDate,
  });
}

/// Thin wrapper around the `rrule` package for parsing, evaluating and
/// building RFC 5545 recurrence rules (planner.md Chunk 4 #2).
///
/// Stored strings omit the `RRULE:` prefix (architecture.md §8 examples),
/// e.g. `FREQ=WEEKLY;BYDAY=MO,WE`.
abstract final class RruleUtils {
  static const _weekdayCodes = {
    DateTime.monday: 'MO',
    DateTime.tuesday: 'TU',
    DateTime.wednesday: 'WE',
    DateTime.thursday: 'TH',
    DateTime.friday: 'FR',
    DateTime.saturday: 'SA',
    DateTime.sunday: 'SU',
  };

  static RecurrenceRule parse(String rrule) =>
      // The package's decoder expects a full iCalendar property line.
      RecurrenceRule.fromString(
          rrule.toUpperCase().startsWith('RRULE:') ? rrule : 'RRULE:$rrule');

  static String encode(RecurrenceRule rule) =>
      rule.toString().replaceFirst(RegExp(r'^RRULE:', caseSensitive: false), '');

  /// True when the rule produces an occurrence on [date]'s calendar day.
  ///
  /// The package requires UTC DateTimes but ignores the time zone — local
  /// wall-clock values are passed with `isUtc: true`.
  static bool occursOnDate(String rrule, DateTime ruleStartDate, DateTime date) {
    final dayStart = startOfDay(date);
    // Occurrences cannot precede DTSTART; also guards the package's
    // `after >= start` assertion.
    if (dayStart.isBefore(startOfDay(ruleStartDate))) return false;
    try {
      final rule = parse(rrule);
      final start = _wallClockUtc(startOfDay(ruleStartDate));
      final dayEnd = _wallClockUtc(dayStart.add(const Duration(days: 1)));
      // Lower bound of the queried window; `after` is exclusive and must
      // stay >= DTSTART, so it is omitted entirely when the window begins
      // at or before DTSTART.
      final windowStart =
          _wallClockUtc(dayStart).subtract(const Duration(microseconds: 1));
      final after = windowStart.isAfter(start) ? windowStart : null;
      return rule
          .getAllInstances(start: start, after: after, before: dayEnd)
          .isNotEmpty;
    } on Exception catch (_) {
      return false;
    } on Error {
      return false;
    }
  }

  static String? presetToRrule(RepeatPreset preset, DateTime anchorDate) =>
      switch (preset) {
        RepeatPreset.never => null,
        RepeatPreset.daily => 'FREQ=DAILY',
        RepeatPreset.weekdays => 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR',
        RepeatPreset.weekly =>
          'FREQ=WEEKLY;BYDAY=${_weekdayCodes[anchorDate.weekday]}',
        RepeatPreset.monthly => 'FREQ=MONTHLY;BYMONTHDAY=${anchorDate.day}',
        RepeatPreset.custom => null,
      };

  static String configToRrule(CustomRecurrenceConfig config, DateTime anchorDate) {
    final buffer = StringBuffer('FREQ=${switch (config.frequency) {
      Frequency.daily => 'DAILY',
      Frequency.weekly => 'WEEKLY',
      Frequency.monthly => 'MONTHLY',
      _ => 'DAILY',
    }}');
    if (config.interval > 1) buffer.write(';INTERVAL=${config.interval}');
    if (config.frequency == Frequency.weekly) {
      final days = (config.byWeekDays.isEmpty
              ? {anchorDate.weekday}
              : config.byWeekDays)
          .map((d) => _weekdayCodes[d])
          .whereType<String>()
          .toList()
        ..sort();
      if (days.isNotEmpty) buffer.write(';BYDAY=${days.join(',')}');
    }
    if (config.frequency == Frequency.monthly && config.byWeekDays.isNotEmpty) {
      // nth-weekday support is out of scope for v1; fall back to the
      // anchor date's day of month.
      buffer.write(';BYMONTHDAY=${anchorDate.day}');
    }
    if (config.endDate != null) {
      buffer.write(';UNTIL=${isoDateString(startOfDay(config.endDate!)).replaceAll('-', '')}');
    }
    return buffer.toString();
  }

  /// Maps an RRULE string back to a dropdown preset where possible.
  static RepeatPreset detectPreset(String rrule) {
    final normalized =
        rrule.toUpperCase().replaceAll(RegExp(r'\s'), '').split(';');
    String freq = '';
    List<String> byDay = [];
    String? byMonthDay;
    var interval = 1;
    var hasOtherParts = false;
    for (final part in normalized) {
      final (key, value) = switch (part.split('=')) {
        [final k, final v] => (k, v),
        _ => ('', ''),
      };
      switch (key) {
        case 'FREQ':
          freq = value;
        case 'BYDAY':
          byDay = value.split(',');
        case 'BYMONTHDAY':
          byMonthDay = value;
        case 'INTERVAL':
          interval = int.tryParse(value) ?? 1;
        case '':
          break;
        case _:
          hasOtherParts = true;
      }
    }
    if (!hasOtherParts && freq == 'DAILY' && interval == 1) {
      return RepeatPreset.daily;
    }
    if (!hasOtherParts &&
        freq == 'WEEKLY' &&
        interval == 1 &&
        byDay.join(',') == 'MO,TU,WE,TH,FR') {
      return RepeatPreset.weekdays;
    }
    if (!hasOtherParts &&
        freq == 'WEEKLY' &&
        interval == 1 &&
        byDay.length == 1) {
      return RepeatPreset.weekly;
    }
    if (!hasOtherParts &&
        freq == 'MONTHLY' &&
        interval == 1 &&
        byMonthDay != null &&
        int.tryParse(byMonthDay) != null) {
      return RepeatPreset.monthly;
    }
    return RepeatPreset.custom;
  }

  static String weekdayCode(int weekday) => _weekdayCodes[weekday] ?? '';

  /// Best-effort human-readable description, e.g.
  /// "Every week on Tuesday". Falls back to the raw RRULE string when the
  /// rule cannot be fully converted to text or l10n fails to load.
  static Future<String> describe(String rrule) async {
    try {
      final rule = parse(rrule);
      if (!rule.canFullyConvertToText) return rrule;
      final l10n = await RruleL10nEn.create();
      return rule.toText(l10n: l10n);
    } catch (_) {
      return rrule;
    }
  }

  static DateTime _wallClockUtc(DateTime local) =>
      DateTime(local.year, local.month, local.day, local.hour, local.minute)
          .copyWith(isUtc: true);
}
