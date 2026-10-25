import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/review/data/review_repository.dart';
import 'package:personal_planner/features/review/domain/review_search.dart';

import '../../helpers/sqlite_setup.dart';

DateTime d(int month, int day) =>
    PlannerTimeZone.calendarDate(2026, month, day);

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late ReviewRepository reviews;

  // Wednesday 2026-10-14; the Monday-start week began on the 12th.
  final today = PlannerTimeZone.calendarDate(2026, 10, 14, hour: 12);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    reviews = ReviewRepository(db);
  });

  tearDown(() {
    plannerWeekStartDay = WeekStartDay.monday;
    return db.close();
  });

  final stamp = DateTime.utc(2026, 1, 1);

  Future<String> task(
    String id,
    String title,
    DateTime start, {
    bool inbox = false,
    bool deleted = false,
  }) async {
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: id,
            title: title,
            startTime: Value(start),
            endTime: Value(start.add(const Duration(minutes: 30))),
            isInbox: Value(inbox),
            deletedAt: Value(deleted ? stamp : null),
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
    return id;
  }

  Future<ReviewSearchIndex> load() =>
      ReviewSearchIndexLoader(db).load(today: today);

  DateTime at(DateTime day, int hour) =>
      PlannerTimeZone.calendarDate(day.year, day.month, day.day, hour: hour);

  test('groups titles by local day, newest day first', () async {
    await task('a', 'Alpha late', at(d(10, 5), 22));
    await task('b', 'Beta early', at(d(10, 5), 6));
    await task('c', 'Gamma', at(d(10, 7), 9));

    final index = await load();

    expect(index.days.map((day) => isoDateString(day.date)), [
      '2026-10-07',
      '2026-10-05',
    ]);
    // Tasks are ordered by start inside a day.
    expect(index.days[1].texts.map((t) => t.text), [
      'Beta early',
      'Alpha late',
    ]);
    expect(
      index.days[1].texts.every((t) => t.lower == t.text.toLowerCase()),
      isTrue,
    );
  });

  test(
    'Daily search excludes future days, deleted tasks and Inbox ideas',
    () async {
      await task('past', 'Past one', at(d(10, 13), 9));
      await task('now', 'Today one', at(d(10, 14), 20));
      await task('future', 'Tomorrow one', at(d(10, 15), 9));
      await task('gone', 'Deleted one', at(d(10, 13), 10), deleted: true);
      await task('idea', 'Inbox one', at(d(10, 13), 11), inbox: true);

      final index = await load();

      // The index keeps the rest of this week for Weekly search; the Daily
      // filter is what keeps tomorrow out.
      expect(searchReviewDays(index, 'one').map((h) => h.snippet), [
        'Today one',
        'Past one',
      ]);
      await reviews.saveReviewDraft(
        date: d(10, 15),
        mood: 2,
        note: 'Future note',
        taskReasons: const {},
      );
      final withFutureNote = await load();
      expect(searchReviewDays(withFutureNote, 'future note'), isEmpty);
      expect(searchReviewWeeks(withFutureNote, 'future note'), isEmpty);
    },
  );

  test('the index remembers today as the start of the day', () async {
    expect((await load()).today, d(10, 14));
  });

  group('current week', () {
    // Wednesday 2026-10-14 (Monday-start week 12th to 18th).
    test('Weekly finds a task on a later day, Daily does not', () async {
      await task('fri', 'Friday dentist', at(d(10, 16), 9));
      await task('wed', 'Wednesday dentist', at(d(10, 14), 9));

      final index = await load();

      expect(
        searchReviewWeeks(index, 'dentist').map((h) => isoDateString(h.date)),
        ['2026-10-12'],
      );
      expect(searchReviewWeeks(index, 'friday'), hasLength(1));
      expect(searchReviewDays(index, 'dentist').map((h) => h.snippet), [
        'Wednesday dentist',
      ]);
      expect(searchReviewDays(index, 'friday'), isEmpty);
    });

    test('the last day of the week is found, a later week is not', () async {
      await task('sun', 'Sunday dentist', at(d(10, 18), 23));
      await task('next', 'Next week dentist', at(d(10, 19), 0));
      await task('later', 'Later dentist', at(d(10, 28), 9));

      final index = await load();

      expect(searchReviewWeeks(index, 'sunday'), hasLength(1));
      expect(searchReviewWeeks(index, 'next week'), isEmpty);
      expect(searchReviewWeeks(index, 'later'), isEmpty);
      expect(searchReviewDays(index, 'dentist'), isEmpty);
    });

    test('a Sunday week start reaches Saturday, not the next Sunday', () async {
      plannerWeekStartDay = WeekStartDay.sunday;
      // The Sunday-start week is Oct 11 to 17.
      await task('sat', 'Saturday dentist', at(d(10, 17), 9));
      await task('sun', 'Next Sunday dentist', at(d(10, 18), 9));

      final index = await load();

      expect(
        searchReviewWeeks(index, 'dentist').map((h) => isoDateString(h.date)),
        ['2026-10-11'],
      );
      expect(searchReviewWeeks(index, 'next sunday'), isEmpty);
      expect(searchReviewDays(index, 'dentist'), isEmpty);
    });

    test('a Monday week start reaches Sunday', () async {
      await task('sun', 'Sunday dentist', at(d(10, 18), 9));
      expect(searchReviewWeeks(await load(), 'dentist'), hasLength(1));
    });

    test('on a Sunday-start Sunday the week is the one just begun', () async {
      plannerWeekStartDay = WeekStartDay.sunday;
      final sunday = PlannerTimeZone.calendarDate(2026, 10, 11, hour: 12);
      await task('mon', 'Monday dentist', at(d(10, 12), 9));
      await task('next', 'Next Sunday dentist', at(d(10, 18), 9));

      final index = await ReviewSearchIndexLoader(db).load(today: sunday);

      expect(searchReviewWeeks(index, 'monday'), hasLength(1));
      expect(searchReviewWeeks(index, 'next sunday'), isEmpty);
      expect(searchReviewDays(index, 'monday'), isEmpty);
    });
  });

  group('reasons', () {
    test('only reasons of tasks that start that day are indexed', () async {
      final real = await task('real', 'Write report', at(d(10, 6), 9));
      final other = await task('other', 'Other day', at(d(10, 7), 9));
      await task('gone', 'Deleted', at(d(10, 6), 10), deleted: true);
      await reviews.saveReviewDraft(
        date: d(10, 6),
        mood: 3,
        note: '',
        taskReasons: {
          real: 'Too tired',
          'no-such-task': 'Ghost reason',
          other: 'Wrong day reason',
          'gone': 'Deleted reason',
        },
      );

      final index = await load();
      final day = index.days.singleWhere(
        (day) => isoDateString(day.date) == '2026-10-06',
      );

      expect(
        day.texts
            .where((t) => t.source == ReviewSearchSource.reason)
            .map((t) => t.text),
        ['Too tired'],
      );
      expect(searchReviewDays(index, 'ghost'), isEmpty);
      expect(searchReviewDays(index, 'wrong day'), isEmpty);
      expect(searchReviewDays(index, 'deleted reason'), isEmpty);
      expect(searchReviewWeeks(index, 'ghost'), isEmpty);
      expect(searchReviewDays(index, 'too tired'), hasLength(1));
    });

    test('a day with only a ghost reason is left out', () async {
      await reviews.saveReviewDraft(
        date: d(10, 6),
        mood: 3,
        note: '',
        taskReasons: {'no-such-task': 'Ghost reason'},
      );
      expect((await load()).days, isEmpty);
    });
  });

  test('maps the note, task and reason sources, note first', () async {
    final id = await task('t', 'Write report', at(d(10, 6), 9));
    await reviews.saveReviewDraft(
      date: d(10, 6),
      mood: 3,
      note: '  Slept badly  ',
      taskReasons: {id: 'Too tired'},
    );

    final day = (await load()).days.single;

    expect(day.texts.map((t) => (t.source, t.text)), [
      (ReviewSearchSource.note, 'Slept badly'),
      (ReviewSearchSource.task, 'Write report'),
      (ReviewSearchSource.reason, 'Too tired'),
    ]);
  });

  test('a day with no non-blank text is left out', () async {
    await reviews.saveReviewDraft(
      date: d(10, 6),
      mood: 3,
      note: '   ',
      taskReasons: const {},
    );
    expect((await load()).days, isEmpty);
  });

  test(
    'searchReviewDays returns the first match per day, newest first',
    () async {
      final id = await task('t', 'Plan the trip', at(d(10, 6), 9));
      await reviews.saveReviewDraft(
        date: d(10, 6),
        mood: 3,
        note: 'The TRIP went well',
        taskReasons: {id: 'Booked the trip late'},
      );
      await task('u', 'Trip packing', at(d(10, 9), 9));

      final hits = searchReviewDays(await load(), 'trip');

      expect(hits.map((h) => isoDateString(h.date)), [
        '2026-10-09',
        '2026-10-06',
      ]);
      expect(hits[0].source, ReviewSearchSource.task);
      // The note comes first in the day's texts, so it wins over the task.
      expect(hits[1].source, ReviewSearchSource.note);
      expect(hits[1].snippet, 'The TRIP went well');
      expect(searchReviewDays(await load(), ''), isEmpty);
      expect(searchReviewDays(await load(), 'zzz'), isEmpty);
    },
  );

  test('matching is contiguous', () async {
    await task('t', 'Buy milk today', at(d(10, 6), 9));
    final index = await load();
    expect(searchReviewDays(index, 'buy milk'), hasLength(1));
    expect(searchReviewDays(index, 'milk buy'), isEmpty);
  });

  group('weeks', () {
    Future<void> weekly(DateTime weekStart, String feeling, String note) =>
        reviews.saveWeeklyReviewDraft(
          weekStart: weekStart,
          mood: 2,
          feeling: feeling,
          note: note,
        );

    test(
      'weekly feeling and note win over day texts; order is newest first',
      () async {
        await task('a', 'Garden work', at(d(10, 6), 9)); // week of Oct 5
        await task('b', 'Garden fence', at(d(10, 13), 9)); // week of Oct 12
        await weekly(d(10, 5), 'Muddy garden week', '');
        await weekly(d(9, 28), '', 'Plant the garden early');

        final hits = searchReviewWeeks(await load(), 'garden');

        expect(hits.map((h) => isoDateString(h.date)), [
          '2026-10-12',
          '2026-10-05',
          '2026-09-28',
        ]);
        expect(hits.map((h) => h.source), [
          ReviewSearchSource.task,
          ReviewSearchSource.feeling,
          ReviewSearchSource.weekNote,
        ]);
      },
    );

    test('a weekly review of a future week is not found', () async {
      await weekly(d(10, 19), 'Future garden', '');
      expect(searchReviewWeeks(await load(), 'garden'), isEmpty);
    });

    test('the Daily note is not searched on the Weekly page', () async {
      await reviews.saveReviewDraft(
        date: d(10, 6),
        mood: 3,
        note: 'Only the daily note says kiwi',
        taskReasons: const {},
      );
      final index = await load();
      expect(searchReviewDays(index, 'kiwi'), hasLength(1));
      expect(searchReviewWeeks(index, 'kiwi'), isEmpty);
    });

    test('groups by the Monday week start', () async {
      await task('sun', 'Sunday chore', at(d(10, 11), 9));
      await task('mon', 'Monday chore', at(d(10, 12), 9));

      final hits = searchReviewWeeks(await load(), 'chore');

      expect(hits.map((h) => isoDateString(h.date)), [
        '2026-10-12',
        '2026-10-05',
      ]);
    });

    test(
      'groups by the Sunday week start, keyed under the Monday inside it',
      () async {
        plannerWeekStartDay = WeekStartDay.sunday;
        await task('sat', 'Saturday chore', at(d(10, 10), 9));
        await task('sun', 'Sunday chore', at(d(10, 11), 9));
        // Stored under the Monday of the Sunday-start week Oct 11 - 17.
        await weekly(d(10, 12), 'Slow kiwi week', '');

        final index = await load();
        final chores = searchReviewWeeks(index, 'chore');
        final kiwi = searchReviewWeeks(index, 'kiwi');

        expect(chores.map((h) => isoDateString(h.date)), [
          '2026-10-11',
          '2026-10-04',
        ]);
        expect(kiwi.map((h) => isoDateString(h.date)), ['2026-10-11']);
      },
    );
  });
}
