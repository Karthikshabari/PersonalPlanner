import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/day_context.dart';
import 'package:personal_planner/features/day_context/domain/break_day.dart';
import 'package:personal_planner/features/day_context/domain/day_context_presets.dart';

DayContext _context(DayContextKind kind, {String? label, String? date}) =>
    DayContext(
      id: 'c-${date ?? '2026-09-23'}',
      date: date ?? '2026-09-23',
      kind: kind,
      customLabel: label,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
    );

void main() {
  group('isBreakDay with the preset lookup', () {
    test('a day whose label is a break preset is a break', () {
      final rule = BreakDayRule(defaultDayContextPresets);
      expect(rule.breakLabel(_context(DayContextKind.leave)), 'Leave');
      expect(
        rule.breakLabel(_context(DayContextKind.holiday)),
        'Holiday / Festival',
      );
      expect(
        rule.isBreakDay(_context(DayContextKind.custom, label: 'Rest Day')),
        isTrue,
      );
      expect(rule.isBreakDay(_context(DayContextKind.office)), isFalse);
      expect(rule.isBreakDay(null), isFalse);
    });

    test('case and spaces are ignored', () {
      final rule = BreakDayRule(defaultDayContextPresets);
      expect(
        rule.breakLabel(_context(DayContextKind.custom, label: 'rest  day')),
        'rest  day',
      );
    });

    test('a switched-off preset is not a break', () {
      final presets = [
        for (final p in defaultDayContextPresets)
          p.name == 'Leave' ? p.copyWith(isBreak: false) : p,
      ];
      expect(
        BreakDayRule(presets).isBreakDay(_context(DayContextKind.leave)),
        isFalse,
      );
    });

    test(
      'a renamed preset leaves its old days with a label that is no break',
      () {
        final presets = [
          for (final p in defaultDayContextPresets)
            p.name == 'Leave' ? p.copyWith(name: 'Annual leave') : p,
        ];
        final rule = BreakDayRule(presets);
        final oldDay = _context(DayContextKind.leave);
        expect(oldDay.label, 'Leave');
        expect(rule.isBreakDay(oldDay), isFalse);
        expect(
          rule.isBreakDay(
            _context(DayContextKind.custom, label: 'Annual leave'),
          ),
          isTrue,
        );
      },
    );

    test('a deleted preset is no break; a re-added one with the label is', () {
      final without = [
        for (final p in defaultDayContextPresets)
          if (p.name != 'Rest Day') p,
      ];
      final day = _context(DayContextKind.custom, label: 'Rest Day');
      expect(BreakDayRule(without).isBreakDay(day), isFalse);
      expect(
        BreakDayRule([
          ...without,
          const DayContextPreset('Rest day', isBreak: true),
        ]).isBreakDay(day),
        isTrue,
      );
    });

    test('an old custom label is never a break', () {
      final rule = BreakDayRule(defaultDayContextPresets);
      expect(
        rule.isBreakDay(_context(DayContextKind.custom, label: 'Family visit')),
        isFalse,
      );
    });

    test('breakDates keeps only the break days', () {
      final rule = BreakDayRule(defaultDayContextPresets);
      expect(
        rule.breakDates([
          _context(DayContextKind.leave, date: '2026-09-21'),
          _context(DayContextKind.office, date: '2026-09-22'),
          _context(
            DayContextKind.custom,
            label: 'Rest Day',
            date: '2026-09-23',
          ),
        ]),
        {'2026-09-21': 'Leave', '2026-09-23': 'Rest Day'},
      );
    });

    test('rules are equal when the same names are breaks', () {
      final renamedOffice = [
        for (final p in defaultDayContextPresets)
          p.name == 'Office Day' ? p.copyWith(name: 'Office') : p,
      ];
      expect(
        BreakDayRule(renamedOffice),
        BreakDayRule(defaultDayContextPresets),
      );
      expect(
        BreakDayRule(const [DayContextPreset('Leave', isBreak: true)]),
        isNot(BreakDayRule(defaultDayContextPresets)),
      );
    });
  });
}
