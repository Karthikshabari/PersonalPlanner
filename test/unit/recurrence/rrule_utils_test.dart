import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/recurring/domain/rrule_utils.dart';
import 'package:rrule/rrule.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  group('RruleUtils.presetToRrule', () {
    // Aug 26 2026 is a Wednesday.
    final anchor = DateTime(2026, 8, 26);

    test('generates the architecture.md §8 example strings', () {
      expect(RruleUtils.presetToRrule(RepeatPreset.daily, anchor), 'FREQ=DAILY');
      expect(RruleUtils.presetToRrule(RepeatPreset.weekdays, anchor),
          'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR');
      expect(RruleUtils.presetToRrule(RepeatPreset.weekly, anchor),
          'FREQ=WEEKLY;BYDAY=WE');
      expect(RruleUtils.presetToRrule(RepeatPreset.monthly, anchor),
          'FREQ=MONTHLY;BYMONTHDAY=26');
      expect(RruleUtils.presetToRrule(RepeatPreset.never, anchor), isNull);
    });

    test('detectPreset round-trips presets', () {
      for (final (preset, rrule) in [
        (RepeatPreset.daily, 'FREQ=DAILY'),
        (RepeatPreset.weekdays, 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR'),
        (RepeatPreset.weekly, 'FREQ=WEEKLY;BYDAY=TU'),
        (RepeatPreset.monthly, 'FREQ=MONTHLY;BYMONTHDAY=15'),
      ]) {
        expect(RruleUtils.detectPreset(rrule), preset, reason: rrule);
      }
      expect(RruleUtils.detectPreset('FREQ=DAILY;INTERVAL=2'),
          RepeatPreset.custom);
      expect(
          RruleUtils.detectPreset('FREQ=MONTHLY;BYDAY=1MO'), RepeatPreset.custom);
    });
  });

  group('RruleUtils.configToRrule', () {
    final anchor = DateTime(2026, 8, 26);

    test('encodes interval and weekday selection', () {
      final config = CustomRecurrenceConfig(
        frequency: Frequency.weekly,
        interval: 2,
        byWeekDays: {DateTime.monday, DateTime.friday},
      );
      expect(RruleUtils.configToRrule(config, anchor),
          'FREQ=WEEKLY;INTERVAL=2;BYDAY=FR,MO');
    });

    test('encodes an end date as UNTIL', () {
      final config = CustomRecurrenceConfig(
        frequency: Frequency.daily,
        endDate: DateTime(2026, 12, 31),
      );
      expect(RruleUtils.configToRrule(config, anchor),
          'FREQ=DAILY;UNTIL=20261231');
    });

    test('falls back to anchor weekday when no days selected', () {
      final config = const CustomRecurrenceConfig(frequency: Frequency.weekly);
      expect(RruleUtils.configToRrule(config, anchor), 'FREQ=WEEKLY;BYDAY=WE');
    });
  });

  group('RruleUtils.parse / encode', () {
    test('round-trips without the RRULE prefix', () {
      final rule = RruleUtils.parse('FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE');
      expect(RruleUtils.encode(rule), 'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE');
    });

    test('occursOnDate evaluates single days', () {
      // Aug 26 2026 = Wednesday.
      expect(RruleUtils.occursOnDate('FREQ=WEEKLY;BYDAY=WE',
          DateTime(2026, 8, 1), DateTime(2026, 8, 26)), isTrue);
      expect(RruleUtils.occursOnDate('FREQ=WEEKLY;BYDAY=TH',
          DateTime(2026, 8, 1), DateTime(2026, 8, 26)), isFalse);
      // Before DTSTART.
      expect(RruleUtils.occursOnDate('FREQ=DAILY',
          DateTime(2026, 9, 1), DateTime(2026, 8, 26)), isFalse);
    });

    test('malformed rules never throw', () {
      expect(RruleUtils.occursOnDate('NOT_A_RULE', DateTime(2026, 1, 1),
          DateTime(2026, 1, 2)), isFalse);
    });

    test('describe returns a human-readable string', () async {
      final text = await RruleUtils.describe('FREQ=DAILY');
      expect(text.toLowerCase(), contains('daily'));
    });
  });
}
