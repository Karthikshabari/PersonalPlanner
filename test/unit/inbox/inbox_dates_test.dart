import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/inbox/domain/inbox_dates.dart';
import 'package:personal_planner/features/inbox/domain/inbox_session_text.dart';
import 'package:personal_planner/features/inbox/domain/inbox_status.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  DateTime planner(int y, int m, int d, [int hour = 0, int minute = 0]) =>
      PlannerTimeZone.calendarDate(y, m, d, hour: hour, minute: minute);

  // Monday 2026-10-12 12:00.
  final now = planner(2026, 10, 12, 12);

  group('window', () {
    test('14 dates from today', () {
      final dates = inboxWindowDates(now);
      expect(dates, hasLength(14));
      expect(dates.first, '2026-10-12');
      expect(dates.last, '2026-10-25');
    });

    test('crosses a month end and a year end', () {
      final dates = inboxWindowDates(planner(2026, 12, 25, 8));
      expect(dates[6], '2026-12-31');
      expect(dates[7], '2027-01-01');
      expect(dates.last, '2027-01-07');
      expect(inboxWindowDates(planner(2026, 2, 20)).last, '2026-03-05');
    });

    test('is by planner date: 23:30 is still today, a UTC midnight is not', () {
      expect(
        inboxWindowDates(planner(2026, 10, 12, 23, 30)).first,
        '2026-10-12',
      );
      // 2026-10-12 19:00 UTC is 00:30 on the 13th in Asia/Kolkata.
      expect(
        inboxWindowDates(DateTime.utc(2026, 10, 12, 19)).first,
        '2026-10-13',
      );
    });

    group('across a DST change', () {
      late String restore;
      setUpAll(() {
        restore = 'Asia/Kolkata';
        PlannerTimeZone.initialize(identifier: 'America/New_York');
      });
      tearDownAll(() => PlannerTimeZone.initialize(identifier: restore));

      test(
        'every date exists once, in order, with no skipped or repeated day',
        () {
          // US clocks go back on 2026-11-01.
          final start = PlannerTimeZone.calendarDate(2026, 10, 28, hour: 12);
          final dates = inboxWindowDates(start);
          expect(dates.first, '2026-10-28');
          expect(dates[4], '2026-11-01');
          expect(dates[5], '2026-11-02');
          expect(dates.last, '2026-11-10');
          expect(dates.toSet(), hasLength(14));
        },
      );

      test(
        'a 09:00 slot keeps its wall-clock time on both sides of the change',
        () {
          final before = inboxSlotStart('2026-10-31');
          final after = inboxSlotStart('2026-11-02');
          expect(PlannerTimeZone.toPlannerLocal(before).hour, 9);
          expect(PlannerTimeZone.toPlannerLocal(after).hour, 9);
          // 25 hours apart in UTC terms across the extra hour (2 days = 49 h).
          expect(after.difference(before).inHours, 49);
        },
      );
    });
  });

  group('slots', () {
    InboxSlot slot(int day, int hour, {int minutes = 60}) =>
        InboxSlot(start: planner(2026, 10, 12 + day, hour), lengthMin: minutes);

    test('end and date follow the start', () {
      final s = slot(1, 23, minutes: 90);
      expect(s.date, '2026-10-13');
      expect(s.end, planner(2026, 10, 14, 0, 30));
      expect(s, slot(1, 23, minutes: 90));
      expect(s.hashCode, slot(1, 23, minutes: 90).hashCode);
    });

    test(
      'today is disabled after the chosen time and enabled when it is later',
      () {
        expect(inboxSlotError(slot(0, 9), now), isNotNull);
        expect(
          inboxSlotError(slot(0, 12), now),
          isNotNull,
          reason: 'now exactly',
        );
        expect(inboxSlotError(slot(0, 13), now), isNull);
        expect(inboxSlotError(slot(0, 23), now), isNull);
      },
    );

    test('inside the window yes, day 14 and the past no', () {
      expect(inboxSlotError(slot(13, 9), now), isNull);
      expect(inboxSlotError(slot(14, 9), now), isNotNull);
      expect(inboxSlotError(slot(-1, 9), now), isNotNull);
    });

    test('lengths', () {
      for (final minutes in inboxSlotLengths) {
        expect(inboxSlotError(slot(1, 9, minutes: minutes), now), isNull);
      }
      expect(inboxSlotError(slot(1, 9, minutes: 45), now), isNotNull);
      expect(inboxSlotError(slot(1, 9, minutes: 0), now), isNotNull);
    });

    test('validateInboxSlots: duplicates, count, and a clean list', () {
      validateInboxSlots([slot(1, 9), slot(2, 9)], now);
      validateInboxSlots(const [], now);
      expect(
        () => validateInboxSlots([slot(1, 9), slot(1, 15)], now),
        throwsArgumentError,
      );
      expect(
        () =>
            validateInboxSlots([for (var i = 0; i < 15; i++) slot(i, 18)], now),
        throwsArgumentError,
      );
    });
  });

  group('quick picks', () {
    test('tomorrow, next 3 days, clear', () {
      expect(inboxQuickPickDates(InboxQuickPick.tomorrow, now), ['2026-10-13']);
      expect(inboxQuickPickDates(InboxQuickPick.nextThreeDays, now), [
        '2026-10-13',
        '2026-10-14',
        '2026-10-15',
      ]);
      expect(inboxQuickPickDates(InboxQuickPick.clear, now), isEmpty);
    });

    test('next 5 weekdays from a Monday are Tue..Fri then Mon', () {
      expect(inboxQuickPickDates(InboxQuickPick.nextFiveWeekdays, now), [
        '2026-10-13',
        '2026-10-14',
        '2026-10-15',
        '2026-10-16',
        '2026-10-19',
      ]);
    });

    test('on a Friday the weekdays start the next Monday', () {
      // 2026-10-16 is a Friday.
      expect(
        inboxQuickPickDates(
          InboxQuickPick.nextFiveWeekdays,
          planner(2026, 10, 16, 10),
        ),
        ['2026-10-19', '2026-10-20', '2026-10-21', '2026-10-22', '2026-10-23'],
      );
    });

    test('on a Sunday tomorrow is a Monday', () {
      // 2026-10-18 is a Sunday.
      final sunday = planner(2026, 10, 18, 10);
      expect(inboxQuickPickDates(InboxQuickPick.tomorrow, sunday), [
        '2026-10-19',
      ]);
      expect(inboxQuickPickDates(InboxQuickPick.nextFiveWeekdays, sunday), [
        '2026-10-19',
        '2026-10-20',
        '2026-10-21',
        '2026-10-22',
        '2026-10-23',
      ]);
    });

    test('next 3 days across a month end', () {
      expect(
        inboxQuickPickDates(
          InboxQuickPick.nextThreeDays,
          planner(2026, 10, 30),
        ),
        ['2026-10-31', '2026-11-01', '2026-11-02'],
      );
    });
  });

  group('replaceable and after-window sessions', () {
    InboxSessionFacts s(
      String id,
      DateTime start, {
      TaskStatus status = TaskStatus.planned,
      DateTime? deletedAt,
    }) => InboxSessionFacts(
      id: id,
      itemId: 'item',
      title: id,
      start: start,
      end: start.add(const Duration(hours: 1)),
      status: status,
      deletedAt: deletedAt,
      createdAt: planner(2026, 10, 1),
    );

    test('only planned, future, in-window, live sessions, soonest first', () {
      final sessions = [
        s('late', planner(2026, 10, 20, 9)),
        s('soon', planner(2026, 10, 13, 9)),
        s('started', planner(2026, 10, 12, 11, 30)),
        s('past', planner(2026, 10, 12, 8)),
        s('progress', planner(2026, 10, 14, 9), status: TaskStatus.inProgress),
        s('done', planner(2026, 10, 15, 9), status: TaskStatus.completed),
        s('skipped', planner(2026, 10, 15, 9), status: TaskStatus.skipped),
        s('carried', planner(2026, 10, 15, 9), status: TaskStatus.rescheduled),
        s(
          'deleted',
          planner(2026, 10, 16, 9),
          deletedAt: planner(2026, 10, 12),
        ),
        s('after', planner(2026, 10, 26, 9)),
        s('edge', planner(2026, 10, 25, 23)),
      ];
      expect(replaceableInboxSessions(sessions, now).map((x) => x.id), [
        'soon',
        'late',
        'edge',
      ]);
    });

    test('after-window upcoming sessions are reported', () {
      final sessions = [
        s('in', planner(2026, 10, 25, 23)),
        s('after', planner(2026, 10, 26, 9)),
        s('far', planner(2026, 11, 20, 9)),
        s('after-done', planner(2026, 10, 27, 9), status: TaskStatus.completed),
        s('after-deleted', planner(2026, 10, 28, 9), deletedAt: now),
      ];
      expect(inboxAfterWindowSessions(sessions, now).map((x) => x.id), [
        'after',
        'far',
      ]);
    });
  });

  group('overlaps with Day', () {
    Task block(
      String id,
      DateTime start,
      int minutes, {
      TaskStatus status = TaskStatus.planned,
    }) => Task(
      id: id,
      title: id,
      startTime: start,
      endTime: start.add(Duration(minutes: minutes)),
      status: status,
      createdAt: planner(2026, 10, 1),
      updatedAt: planner(2026, 10, 1),
    );

    final slots = [
      InboxSlot(start: planner(2026, 10, 13, 9), lengthMin: 60),
      InboxSlot(start: planner(2026, 10, 14, 9), lengthMin: 60),
    ];

    test('reports the overlapping blocks per slot date', () {
      final result = inboxSlotOverlaps(
        slots: slots,
        windowTasks: [
          block('gym', planner(2026, 10, 13, 9, 30), 60),
          block('adjacent', planner(2026, 10, 14, 10), 60),
        ],
      );
      expect(result.keys, ['2026-10-13']);
      expect(result['2026-10-13']!.single.id, 'gym');
    });

    test('cancelled and rescheduled blocks never conflict', () {
      final result = inboxSlotOverlaps(
        slots: slots,
        windowTasks: [
          block(
            'c',
            planner(2026, 10, 13, 9),
            60,
            status: TaskStatus.cancelled,
          ),
          block(
            'r',
            planner(2026, 10, 14, 9),
            60,
            status: TaskStatus.rescheduled,
          ),
        ],
      );
      expect(result, isEmpty);
    });

    test("the item's own replaceable sessions are excluded", () {
      final result = inboxSlotOverlaps(
        slots: slots,
        windowTasks: [
          block('mine', planner(2026, 10, 13, 9), 60),
          block('other', planner(2026, 10, 13, 9), 60),
        ],
        replaceableIds: {'mine'},
      );
      expect(result['2026-10-13']!.map((t) => t.id), ['other']);
    });
  });

  group('session text', () {
    test('first non-empty line is the title, the rest the description', () {
      final text = inboxSessionText('  \n  Buy a lamp  \n\n for the desk \n');
      expect(text.title, 'Buy a lamp');
      expect(text.description, 'for the desk');
    });

    test('one line has no description; blank text has no title', () {
      expect(inboxSessionText('Just this').description, isNull);
      expect(inboxSessionText(' \n \n').title, '');
      expect(inboxSessionText('').description, isNull);
    });

    test('long titles clip to 500 UTF-16 units without splitting an emoji', () {
      final plain = inboxSessionText('x' * 600).title;
      expect(plain.length, 500);
      // 499 letters then an emoji (2 units) would end mid-pair at 500.
      final emoji = inboxSessionText('${'x' * 499}😀 tail').title;
      expect(emoji.length, 499);
      expect(emoji.codeUnits.last, isNot(inInclusiveRange(0xD800, 0xDBFF)));
      expect(clipUtf16('😀😀', 3), '😀');
      expect(clipUtf16('abc', 10), 'abc');
    });
  });
}
