import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/analytics/presentation/widgets/analytics_cards.dart'
    show formatMinutes;
import 'package:personal_planner/features/experiments/domain/experiment_chart_buckets.dart';
import 'package:personal_planner/features/experiments/domain/experiment_days.dart';

import '../../helpers/experiment_fixtures.dart';
import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  ExperimentChartData chart({
    String start = '2026-10-05',
    String end = '2026-11-03',
    int weekday = 60,
    int weekend = 90,
    Set<String> leave = const {},
    Map<String, DayMinutes> minutes = const {},
    String today = '2026-10-20',
    bool running = true,
    required double width,
  }) {
    final experiment = testExperiment(
      start: start,
      end: end,
      weekday: weekday,
      weekend: weekend,
    );
    return buildExperimentChart(
      days: buildExperimentDays(experiment, leave),
      minutesByDay: minutes,
      today: today,
      running: running,
      width: width,
      formatDuration: formatMinutes,
    );
  }

  group('grouping', () {
    test('exactly 6 pixels per bar still shows days', () {
      // 30 days.
      expect(chart(width: 180).grouping, ExperimentChartGrouping.days);
      expect(chart(width: 179.9).grouping, ExperimentChartGrouping.weeks);
    });

    test('weeks give way to months at 6 pixels per week', () {
      // Oct 5 to Nov 3 spans 5 Monday-based weeks.
      final weeks = chart(width: 30);
      expect(weeks.grouping, ExperimentChartGrouping.weeks);
      expect(weeks.buckets, hasLength(5));
      expect(chart(width: 29.9).grouping, ExperimentChartGrouping.months);
    });

    test('months are used even when their bars are narrow', () {
      final data = chart(width: 10);
      expect(data.grouping, ExperimentChartGrouping.months);
      expect(data.buckets, hasLength(2));
    });

    test('captions and grouping notes', () {
      final days = chart(width: 400);
      expect(
        days.caption,
        "Minutes per day. The dashed outline is that day's target.",
      );
      expect(days.groupingNote, isNull);

      final weeks = chart(width: 100);
      expect(
        weeks.caption,
        "Minutes per week. The dashed outline is that week's target.",
      );
      expect(
        weeks.groupingNote,
        "Showing weeks because 30 days don't fit on this screen.",
      );

      final months = chart(width: 10);
      expect(
        months.caption,
        "Minutes per month. The dashed outline is that month's target.",
      );
      expect(
        months.groupingNote,
        "Showing months because 30 days don't fit on this screen.",
      );
    });

    test('summary for screen readers', () {
      expect(
        experimentChartSummary(
          'Minutes per day. The dashed outline is that day\'s target.',
          '2026-10-05',
          '2026-11-03',
        ),
        "Minutes per day. The dashed outline is that day's target. "
        'Oct 5 to Nov 3.',
      );
    });
  });

  group('week buckets', () {
    test('are clipped at the window edges', () {
      // Wednesday Oct 7 to Tuesday Oct 20.
      final data = chart(start: '2026-10-07', end: '2026-10-20', width: 20);
      expect(data.grouping, ExperimentChartGrouping.weeks);
      expect(data.buckets.map((b) => b.label), [
        'Oct 7 to 11',
        'Oct 12 to 18',
        'Oct 19 to 20',
      ]);
      expect(data.buckets.map((b) => b.dayCount), [5, 7, 2]);
      expect(data.buckets.first.firstDate, '2026-10-07');
      expect(data.buckets.last.lastDate, '2026-10-20');
    });

    test('a week across two months names both', () {
      final data = chart(start: '2026-09-28', end: '2026-10-04', width: 6);
      expect(data.buckets.single.label, 'Sep 28 to Oct 4');
    });

    test('a one-day bucket is labelled with its date alone', () {
      // Sunday Oct 11 to Monday Oct 19 clips both outer weeks to one day.
      final data = chart(start: '2026-10-11', end: '2026-10-19', width: 20);
      expect(data.grouping, ExperimentChartGrouping.weeks);
      expect(data.buckets.map((b) => b.label), [
        'Oct 11',
        'Oct 12 to 18',
        'Oct 19',
      ]);
    });

    test('sums done minutes and targets and writes the tap line', () {
      // Weekday 50 and weekend 70: a full week targets 390 minutes.
      final data = chart(
        start: '2026-10-12',
        end: '2026-10-18',
        weekday: 50,
        weekend: 70,
        minutes: const {
          '2026-10-12': DayMinutes(doneMin: 200),
          '2026-10-13': DayMinutes(doneMin: 110),
        },
        width: 6,
      );
      final week = data.buckets.single;
      expect(data.grouping, ExperimentChartGrouping.weeks);
      expect(week.doneMin, 310);
      expect(week.targetMin, 390);
      expect(week.tapLine, 'Oct 12 to 18: 5h 10m of 6h 30m');
    });
  });

  group('month buckets', () {
    test('sums and tap line', () {
      // October 2026 has 22 weekdays and 9 weekend days: 22*60 + 9*20 = 1500.
      final data = chart(
        start: '2026-10-01',
        end: '2026-10-31',
        weekday: 60,
        weekend: 20,
        minutes: const {'2026-10-05': DayMinutes(doneMin: 1270)},
        width: 10,
      );
      expect(data.grouping, ExperimentChartGrouping.months);
      final month = data.buckets.single;
      expect(month.targetMin, 1500);
      expect(month.doneMin, 1270);
      expect(month.label, 'October');
      expect(month.tapLine, 'October: 21h 10m of 25h');
    });

    test('a long window is split by calendar month', () {
      final data = chart(start: '2026-10-15', end: '2027-01-10', width: 10);
      expect(data.buckets.map((b) => b.label), [
        'October',
        'November',
        'December',
        'January',
      ]);
      expect(data.buckets.first.firstDate, '2026-10-15');
      expect(data.buckets.last.lastDate, '2027-01-10');
    });
  });

  group('day buckets', () {
    test('tap line for a day and for a Leave day', () {
      final data = chart(
        start: '2026-10-12',
        end: '2026-10-14',
        leave: const {'2026-10-13'},
        minutes: const {'2026-10-12': DayMinutes(doneMin: 45)},
        width: 300,
      );
      expect(data.grouping, ExperimentChartGrouping.days);
      expect(data.buckets[0].tapLine, 'Mon Oct 12: 45m of 1h target');
      expect(data.buckets[1].tapLine, 'Tue Oct 13: Leave');
      expect(data.buckets[1].isLeaveOrHoliday, isTrue);
      expect(data.buckets[0].isLeaveOrHoliday, isFalse);
    });

    test('future and today flags follow today', () {
      final data = chart(
        start: '2026-10-12',
        end: '2026-10-16',
        today: '2026-10-14',
        width: 300,
      );
      expect(data.buckets.map((b) => b.isFuture), [
        false,
        false,
        false,
        true,
        true,
      ]);
      expect(data.buckets.map((b) => b.isToday), [
        false,
        false,
        true,
        false,
        false,
      ]);
    });

    test('a week containing today is not a future bucket', () {
      final data = chart(
        start: '2026-10-12',
        end: '2026-10-25',
        today: '2026-10-14',
        width: 12,
      );
      expect(data.grouping, ExperimentChartGrouping.weeks);
      expect(data.buckets[0].isFuture, isFalse);
      expect(data.buckets[0].isToday, isTrue);
      expect(data.buckets[1].isFuture, isTrue);
      expect(data.buckets[1].isToday, isFalse);
    });

    test('an experiment starting in the future is all outlines', () {
      final data = chart(
        start: '2026-10-12',
        end: '2026-10-14',
        today: '2026-10-01',
        width: 300,
      );
      expect(data.buckets.every((b) => b.isFuture), isTrue);
      expect(data.buckets.any((b) => b.isToday), isFalse);
    });

    test('a concluded experiment has no future bars and no today dot', () {
      final data = chart(
        start: '2026-10-12',
        end: '2026-10-14',
        today: '2026-10-13',
        running: false,
        width: 300,
      );
      expect(data.buckets.any((b) => b.isFuture || b.isToday), isFalse);
    });
  });

  test('buckets compare by value', () {
    final a = chart(width: 300).buckets;
    final b = chart(width: 300).buckets;
    expect(a, b);
    expect(a.first.hashCode, b.first.hashCode);
  });
}
